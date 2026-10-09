import { z } from "zod";

const booleanFromEnv = z.enum(["true", "false"]).transform((v) => v === "true");

const envSchema = z.object({
  FEATURE_PAYMENTS_ENABLED: booleanFromEnv.default("false"),
  FEATURE_PAYMENTS_MODE: z.enum(["disabled", "test", "live"]).default("disabled"),
  FEATURE_PAYMENT_UPI_ENABLED: booleanFromEnv.default("false"),
  FEATURE_PAYMENT_CARDS_ENABLED: booleanFromEnv.default("false"),
  FEATURE_PAYMENT_NETBANKING_ENABLED: booleanFromEnv.default("false"),
  FEATURE_PAYMENT_CASH_ENABLED: booleanFromEnv.default("false"),
  FEATURE_MAP_SEARCH_ENABLED: booleanFromEnv.default("false"),
  FEATURE_ROUTING_ENABLED: booleanFromEnv.default("false"),
  FEATURE_DRIVER_DISPATCH_ENABLED: booleanFromEnv.default("false"),
  FEATURE_CUSTOMER_SUPPORT_ENABLED: booleanFromEnv.default("false"),
  FEATURE_DRIVER_SUPPORT_ENABLED: booleanFromEnv.default("false"),
  FEATURE_SAFETY_SOS_ENABLED: booleanFromEnv.default("false")
});

export type FeatureConfig = {
  payments: {
    enabled: boolean;
    mode: "disabled" | "test" | "live";
    methods: { upi: boolean; cards: boolean; netbanking: boolean; cash: boolean };
  };
  maps: { search: boolean; routing: boolean };
  dispatch: { enabled: boolean };
  support: { customer: boolean; driver: boolean };
  safety: { sos: boolean };
};

export function loadFeatureConfig(env: NodeJS.ProcessEnv = process.env): FeatureConfig {
  const parsed = envSchema.parse({
    FEATURE_PAYMENTS_ENABLED: env.FEATURE_PAYMENTS_ENABLED ?? "false",
    FEATURE_PAYMENTS_MODE: env.FEATURE_PAYMENTS_MODE ?? "disabled",
    FEATURE_PAYMENT_UPI_ENABLED: env.FEATURE_PAYMENT_UPI_ENABLED ?? "false",
    FEATURE_PAYMENT_CARDS_ENABLED: env.FEATURE_PAYMENT_CARDS_ENABLED ?? "false",
    FEATURE_PAYMENT_NETBANKING_ENABLED: env.FEATURE_PAYMENT_NETBANKING_ENABLED ?? "false",
    FEATURE_PAYMENT_CASH_ENABLED: env.FEATURE_PAYMENT_CASH_ENABLED ?? "false",
    FEATURE_MAP_SEARCH_ENABLED: env.FEATURE_MAP_SEARCH_ENABLED ?? "false",
    FEATURE_ROUTING_ENABLED: env.FEATURE_ROUTING_ENABLED ?? "false",
    FEATURE_DRIVER_DISPATCH_ENABLED: env.FEATURE_DRIVER_DISPATCH_ENABLED ?? "false",
    FEATURE_CUSTOMER_SUPPORT_ENABLED: env.FEATURE_CUSTOMER_SUPPORT_ENABLED ?? "false",
    FEATURE_DRIVER_SUPPORT_ENABLED: env.FEATURE_DRIVER_SUPPORT_ENABLED ?? "false",
    FEATURE_SAFETY_SOS_ENABLED: env.FEATURE_SAFETY_SOS_ENABLED ?? "false"
  });

  const liveMethodsRequested = parsed.FEATURE_PAYMENT_UPI_ENABLED ||
    parsed.FEATURE_PAYMENT_CARDS_ENABLED || parsed.FEATURE_PAYMENT_NETBANKING_ENABLED;
  if (parsed.FEATURE_PAYMENTS_MODE === "disabled" &&
      (parsed.FEATURE_PAYMENTS_ENABLED || liveMethodsRequested || parsed.FEATURE_PAYMENT_CASH_ENABLED)) {
    throw new Error("Payment methods cannot be enabled while payments.mode is disabled.");
  }
  if (parsed.FEATURE_PAYMENTS_MODE === "live" && !parsed.FEATURE_PAYMENTS_ENABLED) {
    throw new Error("Live payment mode requires FEATURE_PAYMENTS_ENABLED=true.");
  }

  return {
    payments: {
      enabled: parsed.FEATURE_PAYMENTS_ENABLED && parsed.FEATURE_PAYMENTS_MODE !== "disabled",
      mode: parsed.FEATURE_PAYMENTS_MODE,
      methods: {
        upi: parsed.FEATURE_PAYMENT_UPI_ENABLED,
        cards: parsed.FEATURE_PAYMENT_CARDS_ENABLED,
        netbanking: parsed.FEATURE_PAYMENT_NETBANKING_ENABLED,
        cash: parsed.FEATURE_PAYMENT_CASH_ENABLED
      }
    },
    maps: { search: parsed.FEATURE_MAP_SEARCH_ENABLED, routing: parsed.FEATURE_ROUTING_ENABLED },
    dispatch: { enabled: parsed.FEATURE_DRIVER_DISPATCH_ENABLED },
    support: { customer: parsed.FEATURE_CUSTOMER_SUPPORT_ENABLED, driver: parsed.FEATURE_DRIVER_SUPPORT_ENABLED },
    safety: { sos: parsed.FEATURE_SAFETY_SOS_ENABLED }
  };
}
