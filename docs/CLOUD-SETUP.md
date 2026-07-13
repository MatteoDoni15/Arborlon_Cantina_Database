# ☁️ Attivare il Cloud (Fase 2)

Il cloud è un **plus premium**: si aggiunge sopra l'app locale + P2P, senza
sostituirli. Se non lo configuri, l'app continua a funzionare esattamente come
prima (locale + sync P2P sul WiFi).

Servono ~10 minuti e un account gratuito Supabase.

## 1. Crea il progetto Supabase

1. Vai su <https://supabase.com> → **New project** (il piano gratuito basta per iniziare).
2. Scegli nome e password del database, attendi che il progetto sia pronto.

## 2. Crea le tabelle, le policy e il bucket foto

1. Nel progetto: **SQL Editor** → **New query**.
2. Incolla tutto il contenuto di [`supabase/schema.sql`](../supabase/schema.sql) e premi **Run**.

Questo crea le tabelle `wines` e `movements`, le regole di sicurezza (RLS) e il
bucket privato `photos`.

## 3. Prendi le chiavi

In **Project Settings → API** copia:

- **Project URL** (es. `https://xxxx.supabase.co`)
- **anon public key** (una stringa lunga che inizia con `eyJ...`)

## 3b. (Opzionale) Abilita il login con Google

Il login email/password funziona subito, senza configurare nulla. Per offrire
anche **"Continua con Google"**:

1. Vai su <https://console.cloud.google.com> → crea (o scegli) un progetto →
   **APIs & Services → OAuth consent screen** e completa la schermata di
   consenso (tipo *External*, bastano nome app e email).
2. **APIs & Services → Credentials → Create credentials → OAuth client ID**:
   - Tipo: **Web application** (sì, "Web", anche se l'app è mobile: il flusso
     passa dal browser e da Supabase).
   - **Authorized redirect URIs**: `https://<TUO-PROGETTO>.supabase.co/auth/v1/callback`
   - Salva e copia **Client ID** e **Client secret**.
3. In Supabase: **Authentication → Providers → Google** → attiva e incolla
   Client ID e Client secret.
4. Sempre in Supabase: **Authentication → URL Configuration → Redirect URLs** →
   aggiungi:
   ```
   io.supabase.cantinavini://login-callback/
   ```
   (è il deep link con cui il browser riapre l'app: vedi
   `CloudConfig.oauthRedirectUri`).

Come funziona nell'app: il bottone **Continua con Google** apre il browser,
l'utente sceglie l'account Google e il telefono torna automaticamente
nell'app già autenticato. Funziona su Android e iOS (il deep link è registrato
nei rispettivi manifest); su desktop usa il login email.

## 4. Avvia l'app con le chiavi

Le chiavi NON vanno nel codice/repo: si passano al build.

```powershell
flutter run `
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=eyJhbGci...
```

(Per la build di rilascio: stessi `--dart-define` su `flutter build apk`.)

Se le chiavi mancano, la sezione **Cloud (Premium)** nelle Impostazioni resta
disabilitata e mostra un avviso — tutto il resto funziona comunque.

## 5. Usa il cloud nell'app

**Impostazioni → Cloud (Premium):**

1. Attiva l'**abbonamento premium** (per ora è un flag manuale; in futuro sarà
   un acquisto in-app).
2. Scegli la modalità **Cloud**.
3. **Registrati / Accedi** con email e password, oppure tocca **Continua con
   Google** (se hai fatto il passo 3b).
4. Crea o entra in un ristorante:
   - **Il primo** (es. il titolare): inserisce il nome e tocca **Crea
     ristorante**. L'app mostra un **codice invito** (es. `A1B2C3`) e, con
     l'icona QR accanto al codice, il **QR invito** da far inquadrare.
   - **I colleghi**: ognuno si registra/accede, poi tocca **Inquadra il QR
     invito di un collega** (o, in alternativa, **Entra con codice invito**
     scrivendo il codice a mano).
5. **Sincronizza col cloud ora**.

Tutti i membri dello stesso ristorante vedono gli stessi dati, da qualsiasi
rete. La sicurezza (RLS) garantisce che un ristorante non veda i dati di un
altro: ogni utente accede **solo** ai ristoranti di cui è membro.

## Note

- **Il P2P resta sempre disponibile**, anche con il cloud attivo: utile per una
  sync veloce in sala quando internet è lento.
- **Merge identico al P2P**: vince l'ultima modifica (`updated_at`), i movimenti
  sono eventi immutabili. Nessun conflitto mescolando le due modalità.
- **Multi-ristorante (multi-tenant)**: lo schema usa le tabelle `restaurants` e
  `restaurant_members` con RLS basata sull'appartenenza: ogni utente vede solo i
  ristoranti di cui è membro. Più locali convivono nello stesso database,
  completamente isolati. Le foto sono separate per ristorante nello Storage
  (path `<restaurant_id>/<file>`).
- **Pagamenti reali**: il flag premium è il punto in cui aggancere Google Play
  Billing (`in_app_purchase`) o Stripe, in un secondo momento.

## Abbonamento (chi ha il cloud)

L'abbonamento è **per ristorante**: la tabella `restaurants` ha una colonna
`plan` (`free` = solo P2P, `cloud` = cloud sbloccato per tutti i colleghi del
locale) e `plan_renews_at` (scadenza). Gli utenti gratis non hanno alcun record:
il P2P è locale e non tocca Supabase.

- **Stato attuale (solo tracciamento):** l'app legge il piano e lo mostra
  (badge "Gratuito" / "Cloud"), ma **non blocca** ancora la sync.
- **Attivare il cloud per un ristorante (per i test):** dalla dashboard Supabase
  → Table Editor → `restaurants` → metti `plan` = `cloud` sulla riga del tuo
  ristorante. Oppure via SQL:
  ```sql
  update restaurants set plan = 'cloud' where invite_code = 'A1B2C3';
  ```
  Alla sync successiva l'app rileggerà il piano e il badge diventerà "Cloud".
- **In futuro (blocco reale):** quando colleghi i pagamenti, aggiungi
  `and has_cloud(restaurant_id)` alle policy RLS di `wines`/`movements` per far
  rifiutare al server la sync dei ristoranti senza abbonamento. La funzione
  `has_cloud()` è già pronta nello schema.
