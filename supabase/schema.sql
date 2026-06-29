-- =====================================================================
-- Cantina Vini — schema CLOUD multi-ristorante (Supabase / Postgres) — Fase 2
-- =====================================================================
-- Da eseguire UNA volta nel progetto Supabase:
--   Dashboard → SQL Editor → New query → incolla tutto → Run.
--
-- Modello MULTI-TENANT (più ristoranti nello stesso DB, isolati tra loro):
--   restaurants         → anagrafica ristoranti + codice invito
--   restaurant_members  → quale utente appartiene a quale ristorante (+ ruolo)
--   wines / movements   → dati, legati a un restaurant_id (come il DB locale)
--
-- La RLS garantisce che ogni utente veda SOLO i ristoranti di cui è membro.
-- `updated_at` è in millisecondi epoch (stesso merge LWW dell'app).
-- =====================================================================

-- 1) RISTORANTI -------------------------------------------------------
create table if not exists restaurants (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  invite_code    text not null unique,
  -- Abbonamento (modello freemium, per RISTORANTE):
  --   plan = 'free'  → solo P2P (default)
  --   plan = 'cloud' → cloud sbloccato per tutti i colleghi del locale
  -- plan_renews_at: scadenza dell'abbonamento (null = senza scadenza).
  -- Per ora si imposta a mano dalla dashboard; in futuro lo scriverà il webhook
  -- dei pagamenti (Stripe / Google Play) con privilegi service_role.
  plan           text not null default 'free',
  plan_renews_at timestamptz,
  created_by     uuid not null default auth.uid() references auth.users(id),
  created_at     timestamptz not null default now()
);

-- 2) MEMBRI (chi appartiene a quale ristorante) -----------------------
create table if not exists restaurant_members (
  restaurant_id uuid not null references restaurants(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  role          text not null default 'staff',   -- 'owner' | 'staff'
  created_at    timestamptz not null default now(),
  primary key (restaurant_id, user_id)
);

-- Funzione di appoggio: "l'utente corrente è membro di questo ristorante?"
-- security definer = bypassa la RLS internamente, così evita ricorsioni.
create or replace function public.is_member(p_restaurant uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from restaurant_members
    where restaurant_id = p_restaurant and user_id = auth.uid()
  );
$$;

-- "Questo ristorante ha il cloud attivo?" (piano 'cloud' non scaduto).
-- Per ora usata solo per informare l'app; quando si attiverà il blocco lato
-- server basterà aggiungere "and has_cloud(restaurant_id)" alle policy di
-- wines/movements.
create or replace function public.has_cloud(p_restaurant uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from restaurants
    where id = p_restaurant
      and plan = 'cloud'
      and (plan_renews_at is null or plan_renews_at > now())
  );
$$;

-- 3) VINI -------------------------------------------------------------
create table if not exists wines (
  id            text primary key,
  name          text not null default '',
  producer      text not null default '',
  vintage       integer,
  type          text not null default '',
  region        text not null default '',
  supplier      text not null default '',
  location      text not null default '',
  price_buy     double precision not null default 0,
  price_sell    double precision not null default 0,
  notes           text not null default '',
  photo_path      text,
  photo_path_back text,
  updated_at      bigint not null,
  deleted         integer not null default 0,
  restaurant_id   uuid not null references restaurants(id) on delete cascade
);
create index if not exists idx_wines_rest_updated on wines (restaurant_id, updated_at);

-- 4) MOVIMENTI --------------------------------------------------------
create table if not exists movements (
  id            text primary key,
  wine_id       text not null,
  kind          text not null,
  quantity      integer not null,
  unit_price    double precision not null default 0,
  note          text not null default '',
  photo_path    text,
  device_id     text not null default '',
  created_at    bigint not null,
  updated_at    bigint not null,
  deleted       integer not null default 0,
  restaurant_id uuid not null references restaurants(id) on delete cascade
);
create index if not exists idx_mov_rest_updated on movements (restaurant_id, updated_at);

-- =====================================================================
-- SICUREZZA (RLS): ognuno vede SOLO i ristoranti di cui è membro
-- =====================================================================
alter table restaurants        enable row level security;
alter table restaurant_members enable row level security;
alter table wines              enable row level security;
alter table movements          enable row level security;

drop policy if exists restaurants_rw on restaurants;
create policy restaurants_rw on restaurants
  for all to authenticated
  using (is_member(id)) with check (is_member(id));

drop policy if exists members_read on restaurant_members;
create policy members_read on restaurant_members
  for select to authenticated using (is_member(restaurant_id));

drop policy if exists wines_rw on wines;
create policy wines_rw on wines
  for all to authenticated
  using (is_member(restaurant_id)) with check (is_member(restaurant_id));

drop policy if exists movements_rw on movements;
create policy movements_rw on movements
  for all to authenticated
  using (is_member(restaurant_id)) with check (is_member(restaurant_id));

-- =====================================================================
-- FUNZIONI per creare/entrare in un ristorante (chiamate dall'app)
-- =====================================================================

-- Crea un ristorante: chi lo crea diventa 'owner' e riceve un codice invito.
create or replace function public.create_restaurant(p_name text)
returns restaurants
language plpgsql security definer set search_path = public
as $$
declare r restaurants;
begin
  insert into restaurants(name, invite_code, created_by)
    values (
      p_name,
      upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6)),
      auth.uid()
    )
    returning * into r;
  insert into restaurant_members(restaurant_id, user_id, role)
    values (r.id, auth.uid(), 'owner');
  return r;
end;
$$;

-- Entra in un ristorante esistente usando il codice invito.
create or replace function public.join_restaurant(p_code text)
returns restaurants
language plpgsql security definer set search_path = public
as $$
declare r restaurants;
begin
  select * into r from restaurants where invite_code = upper(p_code);
  if r.id is null then
    raise exception 'Codice invito non valido';
  end if;
  insert into restaurant_members(restaurant_id, user_id, role)
    values (r.id, auth.uid(), 'staff')
    on conflict do nothing;
  return r;
end;
$$;

-- =====================================================================
-- STORAGE: bucket foto, separato per ristorante (path = <restaurant_id>/file)
-- =====================================================================
insert into storage.buckets (id, name, public)
values ('photos', 'photos', false)
on conflict (id) do nothing;

drop policy if exists photos_rw on storage.objects;
create policy photos_rw on storage.objects
  for all to authenticated
  using (
    bucket_id = 'photos'
    and is_member( ((storage.foldername(name))[1])::uuid )
  )
  with check (
    bucket_id = 'photos'
    and is_member( ((storage.foldername(name))[1])::uuid )
  );
