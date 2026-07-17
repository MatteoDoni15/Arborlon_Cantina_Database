-- =====================================================================
-- Import di X-Wines (vini italiani) nel dizionario confermato
-- =====================================================================
-- Prerequisito: aver gia' eseguito supabase/dizionario-vini.sql.
--
-- Il file supabase/xwines-italia.csv contiene 19.333 vini italiani estratti
-- dal dataset X-Wines (licenza CC0, quindi uso libero anche commerciale).
-- Gli stessi vini sono gia' nell'asset dell'app (assets/wine_names.csv):
-- caricarli anche qui serve solo a tenere pulita la "sala d'attesa"
-- (wine_dictionary_pending), cosi' i vini gia' noti non vengono riproposti
-- da telefoni con versioni vecchie dell'app.
--
-- PASSI (dashboard Supabase, progetto cantina-vini):
--   1. SQL Editor → esegui il PASSO 1 qui sotto (crea la tabella d'appoggio).
--   2. Table Editor → tabella `xwines_staging` → ... (menu) → Import data
--      from CSV → carica supabase/xwines-italia.csv → Import.
--      (le colonne name/producer/region si mappano da sole dall'header)
--   3. SQL Editor → esegui il PASSO 2 qui sotto (travasa e pulisce).
-- =====================================================================

-- PASSO 1 — tabella d'appoggio per l'import CSV.
-- RLS attiva senza policy: invisibile alle app; la dashboard la vede comunque.
create table if not exists xwines_staging (
  name     text,
  producer text,
  region   text
);
alter table xwines_staging enable row level security;

-- =====================================================================
-- PASSO 2 — dopo aver caricato il CSV: travasa nel dizionario e pulisci.
-- (esegui queste righe insieme, dopo l'import del Table Editor)
-- =====================================================================
-- insert into wine_dictionary (name_norm, producer_norm, name, producer, region, source)
--   select dict_norm(name), dict_norm(producer),
--          trim(name), trim(coalesce(producer, '')), trim(coalesce(region, '')),
--          'xwines'
--   from xwines_staging
--   where length(dict_norm(name)) >= 3
--   on conflict do nothing;
--
-- drop table xwines_staging;
--
-- Verifica: select count(*) from wine_dictionary where source = 'xwines';
-- (atteso: ~19.300)
