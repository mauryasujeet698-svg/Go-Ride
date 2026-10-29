-- Guest fare estimates are served through the estimate-route-fares Edge Function.
-- That function invokes estimate_guest_fares with its server-side service_role client.
-- Direct client execution is therefore unnecessary and creates an avoidable
-- SECURITY DEFINER entry point in the exposed public schema.
REVOKE EXECUTE ON FUNCTION public.estimate_guest_fares(double precision, integer) FROM anon, authenticated;
