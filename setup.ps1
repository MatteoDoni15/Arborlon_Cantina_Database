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
Write-Host "`n[1/4] flutter create ..." -ForegroundColor Cyan
flutter create .

# 3) Patch del manifest Android
$manifest = "android\app\src\main\AndroidManifest.xml"
if (-not (Test-Path $manifest)) {
    Write-Host "ERRORE: manifest non trovato in $manifest" -ForegroundColor Red
    exit 1
}
Write-Host "`n[2/4] Aggiungo i permessi al manifest ..." -ForegroundColor Cyan
$content = Get-Content $manifest -Raw

# a) permesso CAMERA (prima di <application)
if ($content -notmatch "android.permission.CAMERA") {
    $content = $content -replace "(<application)", "    <uses-permission android:name=`"android.permission.CAMERA`" />`r`n`r`n    `$1"
    Write-Host "  + permesso CAMERA aggiunto"
} else {
    Write-Host "  = permesso CAMERA gia' presente"
}

# b) permesso INTERNET (serve al cloud Supabase, nelle build di release)
if ($content -notmatch "android.permission.INTERNET") {
    $content = $content -replace "(<application)", "    <uses-permission android:name=`"android.permission.INTERNET`" />`r`n`r`n    `$1"
    Write-Host "  + permesso INTERNET aggiunto (sync cloud)"
} else {
    Write-Host "  = permesso INTERNET gia' presente"
}

# c) usesCleartextTraffic dentro <application>
if ($content -notmatch "usesCleartextTraffic") {
    $content = $content -replace "(<application)", "`$1`r`n        android:usesCleartextTraffic=`"true`""
    Write-Host "  + usesCleartextTraffic=true aggiunto (sync su WiFi locale)"
} else {
    Write-Host "  = usesCleartextTraffic gia' presente"
}

Set-Content -Path $manifest -Value $content -Encoding utf8
Write-Host "  manifest aggiornato: $manifest"

# 4) Dipendenze
Write-Host "`n[3/4] flutter pub get ..." -ForegroundColor Cyan
flutter pub get

# 5) Icona dell'app dal logo (assets/Logo_cantina_vini.png)
Write-Host "`n[4/4] Genero l'icona dell'app ..." -ForegroundColor Cyan
dart run flutter_launcher_icons

Write-Host "`n== Fatto! ==" -ForegroundColor Green
Write-Host "Collega un telefono Android (USB debugging) ed esegui:  flutter run"
