import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
});

function sameSecret(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return mismatch === 0;
}

function deterministicFindings(metrics: any): Array<{severity: string; title: string; detail: string}> {
  const findings: Array<{severity: string; title: string; detail: string}> = [];
  const noRls = Array.isArray(metrics?.public_tables_without_rls) ? metrics.public_tables_without_rls : [];
  const anonFunctions = Array.isArray(metrics?.security_definer_functions_executable_by_anon)
    ? metrics.security_definer_functions_executable_by_anon : [];
  if (noRls.length) findings.push({severity: "high", title: "Public tables without RLS", detail: noRls.join(", ")});
  if (anonFunctions.length) findings.push({severity: "high", title: "Security-definer functions callable by anon", detail: JSON.stringify(anonFunctions)});
  if (Number(metrics?.rides_searching_over_10_minutes ?? 0) > 0) findings.push({
    severity: "medium", title: "Rides stuck searching", detail: String(metrics.rides_searching_over_10_minutes) + " ride(s) have been searching for over 10 minutes.",
  });
  if (Number(metrics?.active_subscriptions_past_expiry ?? 0) > 0) findings.push({
    severity: "medium", title: "Expired subscriptions still marked active", detail: String(metrics.active_subscriptions_past_expiry) + " subscription(s) need reconciliation.",
  });
  if (Number(metrics?.urgent_unresolved_support_tickets ?? 0) > 0) findings.push({
    severity: "high", title: "Urgent support tickets unresolved", detail: String(metrics.urgent_unresolved_support_tickets) + " urgent ticket(s) remain unresolved.",
  });
  if (Number(metrics?.denied_or_failed_audit_events ?? 0) > 0) findings.push({
    severity: "medium", title: "Denied, failed or flagged events", detail: String(metrics.denied_or_failed_audit_events) + " audit event(s) in the period need review.",
  });
  if (Number(metrics?.failed_ai_jobs ?? 0) > 0) findings.push({
    severity: "medium", title: "AI jobs failed", detail: String(metrics.failed_ai_jobs) + " AI job(s) failed in the period.",
  });
  if (Number(metrics?.active_areas_without_coverage ?? 0) > 0) findings.push({
    severity: "high", title: "Service area missing coverage", detail: String(metrics.active_areas_without_coverage) + " active area(s) have no valid coverage centre/radius.",
  });
  return findings;
}

