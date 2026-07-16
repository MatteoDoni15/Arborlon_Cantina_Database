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

## 4. Avvia l'app con le chiavi

Le chiavi NON vanno nel codice/repo: si passano al build.

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

Se le chiavi mancano, la sezione **Cloud (Premium)** nelle Impostazioni resta
disabilitata e mostra un avviso — tutto il resto funziona comunque.

## 5. Usa il cloud nell'app

**Impostazioni → Cloud (Premium):**

1. Attiva l'**abbonamento premium** (per ora è un flag manuale; in futuro sarà
   un acquisto in-app).
2. Scegli la modalità **Cloud**.
3. **Registrati / Accedi** con email e password.
4. Crea o entra in un ristorante:
   - **Il primo** (es. il titolare): inserisce il nome e tocca **Crea
     ristorante**. L'app mostra un **codice invito** (es. `A1B2C3`).
   - **I colleghi**: ognuno si registra/accede, poi tocca **Entra con codice
     invito** e inserisce quel codice.
5. **Sincronizza col cloud ora**.

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

### Template col codice a 6 cifre (⚠️ passaggio obbligatorio)

L'app **non usa i link** nelle email (su mobile servirebbero i deep link): usa
**codici a 6 cifre** che l'utente ricopia nell'app. Perché il codice compaia,
i template in Supabase → Authentication → Emails → **Templates** devono
contenere `{{ .Token }}`. Da sistemare almeno questi due:

- **Reset password** (usato da "Password dimenticata?"):

  ```html
  <h2>Recupero password — Arborlon Cantina</h2>
  <p>Il tuo codice di recupero è: <strong style="font-size:24px">{{ .Token }}</strong></p>
  <p>Inseriscilo nell'app entro un'ora. Se non hai richiesto tu il codice, ignora questa email.</p>
  ```

- **Confirm sign up** (usato alla registrazione):

  ```html
  <h2>Benvenuto in Arborlon Cantina!</h2>
  <p>Il tuo codice di conferma è: <strong style="font-size:24px">{{ .Token }}</strong></p>
  <p>Inseriscilo nell'app per attivare l'account.</p>
  ```

Se un template contiene solo `{{ .ConfirmationURL }}` (il default), l'utente
riceve un link che non riporta all'app: il flusso col codice non funziona.

### Flussi disponibili nell'app (Impostazioni → Cloud)

- **Password dimenticata?** → email → codice → nuova password (e accesso).
- **Registrati** → codice di conferma chiesto subito dopo (con "invia di nuovo").
- Login con email non confermata → l'app propone da sola il codice.
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
