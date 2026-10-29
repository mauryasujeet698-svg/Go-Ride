-- Consolidate RLS read policies and index foreign keys for the new operational tables.
-- has_app_role only checks the current auth.uid(); it does not need to bypass RLS.
create or replace function public.has_app_role(p_role text)
returns boolean
language sql
stable
security invoker
set search_path = public, pg_temp
as $role$
  select exists (
    select 1 from public.user_roles r
    where r.user_id = auth.uid()
      and r.role = p_role
      and r.status = 'active'
      and r.revoked_at is null
  );
$role$;
revoke all on function public.has_app_role(text) from public, anon;
grant execute on function public.has_app_role(text) to authenticated;

drop policy if exists service_areas_read_active on public.service_areas;
drop policy if exists service_areas_anon_read_active on public.service_areas;
create policy service_areas_anon_read_active on public.service_areas
for select to anon using (active);
drop policy if exists service_areas_authenticated_read_active_or_admin on public.service_areas;
create policy service_areas_authenticated_read_active_or_admin on public.service_areas
for select to authenticated using (active or public.has_app_role('admin'));

drop policy if exists area_business_settings_read_active on public.area_business_settings;
drop policy if exists area_business_settings_anon_read_active on public.area_business_settings;
create policy area_business_settings_anon_read_active on public.area_business_settings
for select to anon using (
  active and exists (select 1 from public.service_areas a where a.id = area_id and a.active)
);
drop policy if exists area_business_settings_authenticated_read_active_or_admin on public.area_business_settings;
create policy area_business_settings_authenticated_read_active_or_admin on public.area_business_settings
for select to authenticated using (
  (active and exists (select 1 from public.service_areas a where a.id = area_id and a.active))
  or public.has_app_role('admin')
);

drop policy if exists subscription_plans_read_active on public.subscription_plans;
drop policy if exists subscription_plans_anon_read_active on public.subscription_plans;
create policy subscription_plans_anon_read_active on public.subscription_plans
for select to anon using (
  active and exists (select 1 from public.service_areas a where a.id = area_id and a.active)
);
drop policy if exists subscription_plans_authenticated_read_active_or_admin on public.subscription_plans;
create policy subscription_plans_authenticated_read_active_or_admin on public.subscription_plans
for select to authenticated using (
  (active and exists (select 1 from public.service_areas a where a.id = area_id and a.active))
  or public.has_app_role('admin')
);

drop policy if exists service_areas_admin_manage on public.service_areas;
drop policy if exists service_areas_admin_insert on public.service_areas;
create policy service_areas_admin_insert on public.service_areas
for insert to authenticated with check (public.has_app_role('admin'));
drop policy if exists service_areas_admin_update on public.service_areas;
create policy service_areas_admin_update on public.service_areas
for update to authenticated using (public.has_app_role('admin')) with check (public.has_app_role('admin'));
drop policy if exists service_areas_admin_delete on public.service_areas;
create policy service_areas_admin_delete on public.service_areas
for delete to authenticated using (public.has_app_role('admin'));

drop policy if exists area_business_settings_admin_manage on public.area_business_settings;
drop policy if exists area_business_settings_admin_insert on public.area_business_settings;
create policy area_business_settings_admin_insert on public.area_business_settings
for insert to authenticated with check (public.has_app_role('admin'));
drop policy if exists area_business_settings_admin_update on public.area_business_settings;
create policy area_business_settings_admin_update on public.area_business_settings
for update to authenticated using (public.has_app_role('admin')) with check (public.has_app_role('admin'));
drop policy if exists area_business_settings_admin_delete on public.area_business_settings;
create policy area_business_settings_admin_delete on public.area_business_settings
for delete to authenticated using (public.has_app_role('admin'));

drop policy if exists subscription_plans_admin_manage on public.subscription_plans;
drop policy if exists subscription_plans_admin_insert on public.subscription_plans;
create policy subscription_plans_admin_insert on public.subscription_plans
for insert to authenticated with check (public.has_app_role('admin'));
drop policy if exists subscription_plans_admin_update on public.subscription_plans;
create policy subscription_plans_admin_update on public.subscription_plans
for update to authenticated using (public.has_app_role('admin')) with check (public.has_app_role('admin'));
drop policy if exists subscription_plans_admin_delete on public.subscription_plans;
create policy subscription_plans_admin_delete on public.subscription_plans
for delete to authenticated using (public.has_app_role('admin'));

