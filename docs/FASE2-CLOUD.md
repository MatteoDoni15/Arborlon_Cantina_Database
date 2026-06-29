# ☁️ Fase 2 — Cloud e abbonamento

> **Stato:** primo innesto implementato. Per attivarlo (progetto Supabase +
> chiavi) segui la guida **[CLOUD-SETUP.md](CLOUD-SETUP.md)**.
>
> File aggiunti, tutti **accanto** al P2P senza modificarlo:
> - `lib/sync/cloud_config.dart` — chiavi Supabase (via `--dart-define`)
> - `lib/sync/cloud_sync_service.dart` — push/pull dello stesso `SyncPayload`
> - `lib/services/app_settings.dart` — flag premium + modalità sync + codice ristorante
> - `lib/ui/widgets/cloud_settings_card.dart` — sezione "Cloud (Premium)" nelle Impostazioni
> - `supabase/schema.sql` — tabelle, RLS e bucket foto

Questo documento descrive come si aggancia il cloud **sopra** la Fase 1, senza
buttare via niente di quello già fatto.

## Perché si innesta senza riscrivere

In Fase 1 i dati sono già progettati per la sincronizzazione:

- ogni record (`Wine`, `Movement`) ha `id` univoco, `updated_at`, `deleted`;
- la fusione è "last-write-wins" + unione di eventi (vedi
  `lib/data/repositories/inventory_repository.dart` → `mergeWine` / `mergeMovement`);
- il formato di scambio è già astratto in `lib/sync/sync_payload.dart`.

Il cloud è semplicemente **un altro "trasporto"** dello stesso payload: oggi
viaggia via HTTP sul WiFi locale (`p2p_sync_service.dart`), domani viaggerà
verso/da un database condiviso online.

## Cosa aggiungere

1. **Backend Supabase** (gratis per iniziare):
   - tabelle `wines` e `movements` con le stesse colonne del DB locale;
   - **Storage** per le foto;
   - **Auth** email/password per i colleghi;
   - **Row Level Security** per isolare i dati per `restaurant_id`
     (necessario quando si passa a più ristoranti).

2. **CloudSyncService** (nuovo file in `lib/sync/`):
   - *push*: invia i record con `updated_at` più recente del last-sync;
   - *pull*: scarica i record remoti cambiati dopo il last-sync e li fonde con
     `SyncPayload.applyTo` (la logica di merge è già pronta);
   - upload/download foto su Supabase Storage.

3. **Modalità nelle impostazioni** (il modello freemium):
   ```
   Sincronizzazione:  ( ) Locale P2P  (gratis)   ( ) Cloud  (premium)
   ```

4. **Abbonamento**:
   - Android: Google Play Billing (in-app purchase) tramite il pacchetto
     `in_app_purchase`;
   - oppure pagamenti via Stripe con verifica lato backend.
   - Lo stato "premium" sblocca la modalità Cloud.

## Multi-ristorante

Aggiungere una colonna `restaurant_id` a vini e movimenti e filtrare tutto per
quell'id (sia in locale sia nel cloud). I colleghi entrano nello stesso
ristorante tramite un **codice d'invito**. Le regole RLS di Supabase
garantiscono che un ristorante non veda i dati di un altro.

> Nota: la sincronizzazione P2P della Fase 1 continuerà a funzionare anche con
> il cloud attivo (es. sync veloce in sala anche se internet è lento).
