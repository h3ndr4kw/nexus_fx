<#
.SYNOPSIS
  Builds NexusFX for Windows and packages it for distribution.

.DESCRIPTION
  Produces, under dist\:
    NexusFX-<version>-win-x64\          the app folder, ready to run
    NexusFX-<version>-win-x64.zip       that folder zipped (portable)
    NexusFX-<version>-setup.exe         Inno Setup installer

  The version comes from pubspec.yaml. The build fails if sftp_engine.dll is
  missing from the bundle, and the Visual C++ runtime DLLs the app imports are
  copied in, so the package runs on a PC without the VC++ Redistributable.

.PARAMETER SkipBuild
  Package the existing build\windows\x64\runner\Release instead of building.

.PARAMETER NoInstaller
  Skip the Inno Setup installer and produce only the folder and zip.

.EXAMPLE
  .\scripts\package.ps1
#>
param(
    [switch]$SkipBuild,
    [switch]$NoInstaller
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

# --- Version ---------------------------------------------------------------
$versionLine = Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if (-not $versionLine) { throw 'No version: line in pubspec.yaml' }
$version = ($versionLine.Matches[0].Groups[1].Value -split '\+')[0]
Write-Step "Packaging NexusFX $version"

$release = Join-Path $root 'build\windows\x64\runner\Release'
$dllBuilt = Join-Path $root 'native\sftp_engine\target\release\sftp_engine.dll'

# --- Build -----------------------------------------------------------------
if (-not $SkipBuild) {
    Write-Step 'Building native SFTP engine (Rust)'
    & (Join-Path $PSScriptRoot 'build_native.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'build_native.ps1 failed' }

    Write-Step 'Building Flutter Windows release'
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed' }
}

if (-not (Test-Path (Join-Path $release 'nexus_fx.exe'))) {
    throw "No build found at $release. Run without -SkipBuild."
}

# CMake only bundles the DLL if it existed when Flutter built; cover the case
# where it was built afterwards.
if (-not (Test-Path (Join-Path $release 'sftp_engine.dll')) -and (Test-Path $dllBuilt)) {
    Copy-Item $dllBuilt $release -Force
}
if (-not (Test-Path (Join-Path $release 'sftp_engine.dll'))) {
    throw 'sftp_engine.dll is missing from the bundle. Without it SFTP falls back to the slow Dart engine. Run .\scripts\build_native.ps1 (needs the Rust toolchain).'
}

# --- Stage -----------------------------------------------------------------
$dist = Join-Path $root 'dist'
$name = "NexusFX-$version-win-x64"
$stage = Join-Path $dist $name
$zip = Join-Path $dist "$name.zip"

Write-Step "Staging $stage"
New-Item -ItemType Directory -Force $dist | Out-Null
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
Copy-Item -Recurse $release $stage

# --- Visual C++ runtime ----------------------------------------------------
Write-Step 'Bundling the Visual C++ runtime'
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw 'vswhere.exe not found; Visual Studio 2022 with the C++ workload is required.' }
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'No Visual Studio install with the C++ tools was found.' }

$crt = Get-ChildItem "$vs\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT" -Directory -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $crt) { throw "No VC++ redist folder under $vs\VC\Redist\MSVC." }

$dumpbin = Get-ChildItem "$vs\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1

$available = Get-ChildItem $crt.FullName -Filter *.dll | ForEach-Object { $_.Name.ToLower() }
$needed = [System.Collections.Generic.HashSet[string]]::new()
if ($dumpbin) {
    # Copy exactly the runtime DLLs that something in the bundle imports.
    Get-ChildItem $stage -Recurse -Include *.exe, *.dll | ForEach-Object {
        & $dumpbin.FullName /nologo /dependents $_.FullName |
            ForEach-Object { $_.Trim().ToLower() } |
            Where-Object { $available -contains $_ } |
            ForEach-Object { [void]$needed.Add($_) }
    }
} else {
    Write-Warning 'dumpbin not found; bundling the usual runtime DLLs.'
    'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll' | ForEach-Object { [void]$needed.Add($_) }
}
foreach ($dll in $needed) {
    Copy-Item (Join-Path $crt.FullName $dll) $stage -Force
    Write-Host "    + $dll"
}

# --- Zip -------------------------------------------------------------------
Write-Step "Creating $zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal

# --- Installer -------------------------------------------------------------
$setup = $null
if (-not $NoInstaller) {
    $iscc = (Get-Command iscc.exe -ErrorAction SilentlyContinue).Source
    if (-not $iscc) {
        $iscc = @(
            "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
            "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
            "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if ($iscc) {
        Write-Step 'Building installer (Inno Setup)'
        & $iscc /Q "/DAppVersion=$version" "/DSourceDir=$stage" "/DOutputDir=$dist" (Join-Path $root 'installer\nexusfx.iss')
        if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compile failed' }
        $setup = Join-Path $dist "NexusFX-$version-setup.exe"
    } else {
        Write-Warning 'Inno Setup 6 not found, skipping the installer. Install it with: winget install JRSoftware.InnoSetup'
    }
}

# --- Summary ---------------------------------------------------------------
Write-Host ''
Write-Step 'Done'
foreach ($f in @($zip, $setup) | Where-Object { $_ }) {
    '    {0}  ({1:N1} MB)' -f $f, ((Get-Item $f).Length / 1MB) | Write-Host
}
