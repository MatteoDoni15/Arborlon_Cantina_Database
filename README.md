# 🍷 Cantina Vini

App Android per la gestione del **magazzino vini di un ristorante**.
Funziona **offline** (DB locale sul telefono) e si **sincronizza tra i
telefoni dei colleghi** sulla stessa rete WiFi, senza bisogno di internet né
di un server esterno.

> Questa è la **Fase 1** (locale + P2P). Il cloud per più ristoranti / sync a
> distanza è previsto come Fase 2 (vedi `docs/FASE2-CLOUD.md`).

## Cosa fa

- 📦 **Catalogo vini** con giacenza (bottiglie) calcolata in automatico.
- ⬇️ **Carico** (acquisto) e ⬆️ **Scarico** (vendita) con **foto** al momento.
- 🔤 **OCR etichetta**: scatti la foto e l'app prova a leggere nome e annata.
- 💾 **Backup/Ripristino su file**: esporti tutto (dati + foto) in un file da
  salvare su WhatsApp/Drive e reimportare su un telefono nuovo.
- 📡 **Sincronizzazione P2P**: un telefono mostra un QR, l'altro lo inquadra e i
  due si scambiano tutto (in entrambe le direzioni), foto comprese.

## Come funziona la sincronizzazione (in breve)

I dati sono pensati per **fondersi senza conflitti**:

- I **movimenti** (carico/scarico) sono *eventi immutabili* con un ID univoco:
  unire due telefoni = unione delle liste. La giacenza è sempre ricalcolata.
- L'**anagrafica vini** usa la regola "vince l'ultima modifica" (`updated_at`).

Questo stesso modello funzionerà identico anche con il cloud in Fase 2: si
cambia solo il "trasporto" dei dati.

## Avvio rapido

1. Installa Flutter (vedi **[SETUP.md](SETUP.md)** — è la guida passo-passo).
2. Nella cartella del progetto:
   ```powershell
   flutter create .      # genera le cartelle android/ios
   ```
3. Aggiungi i permessi al manifest Android (vedi SETUP.md, passo 4).
4. ```powershell
   flutter pub get
   flutter run           # con un telefono Android collegato
   ```

> In alternativa c'è lo script `setup.ps1` che fa i passi 2-4 in automatico.

## Struttura del codice

```
lib/
├─ main.dart                      avvio app
├─ data/
│  ├─ models/                     Wine, Movement (con campi di sync)
│  ├─ db/app_database.dart        SQLite locale
│  └─ repositories/               accesso ai dati + logica di merge
├─ services/
│  ├─ photo_service.dart          scatto/archiviazione foto
│  ├─ ocr_service.dart            lettura etichetta (ML Kit)
│  ├─ device_service.dart         identità del telefono
│  └─ backup_service.dart         export/import file .cantina
├─ sync/
│  ├─ sync_payload.dart           formato dati comune (backup + P2P)
│  └─ p2p_sync_service.dart       server/client HTTP sul WiFi locale
└─ ui/
   ├─ theme.dart
   ├─ screens/                    home, scheda vino, form, sync, impostazioni
   └─ widgets/
```
