import { z } from "zod";
import type { CoordinateInput, RoadRoute, RoutingProvider } from "./provider.js";

const responseSchema = z.object({
 code: z.string(),
 routes: z.array(z.object({
  distance: z.number().nonnegative(),
  duration: z.number().nonnegative(),
  geometry: z.object({
   coordinates: z.array(z.tuple([z.number(), z.number()])).min(2).max(10000)
  })
 })).optional()
});

function validateCoordinate(value: CoordinateInput): void {
 if (!Number.isFinite(value.latitude) || value.latitude < -90 || value.latitude > 90) throw new Error("Invalid latitude.");
 if (!Number.isFinite(value.longitude) || value.longitude < -180 || value.longitude > 180) throw new Error("Invalid longitude.");
}

export class OsrmCompatibleRoutingProvider implements RoutingProvider {
 readonly name = "osrm-compatible";
 private readonly baseUrl: URL;
 private readonly fetchImpl: typeof fetch;

 constructor(baseUrl: string, options: { fetchImpl?: typeof fetch; production?: boolean } = {}) {
  let parsed: URL;
  try { parsed = new URL(baseUrl); } catch { throw new Error("ROUTING_BASE_URL must be an absolute URL."); }
  if (!["http:", "https:"].includes(parsed.protocol)) throw new Error("ROUTING_BASE_URL must use HTTP or HTTPS.");
  if (options.production && parsed.protocol !== "https:") throw new Error("Production routing provider must use HTTPS.");
  this.baseUrl = parsed;
  this.fetchImpl = options.fetchImpl ?? fetch;
 }

 async getRoute(origin: CoordinateInput, destination: CoordinateInput): Promise<RoadRoute> {
  validateCoordinate(origin);
  validateCoordinate(destination);
  const url = new URL("route/v1/driving/" +
   origin.longitude + "," + origin.latitude + ";" +
   destination.longitude + "," + destination.latitude, this.baseUrl.toString().replace(/\/?$/, "/"));
  url.searchParams.set("overview", "full");
  url.searchParams.set("geometries", "geojson");
  url.searchParams.set("steps", "false");
  const response = await this.fetchImpl(url, { method: "GET", headers: { accept: "application/json" }, signal: AbortSignal.timeout(8000) });
  if (!response.ok) throw new Error("Routing provider failed with HTTP " + response.status);
  const parsed = responseSchema.parse(await response.json());
  const route = parsed.routes?.[0];
  if (parsed.code !== "Ok" || !route || route.distance <= 0 || route.duration <= 0) {
   throw new Error("Routing provider returned no valid road route.");
  }
  return {
   distanceMeters: Math.round(route.distance),
   durationSeconds: Math.ceil(route.duration),
   geometry: route.geometry.coordinates.map(([longitude, latitude]) => ({ latitude, longitude })),
   provider: this.name,
   calculatedAt: new Date().toISOString()
  };
 }
}