drop policy if exists pricing_rules_read_authenticated on public.pricing_rules;
create policy pricing_rules_read_authenticated on public.pricing_rules
for select to authenticated using (enabled or public.has_app_role('admin'));
drop policy if exists pricing_rules_admin_manage on public.pricing_rules;
drop policy if exists pricing_rules_admin_insert on public.pricing_rules;
create policy pricing_rules_admin_insert on public.pricing_rules
for insert to authenticated with check (public.has_app_role('admin'));
drop policy if exists pricing_rules_admin_update on public.pricing_rules;
create policy pricing_rules_admin_update on public.pricing_rules
for update to authenticated using (public.has_app_role('admin')) with check (public.has_app_role('admin'));
drop policy if exists pricing_rules_admin_delete on public.pricing_rules;
create policy pricing_rules_admin_delete on public.pricing_rules
for delete to authenticated using (public.has_app_role('admin'));

drop policy if exists driver_applications_admin_read on public.driver_applications;
drop policy if exists driver_applications_read_self on public.driver_applications;
drop policy if exists driver_applications_read_self_or_admin on public.driver_applications;
create policy driver_applications_read_self_or_admin on public.driver_applications
for select to authenticated using (user_id = (select auth.uid()) or public.has_app_role('admin'));

drop policy if exists profiles_admin_read on public.profiles;
drop policy if exists profiles_select_own on public.profiles;
drop policy if exists profiles_select_own_or_admin on public.profiles;
create policy profiles_select_own_or_admin on public.profiles
for select to authenticated using (id = (select auth.uid()) or public.has_app_role('admin'));

drop policy if exists driver_profiles_admin_read on public.driver_profiles;
drop policy if exists driver_profiles_select_self on public.driver_profiles;
drop policy if exists driver_profiles_select_self_or_admin on public.driver_profiles;
create policy driver_profiles_select_self_or_admin on public.driver_profiles
for select to authenticated using (user_id = (select auth.uid()) or public.has_app_role('admin'));

drop policy if exists vehicles_admin_read on public.vehicles;
drop policy if exists vehicles_select_assigned on public.vehicles;
drop policy if exists vehicles_select_assigned_or_admin on public.vehicles;
create policy vehicles_select_assigned_or_admin on public.vehicles
for select to authenticated using (
  public.has_app_role('admin')
  or exists (select 1 from public.driver_profiles d where d.user_id = (select auth.uid()) and d.user_id = vehicles.driver_id)
);

drop policy if exists rides_admin_read on public.rides;
drop policy if exists rides_select_participant on public.rides;
drop policy if exists rides_select_participant_or_admin on public.rides;
create policy rides_select_participant_or_admin on public.rides
for select to authenticated using (
  customer_id = (select auth.uid())
  or driver_id = (select auth.uid())
  or public.has_app_role('admin')
);

drop policy if exists ride_events_admin_read on public.ride_events;
drop policy if exists ride_events_select_participant on public.ride_events;
drop policy if exists ride_events_select_participant_or_admin on public.ride_events;
create policy ride_events_select_participant_or_admin on public.ride_events
for select to authenticated using (
  public.has_app_role('admin')
  or exists (
    select 1 from public.rides r
    where r.id = ride_events.ride_id
      and (r.customer_id = (select auth.uid()) or r.driver_id = (select auth.uid()))
  )
);

drop policy if exists support_tickets_admin_read on public.support_tickets;
drop policy if exists support_tickets_select_own on public.support_tickets;
drop policy if exists support_tickets_select_own_or_admin on public.support_tickets;
create policy support_tickets_select_own_or_admin on public.support_tickets
for select to authenticated using (user_id = (select auth.uid()) or public.has_app_role('admin'));

create index if not exists ai_runtime_settings_updated_by_idx on public.ai_runtime_settings(updated_by) where updated_by is not null;
create index if not exists area_business_settings_updated_by_idx on public.area_business_settings(updated_by) where updated_by is not null;
create index if not exists audit_events_actor_id_idx on public.audit_events(actor_id) where actor_id is not null;
create index if not exists driver_subscriptions_plan_id_idx on public.driver_subscriptions(plan_id);
create index if not exists service_areas_created_by_idx on public.service_areas(created_by) where created_by is not null;
create index if not exists service_areas_updated_by_idx on public.service_areas(updated_by) where updated_by is not null;
create index if not exists subscription_plans_area_id_idx on public.subscription_plans(area_id);
create index if not exists subscription_plans_created_by_idx on public.subscription_plans(created_by) where created_by is not null;
create index if not exists subscription_plans_updated_by_idx on public.subscription_plans(updated_by) where updated_by is not null;
create index if not exists support_tickets_assigned_to_idx on public.support_tickets(assigned_to) where assigned_to is not null;
create index if not exists support_ticket_messages_author_id_idx on public.support_ticket_messages(author_id) where author_id is not null;
