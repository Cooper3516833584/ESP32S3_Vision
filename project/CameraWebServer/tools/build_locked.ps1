param(
    [switch]$Upload,
    [string]$Port
)

$ErrorActionPreference = 'Stop'

$toolDir = $PSScriptRoot
$projectDir = Split-Path -Parent $toolDir
$projectParent = Split-Path -Parent $projectDir
$projectName = Split-Path -Leaf $projectDir
$buildDir = Join-Path $projectDir 'build\locked'

# Use the CLI bundled with the student's Arduino IDE. The project intentionally
# does not carry a 1.6 GB duplicate toolchain.
$cliCandidates = @()
$command = Get-Command arduino-cli.exe -ErrorAction SilentlyContinue
if ($command) {
    $cliCandidates += $command.Source
}
$cliCandidates += @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe'),
    (Join-Path $env:ProgramFiles 'Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe')
)
if (${env:ProgramFiles(x86)}) {
    $cliCandidates += (Join-Path ${env:ProgramFiles(x86)} 'Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe')
}
$cli = $cliCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $cli) {
    throw 'Arduino IDE 2.x was not found. Install Arduino IDE before running this script.'
}

$coreList = & $cli core list --format json | ConvertFrom-Json
$esp32Core = $coreList.platforms | Where-Object { $_.id -eq 'esp32:esp32' }
if (-not $esp32Core) {
    throw 'ESP32 Core is not installed. Install esp32 by Espressif Systems 3.3.7 in Boards Manager.'
}
if ($esp32Core.installed_version -ne '3.3.7') {
    throw "ESP32 Core 3.3.7 is required; installed version is $($esp32Core.installed_version)."
}

if ($Upload -and [String]::IsNullOrWhiteSpace($Port)) {
    $Port = Read-Host 'Serial port (for example COM5)'
}
if ($Upload -and $Port -notmatch '^COM\d+$') {
    throw "Invalid serial port: $Port"
}

# Arduino's Windows linker can corrupt non-ASCII build paths. Map the project
# temporarily to an unused ASCII drive letter. The mapping is always removed.
$mappedDrive = @('R:', 'Q:', 'P:', 'O:') |
    Where-Object { -not (Test-Path "$_\") } |
    Select-Object -First 1
if (-not $mappedDrive) {
    throw 'No free temporary drive letter (R:, Q:, P:, O:)'
}

try {
    & subst.exe $mappedDrive $projectParent
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to create temporary ASCII drive mapping'
    }

    $mappedProject = "$mappedDrive\$projectName"
    $mappedBuild = "$mappedProject\build\locked"
    $arguments = @(
        'compile',
        '--fqbn', 'esp32:esp32:esp32s3:FlashMode=dio,FlashSize=4M,PSRAM=opi,PartitionScheme=custom,DebugLevel=none,EraseFlash=all',
        '--clean',
        '--build-path', $mappedBuild,
        '--build-property', 'build.flash_mode=dio',
        '--build-property', 'build.img_freq=40m',
        '--build-property', 'build.flash_freq=40m'
    )
    $arguments += $mappedProject

    $phase = 'Compiling'
    $spinner = @('|', '/', '-', '\')
    $startedAt = Get-Date
    $argumentsJson = ConvertTo-Json -InputObject @($arguments) -Compress
    $job = Start-Job -ScriptBlock {
        param($executable, $serializedArguments)
        $cliArguments = @(ConvertFrom-Json -InputObject $serializedArguments)
        $output = & $executable @cliArguments 2>&1
        [PSCustomObject]@{
            ExitCode = $LASTEXITCODE
            Output = @($output | ForEach-Object { $_.ToString() })
        }
    } -ArgumentList $cli, $argumentsJson

    try {
        $step = 0
        while ($job.State -in @('NotStarted', 'Running')) {
            $elapsed = [int]((Get-Date) - $startedAt).TotalSeconds
            $mark = $spinner[$step % $spinner.Count]
            Write-Progress -Id 1 -Activity 'ESP32-S3 DIO 40MHz' `
                -Status "$mark $phase... elapsed ${elapsed}s (please wait)" `
                -PercentComplete -1
            Start-Sleep -Milliseconds 200
            $step++
            $job = Get-Job -Id $job.Id
        }
        $result = Receive-Job -Job $job
    }
    finally {
        Write-Progress -Id 1 -Activity 'ESP32-S3 DIO 40MHz' -Completed
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }

    if ($result.Output) {
        $result.Output | ForEach-Object { Write-Host $_ }
    }
    if ($result.ExitCode -ne 0) {
        throw "Locked Arduino build failed with exit code $($result.ExitCode)"
    }
}
finally {
    & subst.exe $mappedDrive /d 2>$null
}

function Assert-Dio40Image([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Expected image was not generated: $Path"
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 4 -or $bytes[0] -ne 0xE9) {
        throw "Invalid ESP image: $Path"
    }

    # ESP image byte 2: SPI mode (2 = DIO).
    # Low nibble of byte 3: SPI frequency (0 = 40 MHz, F = 80 MHz).
    if ($bytes[2] -ne 2 -or (($bytes[3] -band 0x0F) -ne 0)) {
        throw "Refusing image: header is not DIO 40 MHz: $Path"
    }
}

function Find-EspTool {
    $toolsDir = Join-Path $env:LOCALAPPDATA 'Arduino15\packages\esp32\tools\esptool_py'
    $candidate = Get-ChildItem -LiteralPath $toolsDir -Filter 'esptool.exe' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (-not $candidate) {
        throw 'The esptool bundled with ESP32 Core was not found.'
    }
    return $candidate.FullName
}

function Assert-Esp32S3Image([string]$Path, [string]$EspTool) {
    $output = & $EspTool image-info $Path 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "esptool could not inspect image: $Path"
    }
    $details = $output -join "`n"
    if ($details -notmatch 'Detected image type:\s*ESP32-S3' -or
        $details -notmatch 'Chip ID:\s*9 \(ESP32-S3\)') {
        throw "Refusing image: target is not ESP32-S3: $Path"
    }
}

$bootImage = Join-Path $buildDir 'CameraWebServer.ino.bootloader.bin'
$appImage = Join-Path $buildDir 'CameraWebServer.ino.bin'
Assert-Dio40Image $bootImage
Assert-Dio40Image $appImage
$espTool = Find-EspTool
Assert-Esp32S3Image $bootImage $espTool
Assert-Esp32S3Image $appImage $espTool

Write-Host ''
Write-Host 'LOCKED CONFIG VERIFIED: ESP32-S3 / DIO / 40 MHz / 4 MB / OPI PSRAM' -ForegroundColor Green
Write-Host "Build directory: $buildDir"
if ($Upload) {
    # Upload only after both images pass the locked-config checks above.
    # Recreate the ASCII mapping because esptool may also reject non-ASCII paths.
    try {
        & subst.exe $mappedDrive $projectParent
        if ($LASTEXITCODE -ne 0) {
            throw 'Unable to create temporary ASCII drive mapping for upload'
        }
        & $cli upload --fqbn 'esp32:esp32:esp32s3:FlashMode=dio,FlashSize=4M,PSRAM=opi,PartitionScheme=custom,DebugLevel=none,EraseFlash=all' `
            --input-dir $mappedBuild --port $Port $mappedProject
        if ($LASTEXITCODE -ne 0) {
            throw "Locked Arduino upload failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        & subst.exe $mappedDrive /d 2>$null
    }
    Write-Host "Upload completed on $Port" -ForegroundColor Green
}
