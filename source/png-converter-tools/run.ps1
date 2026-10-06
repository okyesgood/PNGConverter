#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$InputPaths,
    [string]$InputListFile
)

$ErrorActionPreference = 'Stop'
$script:ToolVersion = '3.0.1'
if (-not $PSScriptRoot) {
    throw 'Unable to resolve the tool folder. Please run this file from the tool directory.'
}
$toolDir = [IO.Path]::GetFullPath($PSScriptRoot)
$configPath = Join-Path $toolDir 'config.ini'
$jsxPath = Join-Path $toolDir 'photoshop_convert.jsx'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

function Write-ConsoleAndLog {
    param([string]$Message)
    Write-Host $Message
    if ($script:LogFile) {
        Add-Content -LiteralPath $script:LogFile -Value $Message -Encoding UTF8
    }
}

function Write-LogCopy {
    if ($script:LogFile -and (Test-Path -LiteralPath $script:LogFile)) {
        Copy-Item -LiteralPath $script:LogFile -Destination (Join-Path $logRoot 'latest.log') -Force
    }
}

function Read-Config {
    $config = @{
        Quality = 10
        SkipUpToDate = $true
        ForceOverwrite = $true
        DeleteSourcePng = $false
        TransparentBackground = 'white'
        ConvertToSRGB = $true
    }
    if (Test-Path -LiteralPath $configPath) {
        foreach ($line in Get-Content -LiteralPath $configPath -Encoding UTF8) {
            if ($line -match '^\s*([^;#=]+?)\s*=\s*(.*?)\s*$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                switch ($key) {
                    'Quality' { $config.Quality = [Math]::Max(0, [Math]::Min(12, [int]$value)) }
                    'SkipUpToDate' { $config.SkipUpToDate = $value -match '^(?i:true|1|yes)$' }
                    'ForceOverwrite' { $config.ForceOverwrite = $value -match '^(?i:true|1|yes)$' }
                    'DeleteSourcePng' { $config.DeleteSourcePng = $value -match '^(?i:true|1|yes)$' }
                    'TransparentBackground' { $config.TransparentBackground = $value.ToLowerInvariant() }
                    'ConvertToSRGB' { $config.ConvertToSRGB = $value -match '^(?i:true|1|yes)$' }
                }
            }
        }
    }
    return $config
}

function Get-PhotoshopPath {
    $overrideFile = Join-Path $toolDir 'photoshop.path.txt'
    if (Test-Path -LiteralPath $overrideFile) {
        $candidate = (Get-Content -LiteralPath $overrideFile -Raw -Encoding UTF8).Trim()
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }

    $roots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramW6432,
        "$env:SystemDrive\Adobe",
        "$env:SystemDrive\Program Files\Adobe",
        "$env:SystemDrive\Program Files (x86)\Adobe"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

    $candidates = @(
        "$env:ProgramFiles\Adobe\Adobe Photoshop 2026\Photoshop.exe",
        "$env:ProgramFiles\Adobe\Adobe Photoshop 2025\Photoshop.exe",
        "$env:ProgramFiles\Adobe\Adobe Photoshop 2024\Photoshop.exe",
        "$env:ProgramFiles\Adobe\Adobe Photoshop 2023\Photoshop.exe",
        "$env:ProgramFiles\Adobe\Adobe Photoshop 2022\Photoshop.exe",
        "${env:ProgramFiles(x86)}\Adobe\Adobe Photoshop 2026\Photoshop.exe",
        "${env:ProgramFiles(x86)}\Adobe\Adobe Photoshop 2025\Photoshop.exe",
        "${env:ProgramFiles(x86)}\Adobe\Adobe Photoshop 2024\Photoshop.exe",
        "${env:ProgramFiles(x86)}\Adobe\Adobe Photoshop 2023\Photoshop.exe",
        "${env:ProgramFiles(x86)}\Adobe\Adobe Photoshop 2022\Photoshop.exe"
    )

    foreach ($key in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        $candidates += Get-ItemProperty -Path $key -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like 'Adobe Photoshop*' -and $_.InstallLocation } |
            ForEach-Object { Join-Path $_.InstallLocation 'Photoshop.exe' }
    }

    foreach ($root in $roots) {
        $candidates += Get-ChildItem -LiteralPath $root -Filter Photoshop.exe -Recurse -File -ErrorAction SilentlyContinue |
            ForEach-Object FullName
    }

    return ($candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -Unique -First 1)
}

