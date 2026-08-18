$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot 'CameraStreamViewer.cs'
$output = Join-Path $PSScriptRoot 'CameraStreamViewer.exe'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    throw 'The .NET Framework C# compiler was not found.'
}

& $compiler /nologo /target:winexe /unsafe /optimize+ `
    /reference:System.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll `
    "/out:$output" $source
if ($LASTEXITCODE -ne 0) {
    throw "Viewer compilation failed with exit code $LASTEXITCODE"
}

$destinations = @(
    (Join-Path $PSScriptRoot '..\CameraWebServer\tools\CameraStreamViewer.exe'),
    (Join-Path $PSScriptRoot '..\.server_and_tracking\noob\tools\CameraStreamViewer.exe'),
    (Join-Path $PSScriptRoot '..\.server_and_tracking\pro\tools\CameraStreamViewer.exe')
)
foreach ($destination in $destinations) {
    Copy-Item -LiteralPath $output -Destination $destination -Force
}

Write-Host "Viewer built and copied to all three projects: $output"
