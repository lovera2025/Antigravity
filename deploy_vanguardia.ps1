# Script de Despliegue Junior Eventos
# Version: 1.5 (Standard Stable Release)

Write-Host ">>> Iniciando Despegue JUNIOR EVENTOS..." -ForegroundColor Yellow

# 1. Limpieza absoluta
Write-Host ">>> Limpiando rastro de versiones previas..." -ForegroundColor Gray
flutter clean
flutter pub get

# 2. Compilacion Web Estandar
Write-Host ">>> Compilando Aplicacion Web (Motor Estandar 3.41)..." -ForegroundColor Magenta
# Compilamos de forma estandar. La configuracion de renderer esta en index.html
flutter build web --release

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Compilacion terminda con exito." -ForegroundColor Green
    
    # 3. Subida a Firebase
    Write-Host ">>> Sincronizando con Servidor Global..." -ForegroundColor Cyan
    firebase deploy --only hosting
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "*******************************************" -ForegroundColor Green
        Write-Host "* JUNIOR EVENTOS ESTA ONLINE              *" -ForegroundColor White -BackgroundColor DarkGreen
        Write-Host "*******************************************" -ForegroundColor Green
        Write-Host "Url: https://arguello-eventos.web.app" -ForegroundColor Cyan
    } else {
        Write-Host "[ERROR] El despliegue a la nube fallo." -ForegroundColor Red
    }
} else {
    Write-Host "[ERROR] La construccion de Flutter se detuvo." -ForegroundColor Red
}
