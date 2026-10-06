#target photoshop

/*
 * Photoshop-side worker. The PowerShell runner writes a temporary JSON job
 * file and invokes this script through Photoshop's COM automation API.
 */
(function () {
    var jobFile = (typeof __PNG_TO_JPG_JOB_FILE !== "undefined") ? __PNG_TO_JPG_JOB_FILE : "";

    if (!jobFile) {
        throw new Error("Missing job file argument.");
    }

    var jobText = readTextFile(File(jobFile));
    var job = eval("(" + jobText + ")");
    var result = {
        ok: false,
        input: job.input,
        output: job.output,
        error: "",
        stage: "initializing"
    };
    var originalDialogs = app.displayDialogs;

    try {
        app.displayDialogs = DialogModes.NO;
        result.stage = "file-object";
        var inputFile = File(job.input);
        var outputFile = File(job.output);
        result.stage = "app.open";
        var doc = app.open(inputFile);
        result.stage = "opened";

        try {
            if (doc.mode != DocumentMode.RGB) {
                result.stage = "change-mode";
                doc.changeMode(ChangeMode.RGB);
            }

            if (job.convertToSRGB) {
                try {
                    doc.convertProfile("sRGB IEC61966-2.1", Intent.RELATIVECOLORIMETRIC, true, true);
                } catch (profileError) {
                    // Some images have no usable profile. Export can continue.
                }
            }

            if (job.transparentBackground === "white") {
                result.stage = "white-background";
                ensureWhiteBackground(doc);
            } else if (job.transparentBackground === "black") {
                result.stage = "black-background";
                ensureBlackBackground(doc);
            }

            if (Number(job.targetWidth) > 0 && Number(job.targetHeight) > 0) {
                result.stage = "resize";
                resizeToCanvas(doc, Number(job.targetWidth), Number(job.targetHeight));
            }

            var options = new JPEGSaveOptions();
            options.quality = Number(job.quality);
            options.embedColorProfile = true;
            options.formatOptions = FormatOptions.OPTIMIZEDBASELINE;
            result.stage = "saving-jpeg";
            doc.saveAs(outputFile, options, true, Extension.LOWERCASE);
            result.ok = true;
        } finally {
            doc.close(SaveOptions.DONOTSAVECHANGES);
        }
    } catch (e) {
        result.error = (e && e.message ? e.message : String(e)) + " (stage: " + result.stage + ")";
    } finally {
        app.displayDialogs = originalDialogs;
    }

    writeTextFile(File(job.result), resultToJson(result));
})();

// Older Photoshop ExtendScript releases do not provide a native JSON serializer.
function escapeJsonString(value) {
    var text = value === null || typeof value === "undefined" ? "" : String(value);
    text = text.replace(/\\/g, "\\\\");
    text = text.replace(/"/g, '\\"');
    text = text.replace(/\r/g, "\\r");
    text = text.replace(/\n/g, "\\n");
    text = text.replace(/\t/g, "\\t");
    return text;
}

function resultToJson(value) {
    return "{\"ok\":" + (value.ok ? "true" : "false") +
        ",\"input\":\"" + escapeJsonString(value.input) +
        "\",\"output\":\"" + escapeJsonString(value.output) +
        "\",\"error\":\"" + escapeJsonString(value.error) + "\"}";
}

function ensureWhiteBackground(doc) {
    var white = new SolidColor();
    white.rgb.red = 255;
    white.rgb.green = 255;
    white.rgb.blue = 255;
    app.backgroundColor = white;
    doc.flatten();
}

function ensureBlackBackground(doc) {
    var black = new SolidColor();
    black.rgb.red = 0;
    black.rgb.green = 0;
    black.rgb.blue = 0;
    app.backgroundColor = black;
    doc.flatten();
}

function resizeToCanvas(doc, targetWidth, targetHeight) {
    var sourceWidth = doc.width.as("px");
    var sourceHeight = doc.height.as("px");
    var scale = Math.min(targetWidth / sourceWidth, targetHeight / sourceHeight);
    var resizedWidth = Math.max(1, Math.round(sourceWidth * scale));
    var resizedHeight = Math.max(1, Math.round(sourceHeight * scale));
    doc.resizeImage(UnitValue(resizedWidth, "px"), UnitValue(resizedHeight, "px"), null, ResampleMethod.BICUBICSHARPER);
    doc.resizeCanvas(UnitValue(targetWidth, "px"), UnitValue(targetHeight, "px"), AnchorPosition.MIDDLECENTER);
}

function readTextFile(file) {
    file.encoding = "UTF8";
    file.open("r");
    var text = file.read();
    file.close();
    if (text.length > 0 && text.charCodeAt(0) === 0xFEFF) {
        text = text.substring(1);
    }
    return text;
}

function writeTextFile(file, text) {
    file.encoding = "UTF8";
    file.open("w");
    file.write(text);
    file.close();
}
