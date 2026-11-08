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
$semver = "2.3.0"
if (Test-Path $pubspecPath) {
    $verLine = Get-Content $pubspecPath -Encoding UTF8 | Where-Object { $_ -match '^\s*version:\s*(.+)\s*$' } | Select-Object -First 1
    if ($verLine -match 'version:\s*(.+)') {
        $semver = ($Matches[1].Trim().Split('+')[0])
    }
}

# La app de las tablets (Android) sale con cada versión, firmada con la clave de
# Documentos\Junior Eventos\claves. Sin android\key.properties el APK saldría con la
# clave de prueba, y una tablet que lo instale no se puede actualizar después sin
# desinstalar (y perder lo que no subió): se frena antes de compilar nada.
$keyProps = Join-Path $root "android\key.properties"
if (-not (Test-Path $keyProps)) {
    Write-Error "Falta android\key.properties (la clave de firma de Android). Copiala de Documentos\Junior Eventos\claves: ninguna tablet recibe un APK con la clave de prueba."
}

Write-Host ">> flutter build windows --release (app $semver)" -ForegroundColor Cyan
flutter build windows --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# La página del celular de la puerta (lib/puesto_main.dart). La sirve la
# notebook central por el wifi del router, así que no puede pedir nada a
# internet: sin CDN. El instalador la deja en {app}\puesto.
$puesto = Join-Path $root "build\puesto"
Write-Host ">> flutter build web -t lib/puesto_main.dart --no-web-resources-cdn" -ForegroundColor Cyan
flutter build web --release -t lib/puesto_main.dart --no-web-resources-cdn -o "$puesto"
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

# El APK de las tablets: uno por procesador; al release va el de 64 bits (arm64), el
# de todas las tablets y celulares de los últimos años. GitHub le pone puntos en vez
# de espacios al nombre (Junior.Eventos.v6.4.0.apk): así lo busca la app.
Write-Host ">> flutter build apk --release --split-per-abi" -ForegroundColor Cyan
flutter build apk --release --split-per-abi
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$apkArmado = Join-Path $root "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
$apkSdk = Join-Path $env:LOCALAPPDATA "Android\sdk\build-tools"
$apksigner = Get-ChildItem $apkSdk -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName "apksigner.bat" } |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $apksigner) {
    Write-Error "No se encontró apksigner (Android SDK build-tools): no se puede comprobar con qué clave salió el APK."
}
# apksigner necesita Java; el que usa Flutter para compilar es el de Android Studio.
$jbr = "${env:ProgramFiles}\Android\Android Studio\jbr"
if (-not $env:JAVA_HOME -and (Test-Path $jbr)) { $env:JAVA_HOME = $jbr }
$firma = & $apksigner verify --print-certs "$apkArmado" | Out-String
if ($LASTEXITCODE -ne 0 -or $firma -notmatch "CN=Junior Eventos") {
    Write-Error "El APK no salió firmado con la clave de Junior Eventos:`n$firma"
}

$apk = Join-Path $root "installer\dist\Junior Eventos v$semver.apk"
Copy-Item $apkArmado $apk -Force
Write-Host "OK: $apk" -ForegroundColor Green
