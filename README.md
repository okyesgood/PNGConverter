# PNGConverter

Amazon 图片发布转换工具，当前版本 4.27.0。源码位于 [src](src)，使用 Windows Forms 和 .NET 8。

## 功能

- 选择或拖入 PNG 文件与文件夹，递归查找并批量转换。
- 支持详情图、基础 A+、高级 A+、自定义尺寸和原尺寸输出。
- 转换透明区域为白色或黑色背景，输出 JPEG 时清除源图片元数据。
- 验证临时 JPEG 后替换目标文件，生成 CSV 和 JSON 运行报告。
- 可取消处理，并可选择在成功转换后删除原 PNG。

## 构建

需要 Windows 10/11 和 .NET 8 SDK。在仓库根目录运行：

```powershell
dotnet restore src/PNG转JPG-Web.csproj
dotnet build src/PNG转JPG-Web.csproj -c Release
```

发布文件请输出到仓库外部目录。编译产物、本地配置和运行报告不进入 Git。
