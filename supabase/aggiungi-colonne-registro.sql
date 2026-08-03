-- =====================================================================
-- Allinea un progetto Supabase GIÀ CREATO alle colonne più recenti.
-- =====================================================================
-- `schema.sql` usa "create table if not exists": va benissimo per un
-- progetto nuovo, ma su un progetto esistente non aggiunge colonne alle
-- tabelle già create. Questo script fa quel passo, in modo sicuro da
-- rilanciare più volte (ADD COLUMN IF NOT EXISTS).
--
-- Da eseguire UNA volta: Dashboard Supabase → SQL Editor → New query →
-- incolla tutto → Run.
--
-- Aggiunge:
--   - grape / denomination / country (filtri cantina, v4 locale)
--   - created_at / created_by / updated_by su wines, author_name su
--     movements (registro attività: chi ha aggiunto/venduto cosa, v5 locale)
-- =====================================================================

alter table wines add column if not exists grape        text not null default '';
alter table wines add column if not exists denomination text not null default '';
alter table wines add column if not exists country      text not null default '';

alter table wines add column if not exists created_at bigint not null default 0;
alter table wines add column if not exists created_by text   not null default '';
alter table wines add column if not exists updated_by text   not null default '';
-- I vini già sincronizzati non hanno una data di creazione nota: usiamo
-- l'ultima modifica come stima.
update wines set created_at = updated_at where created_at = 0;

alter table movements add column if not exists author_name text not null default '';
