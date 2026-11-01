# Build script for NexusFX Native Rust SFTP Engine
$ErrorActionPreference = "Stop"

Write-Host "==> Compiling Native SFTP Engine (Rust)..." -ForegroundColor Cyan
$projectRoot = Split-Path -Parent $PSScriptRoot
$cargoToml = Join-Path $projectRoot "native\sftp_engine\Cargo.toml"
$dllSource = Join-Path $projectRoot "native\sftp_engine\target\release\sftp_engine.dll"

cargo build --release --manifest-path $cargoToml
if ($LASTEXITCODE -ne 0) {
    Write-Error "Cargo build failed!"
    exit 1
}

Write-Host "==> Built: $dllSource" -ForegroundColor Green

# Copy to build runners if they exist
$targets = @(
    (Join-Path $projectRoot "build\windows\x64\runner\Release"),
    (Join-Path $projectRoot "build\windows\x64\runner\Debug")
)

foreach ($target in $targets) {
    if (Test-Path $target) {
        Copy-Item -Path $dllSource -Destination $target -Force
        Write-Host "==> Copied sftp_engine.dll to $target" -ForegroundColor Green
    }
}

Write-Host "==> Native SFTP Engine build complete!" -ForegroundColor Cyan
