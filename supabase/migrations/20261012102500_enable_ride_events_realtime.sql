-- Track the Realtime publication configuration used by the customer app.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'ride_events'
  ) then
    alter publication supabase_realtime add table public.ride_events;
  end if;
end $$;
