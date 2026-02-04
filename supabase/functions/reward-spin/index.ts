import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type PoolRow = {
  id: string;
  title: string;
  item_type: "none" | "airtime_points" | "boost_coupon";
  payload: any;
  weight: number;
};

function pickWeighted<T extends { weight: number }>(items: T[]): T {
  const total = items.reduce((s, it) => s + (it.weight || 0), 0);
  if (total <= 0) throw new Error("Invalid pool weights");
  const r = Math.floor(Math.random() * total) + 1;
  let acc = 0;
  for (const it of items) {
    acc += it.weight || 0;
    if (r <= acc) return it;
  }
  return items[items.length - 1];
}

// 兼容你现有 coupons.type：category / featured
function mapScopeToType(scope: "category" | "search" | "trending"): string {
  if (scope === "category") return "category";
  return "featured"; // search / trending
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
  );

  try {
    // Auth
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) throw new Error("No authorization header");
    const token = authHeader.replace("Bearer ", "");

    const { data: userData, error: authError } = await supabase.auth.getUser(token);
    if (authError || !userData?.user) throw new Error("Authentication failed");
    const user = userData.user;

    // Body
    const body = await req.json().catch(() => ({}));
    const campaign_code = (body.campaign_code as string) || "launch_v1";
    const request_id = (body.request_id as string) || "";
    const listing_id = body.listing_id as string | undefined;
    const device_id = body.device_id as string | undefined;

    if (!request_id.trim()) {
      return new Response(JSON.stringify({ ok: false, error: "request_id is required" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    // Campaign check
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

    // ------------------------------------------------------------
    // ✅ Step 1: Reservation（先占位幂等记录，避免并发同 request_id 双扣/双发）
    // 说明：这里假设 reward_spin_requests 的 result_type / result_payload 允许为 null。
    // 如果你表上设置了 NOT NULL，请把 null 改成 "pending" 并放开 CHECK（如有）。
    // ------------------------------------------------------------
    const reservation = {
      user_id: user.id,
      campaign_code: campaign.code,
      request_id,
      listing_id: listing_id || null,
      device_id: device_id || null,
      result_type: null,
      result_payload: null,
      error: null,
    };

    const { error: insReqErr } = await supabase.from("reward_spin_requests").insert(reservation);

    if (insReqErr) {
      // unique violation => 已有同 request_id 记录，直接读返回（幂等）
      if ((insReqErr as any).code === "23505") {
        const { data: existed } = await supabase
          .from("reward_spin_requests")
          .select("result_type, result_payload, error")
          .eq("user_id", user.id)
          .eq("campaign_code", campaign.code)
          .eq("request_id", request_id)
          .maybeSingle();

        const { data: st } = await supabase
          .from("user_reward_state")
          .select("spins_balance, airtime_points, qualified_listings_count")
          .eq("user_id", user.id)
          .eq("campaign_code", campaign.code)
          .maybeSingle();

        const reward =
          existed?.result_type
            ? (existed.result_payload
                ? { ...(existed.result_payload as any), result_type: existed.result_type }
                : { result_type: existed.result_type })
            : null;

        return new Response(
          JSON.stringify({
            ok: true,
            idempotent: true,
            spins_left: st?.spins_balance ?? 0,
            airtime_points: st?.airtime_points ?? 0,
            qualified_count: st?.qualified_listings_count ?? 0,
            reward,
            error: existed?.error ?? null,
          }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
        );
      }

      throw new Error(`Failed to create spin request: ${insReqErr.message}`);
    }

    // ------------------------------------------------------------
    // ✅ Step 2: Read state (need spins)
    // ------------------------------------------------------------
    const { data: state, error: stErr } = await supabase
      .from("user_reward_state")
      .select("spins_balance, qualified_listings_count, airtime_points")
      .eq("user_id", user.id)
      .eq("campaign_code", campaign.code)
      .maybeSingle();

    if (stErr) throw new Error(`Failed to read user state: ${stErr.message}`);

    const spins = Number(state?.spins_balance ?? 0);
    if (spins <= 0) {
      // update request as finished(no_spins)
      await supabase
        .from("reward_spin_requests")
        .update({ result_type: "none", result_payload: { result_type: "none", reason: "no_spins" } })
        .eq("user_id", user.id)
        .eq("campaign_code", campaign.code)
        .eq("request_id", request_id);

      return new Response(JSON.stringify({ ok: false, reason: "no_spins", spins_left: 0 }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      });
    }

    // ------------------------------------------------------------
    // ✅ Step 3: CAS decrement spins_balance (防并发扣多次)
    // ------------------------------------------------------------
    const { data: st2, error: decErr } = await supabase
      .from("user_reward_state")
      .update({ spins_balance: spins - 1 })
      .eq("user_id", user.id)
      .eq("campaign_code", campaign.code)
      .eq("spins_balance", spins)
      .select("spins_balance, qualified_listings_count, airtime_points")
      .maybeSingle();

    if (decErr || !st2) {
      const { data: st } = await supabase
        .from("user_reward_state")
        .select("spins_balance")
        .eq("user_id", user.id)
        .eq("campaign_code", campaign.code)
        .maybeSingle();

      await supabase
        .from("reward_spin_requests")
        .update({ result_type: "none", result_payload: { result_type: "none", reason: "spin_race" }, error: "spin_race" })
        .eq("user_id", user.id)
        .eq("campaign_code", campaign.code)
        .eq("request_id", request_id);

      return new Response(JSON.stringify({ ok: false, reason: "spin_race", spins_left: st?.spins_balance ?? 0 }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 409,
      });
    }

    // ------------------------------------------------------------
    // ✅ Step 4: Load pool
    // ------------------------------------------------------------
    const { data: poolRows, error: poolErr } = await supabase
      .from("reward_pool_items")
      .select("id, title, item_type, payload, weight")
      .eq("campaign_code", campaign.code)
      .eq("is_active", true)
      .order("sort_order", { ascending: true });

    if (poolErr) {
      // refund spin
      await supabase
        .from("user_reward_state")
        .update({ spins_balance: Number(st2.spins_balance ?? 0) + 1 })
        .eq("user_id", user.id)
        .eq("campaign_code", campaign.code);

      await supabase
        .from("reward_spin_requests")
        .update({ result_type: "none", result_payload: { result_type: "none", reason: "pool_error" }, error: poolErr.message })
        .eq("user_id", user.id)
        .eq("campaign_code", campaign.code)
        .eq("request_id", request_id);

      throw new Error(`Failed to load pool: ${poolErr.message}`);
    }

    const pool = (poolRows || []) as PoolRow[];
    if (!pool.length) {
      await supabase
        .from("user_reward_state")
        .update({ spins_balance: Number(st2.spins_balance ?? 0) + 1 })
        .eq("user_id", user.id)
        .eq("campaign_code", campaign.code);

      await supabase
        .from("reward_spin_requests")
        .update({ result_type: "none", result_payload: { result_type: "none", reason: "no_pool" }, error: "No pool configured" })
        .eq("user_id", user.id)
        .eq("campaign_code", campaign.code)
        .eq("request_id", request_id);

      throw new Error("No pool configured");
    }

    const selected = pickWeighted(pool);

    // ------------------------------------------------------------
    // ✅ Step 5: Issue reward
    // 注意：这里不再写 reward_entries（会撞 UNIQUE trigger_n）
    // spin 的审计记录全部落在 reward_spin_requests 即可
    // ------------------------------------------------------------
    let rewardType: string = selected.item_type;
    let rewardPayload: any = null;

    let latestPoints = Number(st2.airtime_points ?? 0);

    if (selected.item_type === "airtime_points") {
      const pts = Number(selected.payload?.points ?? 0);

      if (pts > 0) {
        const { data: newPoints, error: ptsErr } = await supabase.rpc("reward_add_points", {
          p_user: user.id,
          p_points: pts,
          p_campaign: campaign.code,
        });

        if (ptsErr) {
          // refund spin
          await supabase
            .from("user_reward_state")
            .update({ spins_balance: Number(st2.spins_balance ?? 0) + 1 })
            .eq("user_id", user.id)
            .eq("campaign_code", campaign.code);

          await supabase
            .from("reward_spin_requests")
            .update({
              result_type: "none",
              result_payload: { result_type: "none", reason: "points_error" },
              error: ptsErr.message,
            })
            .eq("user_id", user.id)
            .eq("campaign_code", campaign.code)
            .eq("request_id", request_id);

          throw new Error(`Failed to add points: ${ptsErr.message}`);
        }

        latestPoints = Number(newPoints ?? latestPoints);
        rewardPayload = { result_type: "airtime_points", points: pts, new_points: newPoints, reason: "spin" };
      } else {
        rewardType = "none";
        rewardPayload = { result_type: "none" };
      }
    } else if (selected.item_type === "boost_coupon") {
      const scope = (selected.payload?.coupon_type || "category") as "category" | "search" | "trending";
      const pinDays = Number(selected.payload?.pin_days ?? 3);

      const couponType = mapScopeToType(scope);
      const scopeNames: Record<string, string> = { category: "Category", search: "Search", trending: "Trending" };

      const title = `${pinDays}-Day ${scopeNames[scope]} Boost`;
      const desc = `Spin reward`;

      const { data: couponId, error: cErr } = await supabase.rpc("_coupon_insert_v2", {
        p_user: user.id,
        p_source: "spin_reward",
        p_type: couponType,
        p_title: title,
        p_desc: desc,
        p_code_prefix: "RWD",
        p_valid_days: 30,
        p_metadata: {
          source: "spin_reward",
          request_id,
          listing_id,
          device_id,
          campaign_code: campaign.code,
          pool_item_id: selected.id,
          pin_scope: scope,
          pin_days: pinDays,
        },
      });

      if (cErr) {
        // refund spin
        await supabase
          .from("user_reward_state")
          .update({ spins_balance: Number(st2.spins_balance ?? 0) + 1 })
          .eq("user_id", user.id)
          .eq("campaign_code", campaign.code);

        await supabase
          .from("reward_spin_requests")
          .update({
            result_type: "none",
            result_payload: { result_type: "none", reason: "coupon_error" },
            error: cErr.message,
          })
          .eq("user_id", user.id)
          .eq("campaign_code", campaign.code)
          .eq("request_id", request_id);

        throw new Error(`Failed to issue coupon: ${cErr.message}`);
      }

      if (!couponId || typeof couponId !== "string") {
        await supabase
          .from("user_reward_state")
          .update({ spins_balance: Number(st2.spins_balance ?? 0) + 1 })
          .eq("user_id", user.id)
          .eq("campaign_code", campaign.code);

        await supabase
          .from("reward_spin_requests")
          .update({
            result_type: "none",
            result_payload: { result_type: "none", reason: "coupon_missing" },
            error: "Coupon ID not returned",
          })
          .eq("user_id", user.id)
          .eq("campaign_code", campaign.code)
          .eq("request_id", request_id);

        throw new Error("Coupon ID not returned");
      }

      // 兼容 publish 的 coupons 更新逻辑
      const { error: updErr } = await supabase
        .from("coupons")
        .update({
          pin_scope: scope,
          pin_days: pinDays,
          duration_days: pinDays,
          updated_at: new Date().toISOString(),
        })
        .eq("id", couponId);

      if (updErr) console.error(`[Spin] Failed to update coupon scope: ${updErr.message}`);

      rewardPayload = { result_type: "boost_coupon", coupon_id: couponId, pin_scope: scope, pin_days: pinDays };
    } else {
      rewardType = "none";
      rewardPayload = { result_type: "none" };
    }

    // ------------------------------------------------------------
    // ✅ Step 6: Finalize request record (幂等落库)
    // ------------------------------------------------------------
    const { error: finalizeErr } = await supabase
      .from("reward_spin_requests")
      .update({
        result_type: rewardType,
        result_payload: rewardPayload,
        error: null,
      })
      .eq("user_id", user.id)
      .eq("campaign_code", campaign.code)
      .eq("request_id", request_id);

    if (finalizeErr) {
      // 这里不能 refund，因为奖励已经发出（points/coupon）。只记录错误。
      console.error(`[Spin] Failed to finalize spin request: ${finalizeErr.message}`);
    }

    return new Response(
      JSON.stringify({
        ok: true,
        spins_left: st2.spins_balance ?? 0,
        airtime_points: latestPoints,
        qualified_count: st2.qualified_listings_count ?? 0,
        reward: rewardPayload,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
    );
  } catch (err) {
    console.error("[Spin] Error:", err);
    return new Response(JSON.stringify({ ok: false, error: String((err as any)?.message ?? err) }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    });
  }
});
