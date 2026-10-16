begin;

create table if not exists public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('customer','driver','admin','support')),
  status text not null default 'active' check (status in ('pending','active','revoked')),
  granted_by uuid references auth.users(id) on delete set null,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique (user_id, role),
  check ((status = 'revoked' and revoked_at is not null) or (status <> 'revoked' and revoked_at is null))
);

create index if not exists user_roles_user_status_idx on public.user_roles(user_id, status);
alter table public.user_roles enable row level security;
revoke all on public.user_roles from anon, authenticated;
grant select on public.user_roles to authenticated;

drop policy if exists user_roles_read_self on public.user_roles;
create policy user_roles_read_self on public.user_roles for select to authenticated
  using (user_id = (select auth.uid()));

create table if not exists public.driver_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  full_name text not null check (length(trim(full_name)) between 2 and 120),
  phone text not null check (length(trim(phone)) between 7 and 20),
  vehicle_category text not null check (vehicle_category in ('BIKE','AUTO','MINI','SEDAN')),
  vehicle_make_model text not null check (length(trim(vehicle_make_model)) between 2 and 120),
  vehicle_registration text not null check (length(trim(vehicle_registration)) between 3 and 30),
  status text not null default 'pending' check (status in ('pending','in_review','approved','rejected','suspended')),
  review_note text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id),
  unique (vehicle_registration)
);

create index if not exists driver_applications_status_created_idx on public.driver_applications(status, created_at desc);
alter table public.driver_applications enable row level security;
revoke all on public.driver_applications from anon, authenticated;
grant select, insert on public.driver_applications to authenticated;

drop policy if exists driver_applications_read_self on public.driver_applications;
create policy driver_applications_read_self on public.driver_applications for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists driver_applications_insert_self on public.driver_applications;
create policy driver_applications_insert_self on public.driver_applications for insert to authenticated
  with check (user_id = (select auth.uid()) and status = 'pending'
    and reviewed_by is null and reviewed_at is null and review_note is null);

comment on table public.user_roles is 'Authoritative app roles. Clients may read their own assignments but cannot grant or revoke roles. Use trusted server-side administration.';
comment on table public.driver_applications is 'Driver onboarding requests. Review and approval must be performed by a trusted server; never expose service-role credentials in apps.';

commit;
