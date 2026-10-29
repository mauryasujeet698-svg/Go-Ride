-- Limit clients to editable profile/place fields; IDs and audit timestamps stay server-controlled.
revoke update on public.profiles from authenticated;
grant update (full_name, phone, avatar_url) on public.profiles to authenticated;
revoke update on public.saved_places from authenticated;
grant update (label, address, latitude, longitude) on public.saved_places to authenticated;
