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
    [string]$Notes = "",
    # Preferir esto cuando el texto tenga comillas o varias líneas: pasarlo por
    # -Notes hace que PowerShell lo parta en varios argumentos y gh termine
    # buscando un archivo que no existe.
    [string]$NotesFile = ""
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
    $texto = $Notes
    if ($NotesFile) {
        if (-not (Test-Path $NotesFile)) { throw "No encontré el archivo de novedades: $NotesFile" }
        $texto = Get-Content -Raw -Path $NotesFile -Encoding UTF8
    }

    $cuerpo = "Instalador Windows de Junior Eventos $Version."
    if ($texto) { $cuerpo = "$cuerpo`r`n`r`n$($texto.Trim())" }

    # Por archivo y no por argumento: el cuerpo tiene comillas y saltos de línea.
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "junior-release-$Version.md"
    [System.IO.File]::WriteAllText($tmp, $cuerpo, (New-Object System.Text.UTF8Encoding($false)))
    try {
        # --target con la rama actual: sin esto el tag se crea sobre la rama por
        # defecto del repo, y termina apuntando a un commit que no es el que
        # compiló este instalador.
        $rama = (git rev-parse --abbrev-ref HEAD).Trim()

        gh release create $tag $setup `
            --repo lovera2025/Antigravity `
            --target $rama `
            --title "Junior Eventos $Version" `
            --notes-file $tmp
        if ($LASTEXITCODE -ne 0) { throw "gh release create falló (código $LASTEXITCODE)" }
    } finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}

Write-Host "Listo: https://github.com/lovera2025/Antigravity/releases/tag/$tag"