function New-JsonJob {
    param(
        [string]$InputFile,
        [string]$OutputFile,
        [string]$JobFile,
        [string]$ResultFile,
        [hashtable]$Config
    )
    $job = [ordered]@{
        input = $InputFile
        output = $OutputFile
        result = $ResultFile
        quality = $Config.Quality
        transparentBackground = $Config.TransparentBackground
        convertToSRGB = $Config.ConvertToSRGB
        targetWidth = $Config.TargetWidth
        targetHeight = $Config.TargetHeight
    }
    Write-Utf8NoBom -Path $JobFile -Content ($job | ConvertTo-Json -Compress)
}

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Content
    )
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Normalize-WindowsPath {
    param([string]$Path)
    if ($null -eq $Path) { return $Path }
    $value = [Environment]::ExpandEnvironmentVariables($Path.Trim('"'))
    if ($value -match '^\\{3,}') {
        $value = '\\' + $value.Substring($value.IndexOf('\', 2))
    }
    return $value
}

function Normalize-WindowsPathSafe {
    param([string]$Path)
    if ($null -eq $Path) { return $Path }
    $value = [Environment]::ExpandEnvironmentVariables($Path.Trim('"'))
    $three = ('\' * 3)
    while ($value.StartsWith($three)) { $value = $value.Substring(1) }
    return $value
}

function Convert-PngWithWindowsImage {
    param(
        [string]$InputFile,
        [string]$OutputFile,
        [int]$Quality,
        [string]$Background,
        [int]$TargetWidth,
        [int]$TargetHeight
    )
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $source = $null
    $bitmap = $null
    $graphics = $null
    try {
        $source = [System.Drawing.Image]::FromFile($InputFile)
        if ($TargetWidth -le 0 -or $TargetHeight -le 0) { $TargetWidth = $source.Width; $TargetHeight = $source.Height }
        $bitmap = New-Object System.Drawing.Bitmap($TargetWidth, $TargetHeight, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $color = if ($Background -eq 'black') { [System.Drawing.Color]::Black } else { [System.Drawing.Color]::White }
        $graphics.Clear($color)
        $scale = [Math]::Min($TargetWidth / [double]$source.Width, $TargetHeight / [double]$source.Height)
        $drawWidth = [int][Math]::Round($source.Width * $scale)
        $drawHeight = [int][Math]::Round($source.Height * $scale)
        $drawX = [int][Math]::Floor(($TargetWidth - $drawWidth) / 2)
        $drawY = [int][Math]::Floor(($TargetHeight - $drawHeight) / 2)
        $graphics.DrawImage($source, $drawX, $drawY, $drawWidth, $drawHeight)
        $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
        $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
        $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long][Math]::Min(100, [Math]::Max(1, $Quality * 100 / 12)))
        $bitmap.Save($OutputFile, $codec, $encoderParams)
    } finally {
        if ($graphics) { $graphics.Dispose() }
        if ($bitmap) { $bitmap.Dispose() }
        if ($source) { $source.Dispose() }
    }
}

function Test-OutputImage {
    param([string]$Path, [int]$ExpectedWidth, [int]$ExpectedHeight)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw '输出文件不存在。' }
    $info = Get-Item -LiteralPath $Path
    if ($info.Length -le 0) { throw '输出文件大小为 0。' }
    $image = $null
    try {
        $image = [System.Drawing.Image]::FromFile($Path)
        if ($image.RawFormat.Guid -ne [System.Drawing.Imaging.ImageFormat]::Jpeg.Guid) { throw '输出文件不是有效 JPG。' }
        if ($ExpectedWidth -gt 0 -and ($image.Width -ne $ExpectedWidth -or $image.Height -ne $ExpectedHeight)) {
            throw "输出尺寸不正确：$($image.Width)x$($image.Height)，期望 ${ExpectedWidth}x${ExpectedHeight}。"
        }
        return [pscustomobject]@{ Width = $image.Width; Height = $image.Height; Bytes = $info.Length }
    } finally {
        if ($image) { $image.Dispose() }
    }
}

function Invoke-PhotoshopConversion {
    param(
        [object]$Photoshop,
        [string]$InputFile,
        [string]$OutputFile,
        [hashtable]$Config,
        [string]$WorkDir,
        [string]$RunnerPath
    )
    $safeName = [Guid]::NewGuid().ToString('N')
    $jobFile = Join-Path $WorkDir "$safeName.job.json"
    $resultFile = Join-Path $WorkDir "$safeName.result.json"
    $launcherPath = Join-Path $WorkDir "$safeName.launcher.jsx"
    try {
        New-JsonJob -InputFile $InputFile -OutputFile $OutputFile -JobFile $jobFile -ResultFile $resultFile -Config $Config
        $jobLiteral = $jobFile | ConvertTo-Json -Compress
        $runnerLiteral = $RunnerPath | ConvertTo-Json -Compress
        $launcher = "#target photoshop`r`nvar __PNG_TO_JPG_JOB_FILE = $jobLiteral;`r`n$.evalFile($runnerLiteral);"
        Write-Utf8NoBom -Path $launcherPath -Content $launcher
        $null = $Photoshop.DoJavaScriptFile($launcherPath, @(), 3)
        $deadline = (Get-Date).AddSeconds(120)
        while (-not (Test-Path -LiteralPath $resultFile)) {
            if ((Get-Date) -gt $deadline) { throw 'Photoshop timed out after 120 seconds.' }
            Start-Sleep -Milliseconds 250
        }
        $result = Get-Content -LiteralPath $resultFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $result.ok) {
            $message = if ($result.error) { [string]$result.error } else { 'Photoshop 未返回具体错误信息。' }
            throw $message
        }
    } finally {
        Remove-Item -LiteralPath $jobFile, $resultFile, $launcherPath -Force -ErrorAction SilentlyContinue
    }
}

