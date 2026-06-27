# Setup automatico del progetto Cantina Vini.
# Prerequisiti: Flutter gia' installato e nel PATH (vedi SETUP.md passi 1-2).
# Uso:  .\setup.ps1

$ErrorActionPreference = "Stop"

Write-Host "== Cantina Vini - setup ==" -ForegroundColor Magenta

# 1) Verifica Flutter
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host "ERRORE: 'flutter' non trovato nel PATH." -ForegroundColor Red
    Write-Host "Installa Flutter e riapri il terminale (vedi SETUP.md)."
    exit 1
}

# 2) Genera le cartelle native (non tocca lib/)
Write-Host "`n[1/3] flutter create ..." -ForegroundColor Cyan
flutter create .

# 3) Patch del manifest Android
$manifest = "android\app\src\main\AndroidManifest.xml"
if (-not (Test-Path $manifest)) {
    Write-Host "ERRORE: manifest non trovato in $manifest" -ForegroundColor Red
    exit 1
}
Write-Host "`n[2/3] Aggiungo i permessi al manifest ..." -ForegroundColor Cyan
$content = Get-Content $manifest -Raw

# a) permesso CAMERA (prima di <application)
if ($content -notmatch "android.permission.CAMERA") {
    $content = $content -replace "(<application)", "    <uses-permission android:name=`"android.permission.CAMERA`" />`r`n`r`n    `$1"
    Write-Host "  + permesso CAMERA aggiunto"
} else {
    Write-Host "  = permesso CAMERA gia' presente"
}

# b) usesCleartextTraffic dentro <application>
if ($content -notmatch "usesCleartextTraffic") {
    $content = $content -replace "(<application)", "`$1`r`n        android:usesCleartextTraffic=`"true`""
    Write-Host "  + usesCleartextTraffic=true aggiunto (sync su WiFi locale)"
} else {
    Write-Host "  = usesCleartextTraffic gia' presente"
}

Set-Content -Path $manifest -Value $content -Encoding utf8
Write-Host "  manifest aggiornato: $manifest"

# 4) Dipendenze
Write-Host "`n[3/3] flutter pub get ..." -ForegroundColor Cyan
flutter pub get

Write-Host "`n== Fatto! ==" -ForegroundColor Green
Write-Host "Collega un telefono Android (USB debugging) ed esegui:  flutter run"
