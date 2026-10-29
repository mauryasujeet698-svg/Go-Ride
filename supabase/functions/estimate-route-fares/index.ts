import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: cors });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return json({ error: "server_configuration_missing" }, 503);

  try {
    const body = await req.json();
    const pickup = body?.pickup;
    const destination = body?.destination;
    const coordinates = [pickup?.latitude, pickup?.longitude, destination?.latitude, destination?.longitude];
    if (!coordinates.every((v) => typeof v === "number" && Number.isFinite(v)) ||
        pickup.latitude < -90 || pickup.latitude > 90 || destination.latitude < -90 || destination.latitude > 90 ||
        pickup.longitude < -180 || pickup.longitude > 180 || destination.longitude < -180 || destination.longitude > 180) {
      return json({ error: "invalid_coordinates" }, 400);
    }

    const mapboxToken = Deno.env.get("MAPBOX_ACCESS_TOKEN") || "";
    const routingBase = (Deno.env.get("ROUTING_URL") || "https://router.project-osrm.org").replace(/\/$/, "");
    const routeUrl = mapboxToken
      ? new URL(`https://api.mapbox.com/directions/v5/mapbox/driving/${pickup.longitude},${pickup.latitude};${destination.longitude},${destination.latitude}`)
      : new URL(`${routingBase}/route/v1/driving/${pickup.longitude},${pickup.latitude};${destination.longitude},${destination.latitude}`);
    routeUrl.searchParams.set("overview", "false");
    routeUrl.searchParams.set("steps", "false");
    if (mapboxToken) routeUrl.searchParams.set("access_token", mapboxToken);
    let routeResponse = await fetch(routeUrl, { signal: AbortSignal.timeout(12000) });
    if (!routeResponse.ok && mapboxToken) {
      const fallbackUrl = new URL(`${routingBase}/route/v1/driving/${pickup.longitude},${pickup.latitude};${destination.longitude},${destination.latitude}`);
      fallbackUrl.searchParams.set("overview", "false");
      fallbackUrl.searchParams.set("steps", "false");
      routeResponse = await fetch(fallbackUrl, { signal: AbortSignal.timeout(12000) });
    }
    if (!routeResponse.ok) return json({ error: "routing_unavailable" }, 503);
    const routeData = await routeResponse.json();
    const route = routeData?.routes?.[0];
    if (!route || !Number.isFinite(route.distance) || !Number.isFinite(route.duration)) return json({ error: "route_not_found" }, 422);
    const distanceKm = route.distance / 1000;
    const etaSeconds = Math.max(1, Math.round(route.duration));
    if (distanceKm > 200) return json({ error: "trip_too_long" }, 422);

    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const authorization = req.headers.get("Authorization") || "";
    const token = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
    let userId: string | null = null;
    if (token && !token.startsWith("sb_publishable_")) {
      const authClient = createClient(url, anonKey, {
        auth: { persistSession: false, autoRefreshToken: false },
        global: { headers: { Authorization: `Bearer ${token}` } },
      });
      const { data, error } = await authClient.auth.getUser(token);
      if (error || !data.user) return json({ error: "invalid_session" }, 401);
      userId = data.user.id;
    }

    if (userId) {
      const { data, error } = await admin.rpc("estimate_fares_from_route", {
        p_customer_id: userId, p_pickup_lat: pickup.latitude, p_pickup_lng: pickup.longitude,
        p_destination_lat: destination.latitude, p_destination_lng: destination.longitude,
        p_distance_km: distanceKm, p_eta_seconds: etaSeconds,
      });
      if (error) return json({ error: error.message.includes("rate_limited") ? "rate_limited" : "fare_estimate_failed" }, error.message.includes("rate_limited") ? 429 : 400);
      return json({ authenticated: true, distance_km: distanceKm, duration_seconds: etaSeconds, fares: data });
    }

    const { data, error } = await admin.rpc("estimate_guest_fares", { p_distance_km: distanceKm, p_eta_seconds: etaSeconds });
    if (error) return json({ error: "fare_estimate_unavailable" }, 503);
    return json({ authenticated: false, distance_km: distanceKm, duration_seconds: etaSeconds, fares: data });
  } catch (_) {
    return json({ error: "invalid_request_or_upstream_unavailable" }, 400);
  }
});
