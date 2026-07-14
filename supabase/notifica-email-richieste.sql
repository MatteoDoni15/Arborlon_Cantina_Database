-- =====================================================================
-- OPZIONALE: email al gestore quando arriva una richiesta di attivazione
-- =====================================================================
-- Ogni insert in `cloud_requests` manda una mail via Mailtrap Email Sending
-- (mailtrap.io — piano gratuito: 150 mail/giorno). Prerequisiti, una volta:
--
--   1. Su Mailtrap → Sending Setup → Sending Domains:
--      - se hai verificato un TUO dominio, usa quello nel campo 'from' sotto;
--      - altrimenti c'è il dominio demo `demomailtrap.co`: funziona subito,
--        ma spedisce SOLO all'email con cui è registrato l'account Mailtrap
--        (in quel caso `v_to` deve essere quell'indirizzo).
--   2. Mailtrap → Settings → API Tokens → Add token con permesso di INVIO
--      (Sending access) → copia il token.
--   3. Dashboard Supabase (progetto cantina-vini) → Database → Extensions →
--      abilita `pg_net`.
--   4. SQL Editor → salva il token nel Vault (sostituisci IL_TUO_TOKEN):
--        select vault.create_secret('IL_TUO_TOKEN', 'mailtrap_api_token');
--   5. Esegui tutto questo file nel SQL Editor.
--
-- Per cambiare destinatario o mittente: modifica `v_to` o `v_from` qui sotto
-- e riesegui il file.

create extension if not exists pg_net;

create or replace function public.notify_cloud_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  api_key   text;
  rest_name text;
  v_to      text := 'teoxdoni@gmail.com';
  -- Mittente: indirizzo su un dominio verificato in Mailtrap (o il dominio
  -- demo `demomailtrap.co`). La casella non deve esistere davvero.
  v_from    text := 'hello@demomailtrap.co';
begin
  select decrypted_secret into api_key
    from vault.decrypted_secrets
    where name = 'mailtrap_api_token';
  -- Nessun token configurato: salta la mail senza bloccare la richiesta.
  if api_key is null then
    return new;
  end if;

  select name into rest_name from restaurants where id = new.restaurant_id;

  perform net.http_post(
    url := 'https://send.api.mailtrap.io/api/send',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Api-Token', api_key
    ),
    body := jsonb_build_object(
      'from', jsonb_build_object('email', v_from, 'name', 'Cantina Vini'),
      'to', jsonb_build_array(jsonb_build_object('email', v_to)),
      'subject', 'Nuova richiesta Cloud: ' || coalesce(rest_name, '(sconosciuto)'),
      'html',
        '<p>Il ristorante <b>' || coalesce(rest_name, '(sconosciuto)') ||
        '</b> (' || new.email || ') ha richiesto l''attivazione del cloud.</p>' ||
        '<p>Per approvare, esegui nel SQL Editor di Supabase:</p>' ||
        '<pre>select approve_cloud_request(''' || new.id || ''');</pre>',
      'category', 'cloud_request'
    )
  );
  return new;
exception when others then
  -- L'invio della mail non deve MAI far fallire la richiesta dell'utente.
  return new;
end;
$$;

drop trigger if exists trg_notify_cloud_request on cloud_requests;
create trigger trg_notify_cloud_request
  after insert on cloud_requests
  for each row execute function public.notify_cloud_request();