async function aiNarrative(provider: string, model: string, key: string, metrics: unknown, findings: unknown) {
  const prompt = [
    "Analyze this Go-Ride security and operations audit. The input contains aggregate checks, not complete logs.",
    "Do not claim that you ran tests or changed configuration. Do not invent facts. Prioritize exploitable risks and operational failures.",
    "Return JSON with keys summary (string), findings (array of objects with severity/title/detail), recommendations (array of objects with priority/action/reason).",
    JSON.stringify({metrics, deterministic_findings: findings}),
  ].join("\n\n");
  let response: Response;
  let extract: (payload: any) => string;
  if (provider === "openai") {
    response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {"Authorization": "Bearer " + key, "Content-Type": "application/json"},
      body: JSON.stringify({model, messages: [
        {role: "system", content: "You are a cautious security auditor. You only analyze evidence and recommend actions; you do not execute actions."},
        {role: "user", content: prompt},
      ], response_format: {type: "json_object"}, temperature: 0.1}),
      signal: AbortSignal.timeout(25000),
    });
    extract = p => p?.choices?.[0]?.message?.content ?? "";
  } else if (provider === "gemini") {
    response = await fetch("https://generativelanguage.googleapis.com/v1beta/models/" + encodeURIComponent(model) + ":generateContent?key=" + encodeURIComponent(key), {
      method: "POST",
      headers: {"Content-Type": "application/json", "x-goog-api-key": key},
      body: JSON.stringify({contents: [{role: "user", parts: [{text: prompt}]}], generationConfig: {responseMimeType: "application/json", temperature: 0.1}}),
      signal: AbortSignal.timeout(25000),
    });
    extract = p => p?.candidates?.[0]?.content?.parts?.map((x: any) => x.text ?? "").join("") ?? "";
  } else if (provider === "anthropic") {
    response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {"x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json"},
      body: JSON.stringify({model, max_tokens: 1800, system: "You are a cautious security auditor. Return evidence-based JSON only.", messages: [{role: "user", content: prompt}]}),
      signal: AbortSignal.timeout(25000),
    });
    extract = p => p?.content?.map((x: any) => x.text ?? "").join("") ?? "";
  } else {
    throw new Error("provider_not_configured");
  }
  if (!response.ok) throw new Error("provider_request_failed");
  const payload = await response.json();
  const raw = extract(payload).trim().replace(/^\`\`\`(?:json)?\s*/i, "").replace(/\s*\`\`\`$/, "");
  if (!raw) throw new Error("provider_empty_response");
  try {
    const parsed = JSON.parse(raw);
    return {
      summary: typeof parsed.summary === "string" ? parsed.summary.slice(0, 6000) : "",
      findings: Array.isArray(parsed.findings) ? parsed.findings.slice(0, 25) : [],
      recommendations: Array.isArray(parsed.recommendations) ? parsed.recommendations.slice(0, 25) : [],
    };
  } catch {
    throw new Error("provider_invalid_json");
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({error: "method_not_allowed"}, 405);
  const expected = Deno.env.get("AI_CRON_SECRET") ?? "";
  const supplied = req.headers.get("x-cron-secret") ?? "";
  if (!sameSecret(expected, supplied)) return json({error: "unauthorized"}, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return json({error: "server_configuration_missing"}, 503);
  const db = createClient(url, serviceKey, {auth: {persistSession: false, autoRefreshToken: false}});
  const now = new Date();
  const periodStart = new Date(now.getTime() - 24 * 3600000);

  const {data: settings, error: settingsError} = await db.from("ai_runtime_settings")
    .select("provider,model,enabled").eq("singleton", true).maybeSingle();
  if (settingsError || !settings) return json({error: "ai_settings_unavailable"}, 503);

  const {data: job, error: jobError} = await db.from("ai_job_runs").insert({
    job_type: "security_audit",
    status: "running",
    started_at: now.toISOString(),
    input_summary: {period_start: periodStart.toISOString(), period_end: now.toISOString()},
    provider: settings.enabled ? settings.provider : "none",
    model: settings.enabled ? settings.model : null,
  }).select("id").single();
  if (jobError || !job) return json({error: "job_record_failed"}, 503);

  const metricsResult = await db.rpc("get_ai_security_metrics", {
    p_period_start: periodStart.toISOString(),
    p_period_end: now.toISOString(),
  });
  if (metricsResult.error) {
    await db.from("ai_job_runs").update({status: "failed", finished_at: new Date().toISOString(), error_code: "security_metrics_failed"}).eq("id", job.id);
    return json({error: "security_metrics_failed"}, 503);
  }

  const findings = deterministicFindings(metricsResult.data);
  let provider = settings.enabled ? String(settings.provider ?? "none") : "none";
  let model = settings.enabled && settings.model ? String(settings.model) : null;
  let summary = findings.length
    ? "Deterministic security checks found " + findings.length + " item(s) for review."
    : "No issues were detected by the configured deterministic checks in this period. This is not a guarantee that the system is vulnerability-free.";
  let recommendations: unknown[] = [];
  let aiStatus = "not_configured";
  let usageId: string | null = null;
  let errorCode: string | null = null;

  try {
    if (provider !== "none" && model) {
      const keyName = provider === "openai" ? "OPENAI_API_KEY" : provider === "gemini" ? "GEMINI_API_KEY" : "ANTHROPIC_API_KEY";
      const key = Deno.env.get(keyName) ?? "";
      if (!key) throw new Error("provider_key_missing");
      const reservation = await db.rpc("reserve_ai_usage_budget", {p_job_type: "security_audit", p_provider: provider, p_model: model});
      if (reservation.error || !reservation.data) {
        const message = reservation.error?.message ?? "";
        if (message.includes("ai_request_budget_exceeded")) throw new Error("ai_request_budget_exceeded");
        if (message.includes("ai_cost_budget_exceeded")) throw new Error("ai_cost_budget_exceeded");
        throw new Error("ai_budget_reservation_failed");
      }
      usageId = String(reservation.data);
      const narrative = await aiNarrative(provider, model, key, metricsResult.data, findings);
      summary = narrative.summary || summary;
      recommendations = narrative.recommendations;
      aiStatus = "succeeded";
      await db.from("ai_usage_events").update({status: "succeeded", completed_at: new Date().toISOString()}).eq("id", usageId);
    }
  } catch (error) {
    const raw = error instanceof Error ? error.message : "";
    const allowed = ["provider_key_missing","provider_request_failed","provider_empty_response","provider_invalid_json","ai_request_budget_exceeded","ai_cost_budget_exceeded","ai_budget_reservation_failed"];
    errorCode = allowed.includes(raw) ? raw : "ai_analysis_failed";
    aiStatus = "failed";
    if (usageId) await db.from("ai_usage_events").update({status: "failed", error_code: errorCode, completed_at: new Date().toISOString()}).eq("id", usageId);
    summary += " AI narrative analysis was unavailable; deterministic findings are still recorded.";
  }

  const outcome = findings.some((x) => x.severity === "high") ? "flagged" : "success";
  await db.from("ai_job_runs").update({
    status: "succeeded",
    finished_at: new Date().toISOString(),
    output_summary: {
      period_start: periodStart.toISOString(),
      period_end: now.toISOString(),
      metrics: metricsResult.data,
      summary,
      findings,
      recommendations,
      ai_analysis_status: aiStatus,
      error_code: errorCode,
    },
    error_code: null,
  }).eq("id", job.id);

  await db.from("audit_events").insert({
    actor_type: "ai_agent",
    action: "ai.security_audit_completed",
    entity_type: "ai_job_run",
    entity_id: String(job.id),
    outcome,
    metadata: {finding_count: findings.length, ai_analysis_status: aiStatus, error_code: errorCode},
  });

  return json({status: "succeeded", job_id: job.id, finding_count: findings.length, ai_analysis_status: aiStatus});
});
