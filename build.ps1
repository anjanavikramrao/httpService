<#
.SYNOPSIS
    Builds the httpService application for multiple OS platforms and architectures.

.DESCRIPTION
    Cross-compiles the Go application for Windows and Linux platforms across amd64,
    arm64, and arm32 architectures, saving the outputs to the bin folder.

.PARAMETER OS
    Target operating system: 'windows', 'linux', or 'all' (default).

.PARAMETER Arch
    Target architecture: 'amd64', 'arm64', 'arm32', or 'all' (default).

.PARAMETER OutputDir
    Destination folder for compiled executables. Defaults to 'bin'.

.EXAMPLE
    .\build.ps1
    Builds all supported combinations of OS and architecture.

.EXAMPLE
    .\build.ps1 -OS linux -Arch arm64
    Builds specifically for Linux ARM64.
#>

[CmdletBinding()]
param(
    [ValidateSet('windows', 'linux', 'all')]
    [string[]]$OS = @('all'),

    [ValidateSet('amd64', 'arm64', 'arm32', 'all')]
    [string[]]$Arch = @('all'),

    [string]$OutputDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if (-not $OutputDir) {
    $OutputDir = Join-Path $scriptDir "bin"
}

$mainFile = Join-Path $scriptDir "main.go"
if (-not (Test-Path -Path $mainFile)) {
    throw "Source file not found: $mainFile"
}

# Resolve targets
$targetOSList = if ($OS -contains 'all') { @('windows', 'linux') } else { $OS }
$targetArchList = if ($Arch -contains 'all') { @('amd64', 'arm64', 'arm32') } else { $Arch }

# Ensure output directory exists
if (-not (Test-Path -Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Architecture mapping to Go GOARCH
$archMap = @{
    'amd64' = 'amd64'
    'arm64' = 'arm64'
    'arm32' = 'arm'
}

$origGOOS = $env:GOOS
$origGOARCH = $env:GOARCH
$origCGO = $env:CGO_ENABLED

$results = @()

try {
    # Ensure pure Go cross-compilation without CGO dependency
    $env:CGO_ENABLED = '0'

    foreach ($currentOS in $targetOSList) {
        foreach ($currentArch in $targetArchList) {
            $goarch = $archMap[$currentArch]
            $ext = if ($currentOS -eq 'windows') { '.exe' } else { '' }
            $outputFilename = "httpservice-$currentOS-$currentArch$ext"
            $outputPath = Join-Path $OutputDir $outputFilename

            # Check for known unsupported targets in Go
            if ($currentOS -eq 'windows' -and $currentArch -eq 'arm32') {
                Write-Warning "Skipping ${currentOS}/${currentArch}: Go does not support 32-bit Windows on ARM."
                $results += [PSCustomObject]@{
                    OS       = $currentOS
                    Arch     = $currentArch
                    Binary   = $outputFilename
                    Status   = 'Skipped (Unsupported)'
                }
                continue
            }

            Write-Host "Building $outputFilename ($currentOS/$goarch)..." -ForegroundColor Cyan

            $env:GOOS = $currentOS
            $env:GOARCH = $goarch

            & go build -o $outputPath $mainFile

            if ($LASTEXITCODE -eq 0 -and (Test-Path -Path $outputPath)) {
                $fileInfo = Get-Item -Path $outputPath
                Write-Host "Successfully built: $outputFilename ($([math]::Round($fileInfo.Length / 1MB, 2)) MB)" -ForegroundColor Green
                $results += [PSCustomObject]@{
                    OS       = $currentOS
                    Arch     = $currentArch
                    Binary   = $outputFilename
                    Status   = 'Success'
                }
            } else {
                Write-Error "Failed to build for $currentOS/$currentArch"
                $results += [PSCustomObject]@{
                    OS       = $currentOS
                    Arch     = $currentArch
                    Binary   = $outputFilename
                    Status   = 'Failed'
                }
            }
        }
    }
}
finally {
    # Restore original environment
    $env:GOOS = $origGOOS
    $env:GOARCH = $origGOARCH
    $env:CGO_ENABLED = $origCGO
}

Write-Host "`nBuild Summary:" -ForegroundColor Yellow
$results | Format-Table -AutoSize