function Select-InputPaths {
    if ($InputListFile -and (Test-Path -LiteralPath $InputListFile)) {
        return @(Get-Content -LiteralPath $InputListFile -Encoding UTF8 | Where-Object { $_.Trim() })
    }
    if ($InputPaths) { return $InputPaths }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'PNG 转 JPG Web 2.1.0 - 拖入多个文件或文件夹'
    $form.Width = 620
    $form.Height = 220
    $form.StartPosition = 'CenterScreen'
    $form.AllowDrop = $true
    $label = New-Object System.Windows.Forms.Label
    $label.Dock = 'Fill'
    $label.TextAlign = 'MiddleCenter'
    $label.Font = New-Object System.Drawing.Font('Microsoft YaHei', 14)
    $label.Text = "请将一个或多个文件/文件夹拖到此窗口`r`n松开后自动开始处理"
    $form.Controls.Add($label)
    $form.Add_DragEnter({
        if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
            $_.Effect = [Windows.Forms.DragDropEffects]::Copy
        }
    })
    $form.Add_DragDrop({
        $script:DroppedInputPaths = @($_.Data.GetData([Windows.Forms.DataFormats]::FileDrop))
        $form.DialogResult = [Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.ShowDialog() | Out-Null
    if ($script:DroppedInputPaths) { return $script:DroppedInputPaths }
    return @()
}

function Get-PngFilesFromInputs {
    param([string[]]$Paths)

    $files = New-Object System.Collections.ArrayList
    foreach ($path in $Paths) {
        $expanded = Normalize-WindowsPathSafe $path
        if (-not (Test-Path -LiteralPath $expanded)) {
            Write-Host "[WARN] 路径不存在: $path"
            continue
        }

        $item = Get-Item -LiteralPath $expanded -Force
        if ($item.PSIsContainer) {
            $folderFiles = Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Filter '*.png' -ErrorAction SilentlyContinue
            foreach ($file in $folderFiles) { [void]$files.Add($file) }
            continue
        }

        if ($item.Extension -ieq '.png') {
            [void]$files.Add($item)
        } else {
            Write-Host "[SKIP] 不是 PNG，已跳过: $($item.FullName)"
        }
    }

    return @($files | Sort-Object FullName -Unique)
}

$config = Read-Config
$selected = Select-InputPaths
if (-not $selected) {
    Write-Host '未选择输入文件夹，已退出。'
    exit 0
}

$logRoot = Join-Path $toolDir 'logs'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$script:LogFile = Join-Path $logRoot "run_$timestamp.log"
$csvFile = Join-Path $logRoot "run_$timestamp.csv"
Write-ConsoleAndLog "工具版本: $script:ToolVersion"

$validRoots = @($selected | ForEach-Object {
    $expanded = Normalize-WindowsPathSafe $_
    if (Test-Path -LiteralPath $expanded -PathType Container) {
        (Get-Item -LiteralPath $expanded).FullName
    }
}) | Select-Object -Unique
$allFiles = @(Get-PngFilesFromInputs -Paths $selected)
if (-not $allFiles) {
    Write-ConsoleAndLog '没有找到可处理的 PNG 文件。'
    Write-LogCopy
    exit 0
}

$tempRoot = Join-Path $env:TEMP "PngToJpgWeb_$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$runnerPath = Join-Path $tempRoot 'photoshop_convert.jsx'
Copy-Item -LiteralPath $jsxPath -Destination $runnerPath -Force

$csvRows = New-Object System.Collections.ArrayList
$total = $allFiles.Count
$stats = @{ Success = 0; Skipped = 0; Failed = 0 }
$successfulConversions = New-Object System.Collections.ArrayList

Write-ConsoleAndLog "开始时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-ConsoleAndLog "输入项目: $($selected -join '; ')"
if ($validRoots) {
    Write-ConsoleAndLog "递归目录: $($validRoots -join '; ')"
}
Write-ConsoleAndLog "PNG 数量: $total"
Write-ConsoleAndLog "参数: JPEG质量=$($config.Quality), 透明底=$($config.TransparentBackground), sRGB=$($config.ConvertToSRGB)"
$photoshop = $null
$startedByTool = $false
$photoshopPath = Get-PhotoshopPath
try {
    try {
        $photoshop = [Runtime.InteropServices.Marshal]::GetActiveObject('Photoshop.Application')
    } catch {
        if (-not $photoshopPath) {
            throw 'Photoshop.exe was not found and no active Photoshop COM instance is available.'
        }
        try {
            $photoshop = New-Object -ComObject Photoshop.Application
            $startedByTool = $true
        } catch {
            if (-not $photoshopPath) { throw }
            Write-ConsoleAndLog "正在启动 Photoshop: $photoshopPath"
            Start-Process -FilePath $photoshopPath | Out-Null
            $startedByTool = $true
            $deadline = (Get-Date).AddSeconds(45)
            while (-not $photoshop) {
                try { $photoshop = [Runtime.InteropServices.Marshal]::GetActiveObject('Photoshop.Application') } catch {}
                if ($photoshop) { break }
                if ((Get-Date) -gt $deadline) { throw 'Photoshop startup timed out after 45 seconds.' }
                Start-Sleep -Seconds 1
            }
        }
    }
    $photoshop.Visible = $true
} catch {
    if (-not $photoshopPath) {
        Write-ConsoleAndLog '[ERROR] 未找到或无法启动 Photoshop。可在工具目录创建 photoshop.path.txt，写入 Photoshop.exe 的完整路径。'
    } else {
        Write-ConsoleAndLog "[ERROR] 无法连接 Photoshop COM 接口: $($_.Exception.Message)"
    }
    Write-LogCopy
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    exit 3
}

$index = 0
try {
    foreach ($file in $allFiles) {
        $index++
        $output = [IO.Path]::ChangeExtension($file.FullName, '.jpg')
        $status = '成功'
        $errorMessage = ''
        $started = Get-Date
        $width = ''
        $height = ''
        try {
            try {
                Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
                $sourceImage = [System.Drawing.Image]::FromFile($file.FullName)
                $width = $sourceImage.Width
                $height = $sourceImage.Height
                $sourceImage.Dispose()
            } catch {}
            $targetWidth = $width
            $targetHeight = $height
            $sizeRule = '原尺寸'
            if ($width -and $height) {
                $ratio = $width / [double]$height
                if ([Math]::Abs($ratio - 1.0) -le 0.03) {
                    $targetWidth = 1601; $targetHeight = 1601; $sizeRule = '1:1 -> 1601x1601'
                } elseif ([Math]::Abs($ratio - (1564 / [double]986)) -le 0.04) {
                    $targetWidth = 970; $targetHeight = 600; $sizeRule = '1564:986 -> 970x600'
                } else {
                    $sizeRule = "未匹配规则 -> ${width}x${height}"
                }
            }
            Write-ConsoleAndLog "尺寸: ${width}x${height} | 输出: ${targetWidth}x${targetHeight} | 规则: $sizeRule"
            if (-not $config.ForceOverwrite -and $config.SkipUpToDate -and (Test-Path -LiteralPath $output)) {
                $outInfo = Get-Item -LiteralPath $output
                if ($outInfo.LastWriteTimeUtc -ge $file.LastWriteTimeUtc) {
                    $status = '跳过'
                    $stats.Skipped++
                }
            }
            if ($status -eq '成功') {
                Write-ConsoleAndLog "[$index/$total] 处理中: $($file.FullName)"
                $localInput = Join-Path $tempRoot ("input_" + $index.ToString('000000') + '.png')
                $tempOutput = Join-Path $tempRoot ("output_" + $index.ToString('000000') + '.jpg')
                Copy-Item -LiteralPath $file.FullName -Destination $localInput -Force -ErrorAction Stop
                try {
                    $engine = 'Photoshop'
                    try {
                        $conversionConfig = $config.Clone()
                        $conversionConfig.TargetWidth = $targetWidth
                        $conversionConfig.TargetHeight = $targetHeight
                        Invoke-PhotoshopConversion -Photoshop $photoshop -InputFile $localInput -OutputFile $tempOutput -Config $conversionConfig -WorkDir $tempRoot -RunnerPath $runnerPath
                    } catch {
                        $engine = 'Windows备用引擎'
                        $photoshopError = $_.Exception.Message
                        Write-ConsoleAndLog "[WARN] Photoshop 转换失败，启用 Windows 备用转换: $photoshopError"
                        Convert-PngWithWindowsImage -InputFile $localInput -OutputFile $tempOutput -Quality ([int]$config.Quality) -Background $config.TransparentBackground -TargetWidth $targetWidth -TargetHeight $targetHeight
                    }
                    $verified = Test-OutputImage -Path $tempOutput -ExpectedWidth $targetWidth -ExpectedHeight $targetHeight
                    Move-Item -LiteralPath $tempOutput -Destination $output -Force -ErrorAction Stop
                } finally {
                    Remove-Item -LiteralPath $localInput -Force -ErrorAction SilentlyContinue
                    Remove-Item -LiteralPath $tempOutput -Force -ErrorAction SilentlyContinue
                }
                $stats.Success++
                Write-ConsoleAndLog "[$index/$total] 成功 | 引擎: $engine | 输入: ${width}x${height} | 输出: $($verified.Width)x$($verified.Height) | 大小: $([Math]::Round($verified.Bytes / 1KB, 1)) KB"
                Write-ConsoleAndLog "[$index/$total] 文件: $output"
                if ((Test-Path -LiteralPath $output) -and (Test-Path -LiteralPath $file.FullName)) {
                    [void]$successfulConversions.Add([pscustomobject]@{ Input = $file.FullName; Output = $output })
                }
            } else {
                Write-ConsoleAndLog "[$index/$total] 跳过: $output"
            }
        } catch {
            $status = '失败'
            $errorMessage = $_.Exception.Message
            $stats.Failed++
            Write-ConsoleAndLog "[$index/$total] 失败: $($file.FullName) :: $errorMessage"
        }
        $outSize = if (Test-Path -LiteralPath $output) { (Get-Item -LiteralPath $output).Length } else { 0 }
        [void]$csvRows.Add([pscustomobject]@{
            InputFile = $file.FullName
            OutputFile = $output
            Status = $status
            Width = $width
            Height = $height
            InputBytes = $file.Length
            OutputBytes = $outSize
            DurationSeconds = [Math]::Round(((Get-Date) - $started).TotalSeconds, 2)
            Error = $errorMessage
        })
    }
} finally {
    if ($photoshop) {
        if ($startedByTool) {
            try { $photoshop.Quit() } catch {}
        }
        [Runtime.InteropServices.Marshal]::ReleaseComObject($photoshop) | Out-Null
    }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$csvRows | Export-Csv -LiteralPath $csvFile -NoTypeInformation -Encoding UTF8
Write-ConsoleAndLog "完成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-ConsoleAndLog "总数: $total | 成功: $($stats.Success) | 跳过: $($stats.Skipped) | 失败: $($stats.Failed)"
Write-ConsoleAndLog "日志: $script:LogFile"
if ($successfulConversions.Count -gt 0) {
    Add-Type -AssemblyName System.Windows.Forms
    $deleteMessage = '已成功生成 {0} 个 JPG。{1}{1}是否删除对应的 PNG 原文件，只保留 JPG？{1}{1}选择否或关闭窗口将保留 PNG。' -f $successfulConversions.Count, [Environment]::NewLine
    $deleteAnswer = [System.Windows.Forms.MessageBox]::Show(
        $deleteMessage,
        'PNG 转 JPG Web 2.1.2 - 删除源文件确认',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )
    if ($deleteAnswer -eq [System.Windows.Forms.DialogResult]::Yes) {
        $deleted = 0
        foreach ($item in $successfulConversions) {
            if ((Test-Path -LiteralPath $item.Output) -and (Test-Path -LiteralPath $item.Input)) {
                try {
                    Remove-Item -LiteralPath $item.Input -Force -ErrorAction Stop
                    $deleted++
                    Write-ConsoleAndLog "已删除源 PNG: $($item.Input)"
                } catch {
                    Write-ConsoleAndLog "[WARN] 删除源 PNG 失败: $($item.Input) :: $($_.Exception.Message)"
                }
            }
        }
        Write-ConsoleAndLog "删除完成: $deleted/$($successfulConversions.Count)，仅保留 JPG"
    } else {
        Write-ConsoleAndLog '用户选择保留源 PNG（默认）'
    }
}
Write-ConsoleAndLog "CSV: $csvFile"
Write-LogCopy
if ($stats.Failed -gt 0) { exit 10 }
exit 0
