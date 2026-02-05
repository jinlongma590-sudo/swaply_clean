import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function toInt(v: any): number {
  const n = Number(v);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}
function toBool(v: any): boolean {
  if (typeof v === "boolean") return v;
  const s = String(v ?? "").toLowerCase();
  return s === "true" || s === "1" || s === "yes";
}

async function readSpinLoopRule(supabase: any, campaignId: string) {
  const { data: ruleLoop } = await supabase
    .from("reward_rules")
    .select("trigger_n, payload")
    .eq("campaign_id", campaignId)
    .eq("trigger_type", "spin_grant_loop")
    .eq("is_enabled", true)
    .order("trigger_n", { ascending: true })
    .maybeSingle();

  if (!ruleLoop) return null;

  const startAt = toInt(ruleLoop.trigger_n ?? 0);
  const spinsEach = toInt(ruleLoop.payload?.spins ?? 1);
  const interval = toInt(ruleLoop.payload?.loop_interval ?? 10);

  if (!startAt || startAt < 1) return null;
  if (!interval || interval < 1) return null;

  return { startAt, interval, spinsEach };
}

function calcSpinLoopProgress(currentCount: number, rule: { startAt: number; interval: number }) {
  const startAt = rule.startAt;
  const interval = rule.interval;

  if (currentCount < startAt) {
    const remaining = startAt - currentCount;
    const nextAt = startAt;
    return { enabled: true, startAt, interval, nextAt, remaining };
  }

  const offset = (currentCount - startAt) % interval;
  if (offset === 0) {
    const nextAt = currentCount + interval;
    const remaining = interval;
    return { enabled: true, startAt, interval, nextAt, remaining };
  } else {
    const remaining = interval - offset;
    const nextAt = currentCount + remaining;
    return { enabled: true, startAt, interval, nextAt, remaining };
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!url || !serviceKey) throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");

    const supabase = createClient(url, serviceKey);

    // Auth
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) throw new Error("No authorization header");
    const token = authHeader.replace("Bearer ", "");

    const { data: userData, error: authError } = await supabase.auth.getUser(token);
    if (authError || !userData?.user) throw new Error("Authentication failed");
    const user = userData.user;

    const body = await req.json().catch(() => ({}));
    const campaign_code = (body.campaign_code as string) || "launch_v1";

    // Campaign
    const { data: campaign, error: campaignError } = await supabase
      .from("reward_campaigns")
      .select("id, code, is_enabled")
      .eq("code", campaign_code)
      .eq("is_enabled", true)
      .maybeSingle();

    if (campaignError || !campaign) {
      return new Response(JSON.stringify({ ok: false, error: "Campaign not found or disabled" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 404,
      });
    }

    // State
    const { data: st } = await supabase
      .from("user_reward_state")
      .select("qualified_listings_count, airtime_points, spins_balance")
      .eq("user_id", user.id)
      .eq("campaign_code", campaign.code)
      .maybeSingle();

    const qualified_count = toInt(st?.qualified_listings_count ?? 0);
    const airtime_points = toInt(st?.airtime_points ?? 0);
    const spins = toInt(st?.spins_balance ?? 0);

    // Pool
    const { data: poolRows } = await supabase
      .from("reward_pool_items")
      .select("id, title, item_type, payload, weight, sort_order")
      .eq("campaign_code", campaign.code)
      .eq("is_active", true)
      .order("sort_order", { ascending: true });

    const pool = (poolRows || []).map((x: any) => ({
      id: x.id,
      title: x.title,
      result_type: x.item_type,
      result_payload: x.payload || {},
      weight: x.weight || 0,
    }));

    // Loop rule + progress
    const loopRule = await readSpinLoopRule(supabase, campaign.id);
    const loop = loopRule ? calcSpinLoopProgress(qualified_count, loopRule) : { enabled: false };

    const progressText =
      loop.enabled === true
        ? qualified_count >= (loop as any).startAt
          ? `${(loop as any).remaining} more listing${(loop as any).remaining === 1 ? "" : "s"} until next spin (#${(loop as any).nextAt})`
          : `${(loop as any).startAt - qualified_count} more listing${((loop as any).startAt - qualified_count) === 1 ? "" : "s"} to unlock spin loop (starting at #${(loop as any).startAt})`
        : null;

    return new Response(
      JSON.stringify({
        ok: true,
        qualified_count,
        airtime_points,
        spins,
        pool,

        spin_loop_enabled: loop.enabled === true,
        spin_loop_start_at: (loop as any).startAt ?? null,
        spin_loop_interval: (loop as any).interval ?? null,
        spin_loop_next_at: (loop as any).nextAt ?? null,
        spin_loop_remaining: (loop as any).remaining ?? null,
        spin_loop_progress_text: progressText,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
    );
  } catch (err) {
    console.error("[RewardCenterState] Error:", err);
    return new Response(JSON.stringify({ ok: false, error: String((err as any)?.message ?? err) }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    });
  }
});