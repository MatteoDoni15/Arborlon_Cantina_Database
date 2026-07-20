-- =====================================================================
-- Import di X-Wines (vini mondiali) nel dizionario confermato
-- =====================================================================
-- Prerequisito: aver gia' eseguito supabase/dizionario-vini.sql.
--
-- Il file supabase/xwines-mondo.csv contiene 100.448 vini estratti dal
-- dataset X-Wines completo (licenza CC0, quindi uso libero anche commerciale),
-- di tutto il mondo (non solo Italia).
-- Gli stessi vini sono gia' nell'asset dell'app (assets/wine_names.csv):
-- caricarli anche qui serve solo a tenere pulita la "sala d'attesa"
-- (wine_dictionary_pending), cosi' i vini gia' noti non vengono riproposti
-- da telefoni con versioni vecchie dell'app.
--
-- Se in futuro vuoi restringere la copertura ai soli vini italiani (asset
-- piu' leggero), filtra il CSV originale per Country = 'Italy' prima
-- dell'import: la colonna Country non e' inclusa in questo export ridotto,
-- quindi rigenera i file dal CSV completo di X-Wines se ti serve.
--
-- PASSI (dashboard Supabase, progetto cantina-vini):
--   1. SQL Editor → esegui il PASSO 1 qui sotto (crea la tabella d'appoggio).
--   2. Table Editor → tabella `xwines_staging` → ... (menu) → Import data
--      from CSV → carica supabase/xwines-mondo.csv → Import.
--      (le colonne name/producer/region si mappano da sole dall'header;
--      il file e' ~5,6 MB: l'import puo' richiedere qualche minuto)
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
-- (atteso: ~100.400)
