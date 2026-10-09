import type { RoadRoute } from "./provider.js";

export type FarePolicy = {
 baseFareMinor: number;
 perKilometerMinor: number;
 perMinuteMinor: number;
 minimumFareMinor: number;
 version: string;
 currency: string;
};

export function calculateFare(route: Pick<RoadRoute, "distanceMeters" | "durationSeconds">, policy: FarePolicy): number {
 for (const [name, value] of Object.entries({
  baseFareMinor: policy.baseFareMinor,
  perKilometerMinor: policy.perKilometerMinor,
  perMinuteMinor: policy.perMinuteMinor,
  minimumFareMinor: policy.minimumFareMinor
 })) {
  if (!Number.isSafeInteger(value) || value < 0) throw new Error(name + " must be a non-negative integer.");
 }
 if (!Number.isSafeInteger(route.distanceMeters) || route.distanceMeters <= 0 ||
     !Number.isSafeInteger(route.durationSeconds) || route.durationSeconds <= 0) {
  throw new Error("A valid road distance and duration are required to quote a fare.");
 }
 if (!/^[A-Z]{3}$/.test(policy.currency) || !policy.version.trim()) throw new Error("A valid currency and pricing policy version are required.");
 const distanceCharge = Math.ceil(route.distanceMeters / 1000 * policy.perKilometerMinor);
 const timeCharge = Math.ceil(route.durationSeconds / 60 * policy.perMinuteMinor);
 const total = Math.max(policy.minimumFareMinor, policy.baseFareMinor + distanceCharge + timeCharge);
 if (!Number.isSafeInteger(total) || total <= 0) throw new Error("Calculated fare is outside the supported range.");
 return total;
}

export function loadFarePolicy(env: NodeJS.ProcessEnv = process.env): FarePolicy {
 const readInteger = (key: string, fallback: number): number => {
  const raw = env[key];
  if (raw === undefined || raw.trim() === "") return fallback;
  if (!/^\d+$/.test(raw.trim())) throw new Error(key + " must be a non-negative integer.");
  const value = Number(raw);
  if (!Number.isSafeInteger(value)) throw new Error(key + " is outside the supported range.");
  return value;
 };
 return {
  baseFareMinor: readInteger("FARE_BASE_MINOR", 3000),
  perKilometerMinor: readInteger("FARE_PER_KM_MINOR", 1200),
  perMinuteMinor: readInteger("FARE_PER_MINUTE_MINOR", 200),
  minimumFareMinor: readInteger("FARE_MINIMUM_MINOR", 5000),
  version: env.FARE_POLICY_VERSION?.trim() || "launch-v1",
  currency: env.FARE_CURRENCY?.trim().toUpperCase() || "INR"
 };
}
