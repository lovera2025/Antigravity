# Publica el Setup de Windows en GitHub Releases (lovera2025/Antigravity).
# Uso (desde la raíz del repo, después de compilar el instalador):
#   powershell -File tool/publish_windows_release.ps1 -Notes "- lo que cambió"
# Opcional: -Version 4.7.3  (si no, lee pubspec.yaml)
#
# Requiere: gh autenticado (`gh auth status`).
# No construye Flutter: adjuntá el .exe que ya generó Inno Setup.

param(
    [string]$Version = "",
    # Novedades de ESTA versión, breves. Sin esto el release sale con el título y
    # una sola línea: es preferible a heredar el changelog de la versión anterior,
    # que es lo que pasaba cuando el texto estaba escrito acá adentro.
    [string]$Notes = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

if (-not $Version) {
    $pubspec = Get-Content -Raw -Path (Join-Path $repoRoot "pubspec.yaml")
    if ($pubspec -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
        throw "No pude leer version: X.Y.Z de pubspec.yaml"
    }
    $Version = $Matches[1]
}

$tag = "v$Version"
$exeName = "Setup Junior Eventos v$Version.exe"
$candidatos = @(
    (Join-Path $repoRoot "installer\dist\$exeName"),
    (Join-Path $repoRoot "dist\$exeName"),
    (Join-Path $repoRoot "installer_output\$exeName"),
    (Join-Path $repoRoot "releases\v$Version\$exeName")
)
$setup = $candidatos | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $setup) {
    throw "No encontré '$exeName'. Compilá el instalador (installer/junior_eventos_setup.iss) y reintentá."
}

Write-Host "Versión: $Version"
Write-Host "Tag:     $tag"
Write-Host "Setup:   $setup"

$existente = $false
try {
    gh release view $tag --repo lovera2025/Antigravity 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $existente = $true }
} catch {
    $existente = $false
}

if ($existente) {
    Write-Host "El release $tag ya existe. Subo/actualizo el asset..."
    gh release upload $tag $setup --repo lovera2025/Antigravity --clobber
} else {
    $cuerpo = "Instalador Windows de Junior Eventos $Version."
    if ($Notes) { $cuerpo = "$cuerpo`n`n$Notes" }

    gh release create $tag $setup `
        --repo lovera2025/Antigravity `
        --title "Junior Eventos $Version" `
        --notes $cuerpo
}

Write-Host "Listo: https://github.com/lovera2025/Antigravity/releases/tag/$tag"
