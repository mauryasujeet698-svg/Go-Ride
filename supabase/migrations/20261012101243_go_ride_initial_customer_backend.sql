-- Go-Ride customer backend: initial schema, RLS policies and database routines.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.driver_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  phone text,
  status text not null default 'offline' check (status in ('offline','available','on_trip','suspended')),
  rating numeric(3,2) not null default 5.00 check (rating >= 0 and rating <= 5),
  created_at timestamptz not null default now()
);

create table if not exists public.vehicles (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.driver_profiles(user_id) on delete cascade,
  category text not null check (category in ('AUTO','MINI','SEDAN')),
  make_model text not null,
  plate_number text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.pricing_rules (
  category text primary key check (category in ('AUTO','MINI','SEDAN')),
  base_fare_minor integer not null check (base_fare_minor >= 0),
  per_km_minor integer not null check (per_km_minor >= 0),
  minimum_fare_minor integer not null check (minimum_fare_minor >= 0),
  currency char(3) not null default 'INR',
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.ride_quotes (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users(id) on delete cascade,
  pickup_lat double precision not null check (pickup_lat between -90 and 90),
  pickup_lng double precision not null check (pickup_lng between -180 and 180),
  destination_lat double precision not null check (destination_lat between -90 and 90),
  destination_lng double precision not null check (destination_lng between -180 and 180),
  category text not null references public.pricing_rules(category),
  fare_minor integer not null check (fare_minor >= 0),
  currency char(3) not null default 'INR',
  eta_seconds integer not null default 300 check (eta_seconds >= 0),
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.rides (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users(id) on delete cascade,
  driver_id uuid references public.driver_profiles(user_id),
  quote_id uuid not null references public.ride_quotes(id),
  idempotency_key uuid not null,
  status text not null default 'searching' check (status in ('searching','driver_assigned','driver_arriving','driver_arrived','otp_required','in_trip','completed','cancelled','failed')),
  seq bigint not null default 1 check (seq > 0),
  pickup_lat double precision not null check (pickup_lat between -90 and 90),
  pickup_lng double precision not null check (pickup_lng between -180 and 180),
  pickup_label text not null default '',
  destination_lat double precision not null check (destination_lat between -90 and 90),
  destination_lng double precision not null check (destination_lng between -180 and 180),
  destination_label text not null default '',
  category text not null check (category in ('AUTO','MINI','SEDAN')),
  fare_minor integer not null check (fare_minor >= 0),
  currency char(3) not null default 'INR',
  cancellation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  cancelled_at timestamptz,
  completed_at timestamptz,
  constraint rides_customer_id_idempotency_key_key unique (customer_id, idempotency_key)
);

create table if not exists public.ride_events (
  id bigint generated always as identity primary key,
  ride_id uuid not null references public.rides(id) on delete cascade,
  seq bigint not null,
  status text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint ride_events_ride_id_seq_key unique (ride_id, seq)
);

create table if not exists public.saved_places (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  label text not null check (length(label) between 1 and 60),
  address text not null default '',
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  created_at timestamptz not null default now()
);

create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  ride_id uuid references public.rides(id) on delete set null,
  subject text not null check (length(subject) between 3 and 120),
  message text not null check (length(message) between 5 and 5000),
  status text not null default 'open' check (status in ('open','in_progress','resolved','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists rides_customer_created_idx on public.rides(customer_id, created_at desc);
create index if not exists rides_driver_status_idx on public.rides(driver_id, status, updated_at desc);
create index if not exists ride_quotes_customer_expiry_idx on public.ride_quotes(customer_id, expires_at desc);
create index if not exists ride_events_ride_seq_idx on public.ride_events(ride_id, seq);
create index if not exists saved_places_user_idx on public.saved_places(user_id, created_at desc);
create index if not exists support_tickets_user_idx on public.support_tickets(user_id, created_at desc);

create unique index if not exists rides_one_active_per_customer
on public.rides(customer_id)
where status in ('searching','driver_assigned','driver_arriving','driver_arrived','otp_required','in_trip');

insert into public.pricing_rules(category, base_fare_minor, per_km_minor, minimum_fare_minor, currency, enabled)
values
  ('AUTO', 3000, 1200, 5000, 'INR', true),
  ('MINI', 4000, 1500, 7000, 'INR', true),
  ('SEDAN', 6000, 2000, 10000, 'INR', true)
on conflict (category) do nothing;

create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public, auth as $$
begin
  insert into public.profiles(id, full_name, phone)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name',''), new.phone)
  on conflict (id) do nothing;
  return new;
end;
$$;

create or replace function public.estimate_fares(
  p_pickup_lat double precision, p_pickup_lng double precision,
  p_destination_lat double precision, p_destination_lng double precision
)
returns table(quote_id uuid, category text, amount_minor integer, currency char(3), eta_seconds integer, expires_at timestamptz)
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_distance_km double precision;
  r record;
  v_fare integer;
begin
  if v_user is null then raise exception 'authentication_required' using errcode = '28000'; end if;
  if p_pickup_lat not between -90 and 90 or p_destination_lat not between -90 and 90
     or p_pickup_lng not between -180 and 180 or p_destination_lng not between -180 and 180 then
    raise exception 'invalid_coordinates' using errcode = '22023';
  end if;
  v_distance_km := 6371 * 2 * asin(sqrt(
    power(sin(radians(p_destination_lat - p_pickup_lat) / 2), 2) +
    cos(radians(p_pickup_lat)) * cos(radians(p_destination_lat)) *
    power(sin(radians(p_destination_lng - p_pickup_lng) / 2), 2)
  ));
  if v_distance_km > 200 then raise exception 'trip_too_long' using errcode = '22023'; end if;
  for r in select pr.* from public.pricing_rules pr where pr.enabled order by pr.category loop
    v_fare := greatest(r.minimum_fare_minor, r.base_fare_minor + ceil(v_distance_km * r.per_km_minor)::integer);
    quote_id := gen_random_uuid();
    category := r.category;
    amount_minor := v_fare;
    currency := r.currency;
    eta_seconds := 300;
    expires_at := now() + interval '2 minutes';
    insert into public.ride_quotes(id, customer_id, pickup_lat, pickup_lng, destination_lat, destination_lng, category, fare_minor, currency, eta_seconds, expires_at)
    values (quote_id, v_user, p_pickup_lat, p_pickup_lng, p_destination_lat, p_destination_lng, category, amount_minor, currency, eta_seconds, expires_at);
    return next;
  end loop;
end;
$$;

create or replace function public.create_ride(
  p_quote_id uuid, p_idempotency_key uuid,
  p_pickup_label text default '', p_destination_label text default ''
)
returns public.rides
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare
  v_user uuid := auth.uid();
  q public.ride_quotes%rowtype;
  v_ride public.rides%rowtype;
begin
  if v_user is null then raise exception 'authentication_required' using errcode = '28000'; end if;
  if p_idempotency_key is null or p_quote_id is null then raise exception 'invalid_request' using errcode = '22023'; end if;
  select * into v_ride from public.rides where customer_id = v_user and idempotency_key = p_idempotency_key;
  if found then return v_ride; end if;
  select * into q from public.ride_quotes where id = p_quote_id and customer_id = v_user for update;
  if not found then raise exception 'quote_not_found' using errcode = 'P0002'; end if;
  if q.expires_at <= now() then raise exception 'quote_expired' using errcode = '22023'; end if;
  if q.used_at is not null then raise exception 'quote_already_used' using errcode = '22023'; end if;
  if exists (select 1 from public.rides where customer_id = v_user and status in ('searching','driver_assigned','driver_arriving','driver_arrived','otp_required','in_trip')) then
    raise exception 'active_ride_exists' using errcode = '23505';
  end if;
  insert into public.rides(customer_id, quote_id, idempotency_key, status, seq, pickup_lat, pickup_lng, pickup_label, destination_lat, destination_lng, destination_label, category, fare_minor, currency)
  values (v_user, q.id, p_idempotency_key, 'searching', 1, q.pickup_lat, q.pickup_lng, left(coalesce(p_pickup_label,''),160), q.destination_lat, q.destination_lng, left(coalesce(p_destination_label,''),160), q.category, q.fare_minor, q.currency)
  returning * into v_ride;
  update public.ride_quotes set used_at = now() where id = q.id;
  return v_ride;
exception
  when unique_violation then
    select * into v_ride from public.rides where customer_id = auth.uid() and idempotency_key = p_idempotency_key;
    if found then return v_ride; end if;
    raise;
end;
$$;

create or replace function public.cancel_ride(
  p_ride_id uuid, p_idempotency_key uuid, p_reason text default 'customer_request'
)
returns public.rides
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_ride public.rides%rowtype;
begin
  if v_user is null then raise exception 'authentication_required' using errcode = '28000'; end if;
  if p_idempotency_key is null then raise exception 'invalid_request' using errcode = '22023'; end if;
  select * into v_ride from public.rides where id = p_ride_id and customer_id = v_user for update;
  if not found then raise exception 'ride_not_found' using errcode = 'P0002'; end if;
  if v_ride.status = 'cancelled' then return v_ride; end if;
  if v_ride.status not in ('searching','driver_assigned','driver_arriving','driver_arrived') then
    raise exception 'ride_not_cancellable' using errcode = '22023';
  end if;
  update public.rides set status = 'cancelled', cancellation_reason = left(coalesce(p_reason,'customer_request'),120), cancelled_at = now()
  where id = p_ride_id returning * into v_ride;
  return v_ride;
end;
$$;

create or replace function public.bump_ride_sequence()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if new.status is distinct from old.status or new.driver_id is distinct from old.driver_id then
    new.seq := old.seq + 1;
  else
    new.seq := old.seq;
  end if;
  return new;
end;
$$;

create or replace function public.record_ride_event()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    insert into public.ride_events(ride_id, seq, status, payload)
    values (new.id, new.seq, new.status, jsonb_build_object('driver_id', new.driver_id, 'fare_minor', new.fare_minor));
  elsif new.status is distinct from old.status or new.driver_id is distinct from old.driver_id then
    insert into public.ride_events(ride_id, seq, status, payload)
    values (new.id, new.seq, new.status, jsonb_build_object('driver_id', new.driver_id, 'fare_minor', new.fare_minor));
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at before update on public.profiles for each row execute function public.touch_updated_at();
drop trigger if exists rides_touch_updated_at on public.rides;
create trigger rides_touch_updated_at before update on public.rides for each row execute function public.touch_updated_at();
drop trigger if exists support_tickets_touch_updated_at on public.support_tickets;
create trigger support_tickets_touch_updated_at before update on public.support_tickets for each row execute function public.touch_updated_at();

drop trigger if exists rides_bump_sequence on public.rides;
create trigger rides_bump_sequence before update on public.rides for each row execute function public.bump_ride_sequence();
drop trigger if exists rides_record_event on public.rides;
create trigger rides_record_event after insert or update on public.rides for each row execute function public.record_ride_event();

alter table public.profiles enable row level security;
alter table public.driver_profiles enable row level security;
alter table public.vehicles enable row level security;
alter table public.pricing_rules enable row level security;
alter table public.ride_quotes enable row level security;
alter table public.rides enable row level security;
alter table public.ride_events enable row level security;
alter table public.saved_places enable row level security;
alter table public.support_tickets enable row level security;

drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles for select to authenticated using (id = (select auth.uid()));
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
drop policy if exists driver_profiles_select_self on public.driver_profiles;
create policy driver_profiles_select_self on public.driver_profiles for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists vehicles_select_assigned on public.vehicles;
create policy vehicles_select_assigned on public.vehicles for select to authenticated using (
  exists (select 1 from public.driver_profiles d where d.user_id = (select auth.uid()) and d.user_id = vehicles.driver_id)
);
drop policy if exists pricing_rules_read_authenticated on public.pricing_rules;
create policy pricing_rules_read_authenticated on public.pricing_rules for select to authenticated using (enabled);
drop policy if exists ride_quotes_select_own on public.ride_quotes;
create policy ride_quotes_select_own on public.ride_quotes for select to authenticated using (customer_id = (select auth.uid()));
drop policy if exists rides_select_participant on public.rides;
create policy rides_select_participant on public.rides for select to authenticated using (customer_id = (select auth.uid()) or driver_id = (select auth.uid()));
drop policy if exists ride_events_select_participant on public.ride_events;
create policy ride_events_select_participant on public.ride_events for select to authenticated using (
  exists (select 1 from public.rides r where r.id = ride_events.ride_id and (r.customer_id = (select auth.uid()) or r.driver_id = (select auth.uid())))
);
drop policy if exists saved_places_select_own on public.saved_places;
create policy saved_places_select_own on public.saved_places for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists saved_places_insert_own on public.saved_places;
create policy saved_places_insert_own on public.saved_places for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists saved_places_update_own on public.saved_places;
create policy saved_places_update_own on public.saved_places for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists saved_places_delete_own on public.saved_places;
create policy saved_places_delete_own on public.saved_places for delete to authenticated using (user_id = (select auth.uid()));
drop policy if exists support_tickets_select_own on public.support_tickets;
create policy support_tickets_select_own on public.support_tickets for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists support_tickets_insert_own on public.support_tickets;
create policy support_tickets_insert_own on public.support_tickets for insert to authenticated with check (
  user_id = (select auth.uid()) and
  (ride_id is null or exists (select 1 from public.rides r where r.id = support_tickets.ride_id and r.customer_id = (select auth.uid())))
);

revoke all privileges on all tables in schema public from anon, authenticated;
revoke all privileges on all sequences in schema public from anon, authenticated;
