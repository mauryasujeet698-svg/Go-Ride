import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return mismatch === 0;
}

function asText(value: unknown, maxLength = 4000): string {
  return typeof value === "string" ? value.slice(0, maxLength) : "";
}

function parseNarrative(raw: string): { summary: string; findings: unknown[]; recommendations: unknown[] } {
  const trimmed = raw.trim().replace(/^\`\`\`(?:json)?\s*/i, "").replace(/\s*\`\`\`$/, "");
  try {
    const parsed = JSON.parse(trimmed);
    return {
      summary: asText(parsed?.summary, 6000),
      findings: Array.isArray(parsed?.findings) ? parsed.findings.slice(0, 25) : [],
      recommendations: Array.isArray(parsed?.recommendations) ? parsed.recommendations.slice(0, 25) : [],
    };
  } catch {
    return { summary: trimmed.slice(0, 6000), findings: [], recommendations: [] };
  }
}

async function callProvider(provider: string, model: string, apiKey: string, metrics: unknown) {
  const prompt = [
    "You are Go-Ride's operations analyst.",
    "Analyze only the aggregate metrics below. Do not invent numbers, infer personal identities, or claim an action was taken.",
    "Return valid JSON with keys: summary (string), findings (array of concise objects with severity/title/detail), recommendations (array of concise objects with priority/action/reason).",
    "Flag safety, security, financial, support-escalation, demand, and service reliability risks. Distinguish observations from hypotheses.",
    JSON.stringify(metrics),
  ].join("\n\n");

  let response: Response;
  let extract: (payload: any) => string;

  if (provider === "openai") {
    response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        messages: [
          { role: "system", content: "You produce careful, evidence-based operations reports as JSON." },
          { role: "user", content: prompt },
        ],
        response_format: { type: "json_object" },
        temperature: 0.2,
      }),
      signal: AbortSignal.timeout(30000),
    });
    extract = (payload) => payload?.choices?.[0]?.message?.content ?? "";
  } else if (provider === "gemini") {
    response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
        body: JSON.stringify({
          contents: [{ role: "user", parts: [{ text: prompt }] }],
          generationConfig: { responseMimeType: "application/json", temperature: 0.2 },
        }),
        signal: AbortSignal.timeout(30000),
      },
    );
    extract = (payload) => payload?.candidates?.[0]?.content?.parts?.map((p: any) => p.text ?? "").join("") ?? "";
  } else if (provider === "anthropic") {
    response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model,
        max_tokens: 1800,
        system: "You produce careful, evidence-based operations reports as JSON.",
        messages: [{ role: "user", content: prompt }],
      }),
      signal: AbortSignal.timeout(30000),
    });
    extract = (payload) => payload?.content?.map((p: any) => p.text ?? "").join("") ?? "";
  } else {
    throw new Error("provider_not_configured");
  }

  if (!response.ok) throw new Error("provider_request_failed");
  const payload = await response.json();
  const text = extract(payload);
  if (!text.trim()) throw new Error("provider_empty_response");
  return parseNarrative(text);
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const expectedSecret = Deno.env.get("AI_CRON_SECRET") ?? "";
  const suppliedSecret = req.headers.get("x-cron-secret") ?? "";
  if (!expectedSecret || !suppliedSecret || !constantTimeEqual(expectedSecret, suppliedSecret)) {
    return json({ error: "unauthorized" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return json({ error: "server_configuration_missing" }, 503);

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const now = new Date();

  const { data: settings, error: settingsError } = await admin
    .from("ai_runtime_settings")
    .select("provider, model, enabled, daily_report_enabled, report_interval_hours")
    .eq("singleton", true)
    .maybeSingle();

  if (settingsError || !settings) return json({ error: "ai_settings_unavailable" }, 503);

  if (!settings.enabled || !settings.daily_report_enabled) {
    await admin.from("ai_job_runs").insert({
      job_type: "daily_report",
      status: "skipped",
      started_at: now.toISOString(),
      finished_at: now.toISOString(),
      input_summary: { reason: "daily_reporting_disabled" },
      output_summary: {},
      provider: settings.provider ?? "none",
      model: settings.model ?? null,
    });
    return json({ status: "skipped", reason: "daily_reporting_disabled" });
  }

  const { data: previous } = await admin
    .from("daily_ai_reports")
    .select("period_end")
    .eq("status", "succeeded")
    .order("period_end", { ascending: false })
    .limit(1)
    .maybeSingle();

  const intervalHours = Math.max(1, Math.min(168, Number(settings.report_interval_hours) || 24));
  const previousEnd = previous?.period_end ? new Date(previous.period_end) : null;
  if (previousEnd && now.getTime() - previousEnd.getTime() < (intervalHours - 0.1) * 3600000) {
    return json({ status: "skipped", reason: "report_interval_not_reached" });
  }

  const periodEnd = now;
  const periodStart = previousEnd && previousEnd < periodEnd
    ? previousEnd
    : new Date(periodEnd.getTime() - 24 * 3600000);

  const { data: job, error: jobError } = await admin
    .from("ai_job_runs")
    .insert({
      job_type: "daily_report",
      status: "running",
      started_at: now.toISOString(),
      input_summary: { period_start: periodStart.toISOString(), period_end: periodEnd.toISOString() },
      provider: settings.provider ?? "none",
      model: settings.model ?? null,
    })
    .select("id")
    .single();

  if (jobError || !job) return json({ error: "job_record_failed" }, 503);

  const metricsResult = await admin.rpc("get_ai_daily_metrics", {
    p_period_start: periodStart.toISOString(),
    p_period_end: periodEnd.toISOString(),
  });

  if (metricsResult.error) {
    await admin.from("ai_job_runs").update({
      status: "failed",
      finished_at: new Date().toISOString(),
      error_code: "metrics_query_failed",
    }).eq("id", job.id);
    return json({ error: "metrics_query_failed" }, 503);
  }

  let narrative = {
    summary: "Validated operational metrics collected. AI narrative analysis is not configured.",
    findings: [] as unknown[],
    recommendations: [] as unknown[],
  };
  let provider = settings.provider ?? "none";
  let model = settings.model ?? null;
  let usageId: string | null = null;

  try {
    if (provider !== "none") {
      if (!model) throw new Error("provider_model_missing");
      const keyName = provider === "openai" ? "OPENAI_API_KEY"
        : provider === "gemini" ? "GEMINI_API_KEY" : "ANTHROPIC_API_KEY";
      const apiKey = Deno.env.get(keyName) ?? "";
      if (!apiKey) throw new Error("provider_key_missing");
      const reservation = await admin.rpc("reserve_ai_usage_budget", {
        p_job_type: "daily_report",
        p_provider: provider,
        p_model: model,
      });
      if (reservation.error || !reservation.data) {
        const message = reservation.error?.message ?? "";
        if (message.includes("ai_request_budget_exceeded")) throw new Error("ai_request_budget_exceeded");
        if (message.includes("ai_cost_budget_exceeded")) throw new Error("ai_cost_budget_exceeded");
        throw new Error("ai_budget_reservation_failed");
      }
      usageId = String(reservation.data);
      narrative = await callProvider(provider, model, apiKey, metricsResult.data);
      await admin.from("ai_usage_events").update({
        status: "succeeded",
        completed_at: new Date().toISOString(),
      }).eq("id", usageId);
    }
  } catch (error) {
    const rawCode = error instanceof Error ? error.message : "";
    const allowedCodes = [
      "provider_model_missing", "provider_key_missing", "provider_request_failed",
      "provider_empty_response", "ai_request_budget_exceeded", "ai_cost_budget_exceeded",
      "ai_budget_reservation_failed",
    ];
    const errorCode = allowedCodes.includes(rawCode) ? rawCode : "ai_analysis_failed";
    if (usageId) {
      await admin.from("ai_usage_events").update({
        status: "failed",
        error_code: errorCode,
        completed_at: new Date().toISOString(),
      }).eq("id", usageId);
    }
    await admin.from("daily_ai_reports").upsert({
      period_start: periodStart.toISOString(),
      period_end: periodEnd.toISOString(),
      timezone: "Asia/Kolkata",
      status: "failed",
      metrics: metricsResult.data,
      summary: "Metrics were collected, but AI analysis failed. Review the provider configuration and job log.",
      findings: [],
      recommendations: [],
      provider,
      model,
      error_code: errorCode.slice(0, 120),
    }, { onConflict: "period_start,period_end" });
    await admin.from("ai_job_runs").update({
      status: "failed",
      finished_at: new Date().toISOString(),
      output_summary: { metrics_collected: true },
      error_code: errorCode.slice(0, 120),
    }).eq("id", job.id);
    return json({ error: "ai_analysis_failed", code: errorCode.slice(0, 120) }, 502);
  }

  const completedAt = new Date().toISOString();
  const { error: reportError } = await admin.from("daily_ai_reports").upsert({
    period_start: periodStart.toISOString(),
    period_end: periodEnd.toISOString(),
    timezone: "Asia/Kolkata",
    status: "succeeded",
    metrics: metricsResult.data,
    summary: narrative.summary,
    findings: narrative.findings,
    recommendations: narrative.recommendations,
    provider,
    model,
    error_code: null,
    completed_at: completedAt,
  }, { onConflict: "period_start,period_end" });

  if (reportError) {
    await admin.from("ai_job_runs").update({
      status: "failed",
      finished_at: completedAt,
      error_code: "report_persist_failed",
    }).eq("id", job.id);
    return json({ error: "report_persist_failed" }, 503);
  }

  await admin.from("audit_events").insert({
    actor_type: "system",
    action: "ai.daily_report_generated",
    entity_type: "daily_ai_report",
    entity_id: periodEnd.toISOString(),
    outcome: "success",
    metadata: {
      period_start: periodStart.toISOString(),
      period_end: periodEnd.toISOString(),
      provider,
      findings_count: narrative.findings.length,
      recommendations_count: narrative.recommendations.length,
    },
  });

  await admin.from("ai_job_runs").update({
    status: "succeeded",
    finished_at: completedAt,
    output_summary: {
      report_saved: true,
      findings_count: narrative.findings.length,
      recommendations_count: narrative.recommendations.length,
    },
  }).eq("id", job.id);

  return json({ status: "succeeded", period_start: periodStart.toISOString(), period_end: periodEnd.toISOString() });
});
