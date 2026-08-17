$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot 'CameraStreamViewer.cs'
$releaseDir = 'C:\Users\TZDEZACR\Desktop\招新\project\CameraWebServer\tools'
$output = Join-Path $releaseDir 'CameraStreamViewer.exe'
$compiler = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'

if (-not (Test-Path -LiteralPath $compiler)) {
    throw '64-bit .NET Framework C# compiler was not found.'
}

New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /debug- `
    /out:$output `
    /reference:System.dll `
    /reference:System.Core.dll `
    /reference:System.Drawing.dll `
    /reference:System.Windows.Forms.dll `
    $source

if ($LASTEXITCODE -ne 0) {
    throw "C# compiler failed with exit code $LASTEXITCODE"
}

Write-Output "Built: $output"
Get-FileHash -Algorithm SHA256 -LiteralPath $output
