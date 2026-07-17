-- =====================================================================
-- DIZIONARIO COLLABORATIVO dei nomi di vino (anonimo)
-- =====================================================================
-- L'OCR dell'app propone i nomi confrontandoli con un dizionario locale.
-- Questo file crea la parte CENTRALE: ogni telefono propone i nomi dei vini
-- che salva; quando lo STESSO vino (nome + produttore) arriva da DUE
-- ristoranti DIVERSI viene "confermato" ed entra nel dizionario.
--
-- PRIVACY ("il db si scorda da chi ha avuto l'info"):
--   - delle proposte si salva solo un hash irreversibile del ristorante,
--     che serve unicamente a contare i ristoranti DIVERSI;
--   - alla conferma le proposte vengono CANCELLATE: nel dizionario finale
--     resta solo nome/produttore/regione, senza alcuna traccia dell'origine;
--   - non si caricano mai prezzi, quantita' o altri dati dell'inventario.
--
-- DISTRIBUZIONE: l'app NON scarica nulla a runtime. A ogni release:
--   1. SQL Editor → esegui:
--        select name, producer, region from wine_dictionary order by name;
--      → Download CSV
--   2. incolla le righe in assets/wine_names.csv dell'app (formato
--      nome;produttore;regione) e alza _assetVersion in
--      lib/services/dictionary_service.dart → alla release successiva
--      TUTTI i telefoni (anche senza cloud) ricevono il dizionario nuovo.
--
-- Per importare un dataset esterno (es. X-Wines) direttamente tra i
-- confermati, dal SQL Editor:
--   insert into wine_dictionary(name_norm, producer_norm, name, producer, region, source)
--   values (dict_norm('Nome'), dict_norm('Produttore'), 'Nome', 'Produttore', 'Regione', 'xwines')
--   on conflict do nothing;
--
-- Pulizia occasionale delle proposte mai confermate (opzionale):
--   delete from wine_dictionary_pending where created_at < now() - interval '1 year';
-- =====================================================================

create extension if not exists unaccent;

-- Normalizzazione IDENTICA a quella dell'app
-- (lib/services/text_normalizer.dart): se cambi qui, cambia anche la'.
create or replace function public.dict_norm(t text)
returns text
language sql
stable
as $$
  select trim(regexp_replace(
           regexp_replace(lower(unaccent(coalesce(t, ''))), '[^a-z0-9 ]', ' ', 'g'),
           '\s+', ' ', 'g'));
$$;

-- Il dizionario confermato: anonimo per costruzione.
create table if not exists wine_dictionary (
  name_norm     text not null,
  producer_norm text not null default '',
  name          text not null,
  producer      text not null default '',
  region        text not null default '',
  source        text not null default 'user',   -- 'user' | 'xwines' | 'seed'
  created_at    timestamptz not null default now(),
  primary key (name_norm, producer_norm)
);

-- Proposte in attesa di conferma. L'hash del ristorante e' irreversibile e
-- le righe si cancellano appena il vino e' confermato.
create table if not exists wine_dictionary_pending (
  name_norm        text not null,
  producer_norm    text not null default '',
  name             text not null,
  producer         text not null default '',
  region           text not null default '',
  contributor_hash text not null,
  created_at       timestamptz not null default now(),
  primary key (name_norm, producer_norm, contributor_hash)
);

alter table wine_dictionary         enable row level security;
alter table wine_dictionary_pending enable row level security;

-- Il dizionario confermato e' leggibile da chi e' loggato (e' gia' anonimo);
-- si scrive SOLO tramite la funzione qui sotto (o dalla dashboard).
drop policy if exists wine_dictionary_select on wine_dictionary;
create policy wine_dictionary_select on wine_dictionary
  for select to authenticated using (true);

-- Nessuna policy su wine_dictionary_pending: dall'app non si legge ne' si
-- scrive direttamente, si passa solo da suggest_wine_name (security definer).

-- Propone un vino al dizionario. Chiamata dall'app al salvataggio di un vino
-- il cui nome non e' gia' nel dizionario locale.
create or replace function public.suggest_wine_name(
  p_restaurant uuid,
  p_name       text,
  p_producer   text default '',
  p_region     text default ''
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_name_norm text := dict_norm(p_name);
  v_prod_norm text := dict_norm(p_producer);
  v_hash      text;
begin
  if not is_member(p_restaurant) then
    raise exception 'Non sei membro di questo ristorante';
  end if;
  -- Se vuoi limitare i contributi ai soli ristoranti con piano cloud,
  -- aggiungi qui:  if not has_cloud(p_restaurant) then return; end if;

  if length(v_name_norm) < 3 then
    return;
  end if;

  -- Gia' confermato: niente da fare.
  if exists (select 1 from wine_dictionary
             where name_norm = v_name_norm and producer_norm = v_prod_norm) then
    return;
  end if;

  -- Hash anonimo e irreversibile del ristorante: serve SOLO a contare
  -- "quanti ristoranti diversi" hanno proposto lo stesso vino. Volendo, il
  -- suffisso fisso si puo' spostare in un segreto del Vault.
  v_hash := md5(p_restaurant::text || 'cantina-dizionario-v1');

  insert into wine_dictionary_pending
      (name_norm, producer_norm, name, producer, region, contributor_hash)
    values
      (v_name_norm, v_prod_norm,
       left(trim(p_name), 120),
       left(trim(coalesce(p_producer, '')), 120),
       left(trim(coalesce(p_region, '')), 120),
       v_hash)
    on conflict do nothing;

  -- Conferma: stesso nome+produttore proposto da almeno 2 ristoranti diversi.
  if (select count(distinct contributor_hash)
        from wine_dictionary_pending
        where name_norm = v_name_norm and producer_norm = v_prod_norm) >= 2 then
    insert into wine_dictionary
        (name_norm, producer_norm, name, producer, region, source)
      select name_norm, producer_norm, name, producer, region, 'user'
        from wine_dictionary_pending
        where name_norm = v_name_norm and producer_norm = v_prod_norm
        order by created_at
        limit 1
      on conflict do nothing;
    -- "Si scorda" chi l'ha proposto.
    delete from wine_dictionary_pending
      where name_norm = v_name_norm and producer_norm = v_prod_norm;
  end if;
end;
$$;
