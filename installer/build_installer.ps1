# Genera el instalador (Inno Setup 6). Nombre del .exe = "Setup Junior Eventos v" + versión de pubspec.
# Uso (PowerShell, desde la raíz del repo):
#   .\installer\build_installer.ps1
#
# Prerrequisitos:
#   - Flutter en PATH
#   - Inno Setup 6 (ISCC.exe), por defecto en Archivos de programa

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$pubspecPath = Join-Path $root "pubspec.yaml"
$semver = "2.2.0"
if (Test-Path $pubspecPath) {
    $verLine = Get-Content $pubspecPath -Encoding UTF8 | Where-Object { $_ -match '^\s*version:\s*(.+)\s*$' } | Select-Object -First 1
    if ($verLine -match 'version:\s*(.+)') {
        $semver = ($Matches[1].Trim().Split('+')[0])
    }
}

Write-Host ">> flutter build windows --release (app $semver)" -ForegroundColor Cyan
flutter build windows --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$iscc = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $iscc) {
    Write-Error "No se encontró ISCC.exe. Instalá Inno Setup 6 desde https://jrsoftware.org/isdl.php"
}

Write-Host ">> $iscc installer\junior_eventos_setup.iss" -ForegroundColor Cyan
& $iscc "$root\installer\junior_eventos_setup.iss"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$out = Join-Path $root "installer\dist\Setup Junior Eventos v$semver.exe"
if (Test-Path $out) {
    Write-Host "OK: $out" -ForegroundColor Green
} else {
    Write-Warning "Compilación terminó pero no se encontró: $out (revisá #define MyAppVersion en junior_eventos_setup.iss vs pubspec)"
}
