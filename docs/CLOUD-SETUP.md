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

Le chiavi NON vanno nel codice/repo: si passano al build. Il modo comodo è il
file `env.json` nella radice del progetto (è già nel `.gitignore`):

```json
{
  "SUPABASE_URL": "https://xxxx.supabase.co",
  "SUPABASE_ANON_KEY": "eyJhbGci..."
}
```

Poi, sia per provare sia per la build di rilascio:

```powershell
flutter run --dart-define-from-file=env.json
flutter build apk --dart-define-from-file=env.json
```

Le chiavi vengono "cotte" dentro l'APK al momento della build: l'app
installata funziona da sola, senza bisogno di file esterni.

In alternativa si possono passare le singole chiavi a mano:

**Modo consigliato — file `.env`:** copia [`.env.example`](../.env.example) in
`.env` (è già nel `.gitignore`), compila `SUPABASE_URL` e `SUPABASE_ANON_KEY`,
poi:

```powershell
flutter run --dart-define-from-file=.env
```

**In alternativa, a mano:**

```powershell
flutter run `
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=eyJhbGci...
```

(Per la build di rilascio: stesse opzioni su `flutter build apk`.)

> Nota sicurezza: la **anon key** è pensata per stare nell'app pubblica — i
> dati sono protetti dalle policy RLS, non dalla segretezza della chiave. Il
> **Client Secret di Google** invece NON va mai nell'app né nel repo: vive solo
> nella dashboard Supabase (Providers → Google).

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
5. **Attiva il piano Cloud**: i ristoranti nuovi partono dal piano Gratuito e
   il server blocca la loro sync. Tocca **Richiedi attivazione Cloud** e
   attendi l'approvazione del gestore (vedi la sezione "Abbonamento" in fondo).
6. **Sincronizza col cloud ora**.

Tutti i membri dello stesso ristorante vedono gli stessi dati, da qualsiasi
rete. La sicurezza (RLS) garantisce che un ristorante non veda i dati di un
altro: ogni utente accede **solo** ai ristoranti di cui è membro.

## 6. Email di autenticazione (SMTP + template)

Le email di Auth (conferma registrazione, recupero password, avvisi di
sicurezza) le manda Supabase. Il mittente di default di Supabase è solo per
prova (limite ~2 email/ora): in produzione serve un **SMTP proprio**.

### SMTP (già collegato: Mailtrap)

Il progetto è collegato a **Mailtrap Email Sending** tramite l'integrazione
ufficiale (Supabase → Authentication → Emails → **SMTP Settings**):

- Host: `live.smtp.mailtrap.io`, porta `587`, utente `smtp@mailtrap.io`
- Mittente: `noreply@arborloncantina.com` (dominio verificato su Mailtrap:
  DKIM `rwmt1`/`rwmt2` + DMARC — controllabile in Mailtrap → Sending Domains)

### Template email

Si usano i template di **default** di Supabase (link `{{ .ConfirmationURL }}`):
**nessuna modifica necessaria**. Tutti i flussi passano dal link nell'email:
aprendolo dal telefono si torna nell'app tramite deep link (lo stesso
`io.supabase.cantinavini://login-callback/` registrato per il login Google,
già presente in Supabase → Authentication → URL Configuration → Redirect
URLs). Puoi personalizzare i testi dei template, basta che il link resti.

### Flussi disponibili nell'app (Impostazioni → Cloud)

- **Registrati** → l'app invita ad aprire il link di conferma ricevuto via
  email: il link riapre l'app già connessa (con "invia di nuovo l'email" e
  "Ho confermato" come alternativa se il link è stato aperto altrove).
- Login con email non confermata → l'app mostra lo stesso invito.
- **Password dimenticata?** → email col link → il link riapre l'app già
  autenticata e si sceglie subito la nuova password.
- **Cambia password** (icona 🔑 accanto all'account, da loggati).

### Limiti e test

- **Rate limit**: Supabase → Authentication → Rate Limits → "Emails sent".
  Con SMTP custom il default è basso (es. 30/ora): alzalo se serve.
- **Test rapido senza app** (spedisce una vera email di recupero):

  ```powershell
  curl.exe -s -X POST "https://XXXX.supabase.co/auth/v1/recover" `
    -H "apikey: LA_TUA_ANON_KEY" -H "Content-Type: application/json" `
    -d '{\"email\":\"tua-email@esempio.com\"}'
  ```

  Risposta `{}` = inviata. Se non arriva: Mailtrap → **Email Logs** mostra se
  Supabase ha consegnato la mail a Mailtrap e cosa ne è stato.

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

**Il blocco è reale**: le policy RLS di `wines`/`movements`/foto richiedono il
piano cloud attivo, quindi il server **rifiuta la sync** dei ristoranti
gratuiti. Il badge "Gratuito"/"Cloud" nell'app riflette questo stato. La
colonna `plan` non è modificabile dall'app (privilegi di colonna): la cambia
solo il gestore dalla dashboard.

Flusso di attivazione (finché non ci sono i pagamenti in-app):

1. Nell'app, il ristorante gratuito vede il pannello "Cloud non attivo" e
   tocca **Richiedi attivazione Cloud** → compare una riga `pending` nella
   tabella `cloud_requests` (una sola richiesta in attesa per ristorante).
2. Tu (gestore) controlli le richieste: Table Editor → `cloud_requests`,
   oppure:
   ```sql
   select cr.id, cr.email, r.name, cr.created_at
   from cloud_requests cr join restaurants r on r.id = cr.restaurant_id
   where cr.status = 'pending';
   ```
3. Approvi dal SQL Editor (attiva `plan='cloud'` e marca la richiesta):
   ```sql
   select approve_cloud_request('<id-della-richiesta>');
   ```
   Per rifiutare: `update cloud_requests set status = 'rejected' where id = '...';`
4. L'utente tocca **"Ho fatto richiesta: controlla se è attivo"**: il badge
   diventa "Cloud" e la sincronizzazione si sblocca.

Quando colleghi i pagamenti (Google Play Billing / Stripe), il webhook prenderà
il posto dell'approvazione manuale scrivendo `plan` e `plan_renews_at`.
