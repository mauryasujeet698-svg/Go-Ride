-- Keep an auditable record of Admin-controlled configuration changes.
create or replace function public.audit_configuration_changes()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $audit$
declare
  v_new jsonb;
  v_old jsonb;
  v_row jsonb;
  v_actor uuid;
  v_entity_id text;
  v_actor_type text;
begin
  v_actor := auth.uid();
  v_new := case when tg_op = 'DELETE' then null else to_jsonb(new) end;
  v_old := case when tg_op = 'INSERT' then null else to_jsonb(old) end;
  v_row := coalesce(v_new, v_old);
  v_entity_id := coalesce(v_row->>'id', v_row->>'code', v_row->>'category', v_row->>'singleton', v_row->>'area_id');
  v_actor_type := case when v_actor is not null and public.has_app_role('admin') then 'admin' else 'system' end;

  insert into public.audit_events(actor_id, actor_type, action, entity_type, entity_id, outcome, metadata)
  values (
    v_actor,
    v_actor_type,
    lower('config.' || tg_table_name || '_' || tg_op),
    tg_table_name,
    v_entity_id,
    'success',
    jsonb_build_object('operation', tg_op, 'old', v_old, 'new', v_new)
  );

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$audit$;
revoke all on function public.audit_configuration_changes() from public, anon, authenticated;

drop trigger if exists audit_service_areas_changes on public.service_areas;
create trigger audit_service_areas_changes after insert or update or delete on public.service_areas
for each row execute function public.audit_configuration_changes();

drop trigger if exists audit_area_business_settings_changes on public.area_business_settings;
create trigger audit_area_business_settings_changes after insert or update or delete on public.area_business_settings
for each row execute function public.audit_configuration_changes();

drop trigger if exists audit_subscription_plans_changes on public.subscription_plans;
create trigger audit_subscription_plans_changes after insert or update or delete on public.subscription_plans
for each row execute function public.audit_configuration_changes();

drop trigger if exists audit_ai_runtime_settings_changes on public.ai_runtime_settings;
create trigger audit_ai_runtime_settings_changes after insert or update or delete on public.ai_runtime_settings
for each row execute function public.audit_configuration_changes();

drop trigger if exists audit_pricing_rules_changes on public.pricing_rules;
create trigger audit_pricing_rules_changes after insert or update or delete on public.pricing_rules
for each row execute function public.audit_configuration_changes();
