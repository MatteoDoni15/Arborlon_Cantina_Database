# 🛠️ Installazione e primo avvio (Windows)

Questa guida ti porta da zero ad avere l'app sul telefono. Va fatta **una volta sola**.

---

## 1. Installa Flutter

1. Scarica Flutter da: https://docs.flutter.dev/get-started/install/windows
2. Estrai lo zip in una cartella semplice, es. `C:\src\flutter`
   (evita cartelle con spazi o permessi speciali tipo `Program Files`).
3. Aggiungi `C:\src\flutter\bin` al **PATH** di Windows:
   - Cerca "Variabili d'ambiente" → Modifica le variabili d'ambiente per l'utente
   - Variabile `Path` → Nuovo → incolla `C:\src\flutter\bin` → OK.
4. Chiudi e riapri il terminale, poi verifica:
   ```powershell
   flutter --version
   ```

## 2. Installa Android Studio (serve per compilare per Android)

1. Scarica da https://developer.android.com/studio e installa.
2. Apri Android Studio → **More Actions → SDK Manager** → assicurati siano
   installati: **Android SDK**, **Android SDK Command-line Tools**, **Platform-Tools**.
3. Accetta le licenze:
   ```powershell
   flutter doctor --android-licenses
   ```
4. Controlla che sia tutto a posto:
   ```powershell
   flutter doctor
   ```
   Risolvi eventuali ❌ seguendo i suggerimenti (di solito mancano le licenze o
   il "cmdline-tools").

## 3. Genera le cartelle native del progetto

Apri il terminale **nella cartella del progetto** (`cantina_vini`) ed esegui:

```powershell
flutter create .
```

Questo crea le cartelle `android/`, `ios/`, ecc. **senza** toccare il codice in
`lib/` che è già scritto.

## 4. Aggiungi i permessi Android  ⚠️ importante

Apri il file:

```
android\app\src\main\AndroidManifest.xml
```

### a) Permesso fotocamera
Subito **sopra** il tag `<application ...>` aggiungi:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

### b) Consenti la rete locale in chiaro (serve al sync P2P)
Nel tag `<application ...>` aggiungi l'attributo `android:usesCleartextTraffic="true"`.
Esempio:

```xml
<application
    android:label="Cantina Vini"
    android:usesCleartextTraffic="true"
    android:icon="@mipmap/ic_launcher">
```

> Senza il punto (b) la sincronizzazione tra telefoni **non funziona** su
> Android 9 o superiore (blocca le connessioni HTTP locali).

*(Puoi copiare il blocco già pronto da `docs/AndroidManifest-permessi.xml`.)*

## 5. Scarica le dipendenze e avvia

Collega un telefono Android in **modalità sviluppatore** (USB debugging attivo),
oppure avvia un emulatore, poi:

```powershell
flutter pub get
flutter devices      # controlla che il telefono sia elencato
flutter run
```

L'app si installerà e partirà sul telefono. 🎉

## 6. Creare l'APK da installare sugli altri telefoni

Per dare l'app ai colleghi senza cavo:

```powershell
flutter build apk --release
```

Trovi il file in:
```
build\app\outputs\flutter-apk\app-release.apk
```
Invialo via WhatsApp/Drive: ogni collega lo apre e lo installa (deve
consentire "installa da origini sconosciute").

---

## Scorciatoia: script automatico

Invece dei passi 3-5 puoi lanciare (dopo aver installato Flutter, passi 1-2):

```powershell
.\setup.ps1
```

Fa `flutter create`, aggiunge i permessi al manifest e scarica le dipendenze.

---

## Problemi comuni

| Sintomo | Soluzione |
|---|---|
| `flutter` non riconosciuto | PATH non impostato (passo 1.3), riapri il terminale |
| `flutter doctor` segna Android ❌ | Apri Android Studio, installa SDK + cmdline-tools, poi `flutter doctor --android-licenses` |
| La fotocamera non si apre | Manca il permesso CAMERA (passo 4a) o non l'hai concesso al primo uso |
| Sync "fallita" tra telefoni | Stessa rete WiFi? Hai messo `usesCleartextTraffic="true"` (passo 4b)? Il telefono "host" mostra il QR? |
| L'OCR non legge nulla | Foto poco nitida; riprova più vicino. È comunque facoltativo, puoi scrivere a mano |
