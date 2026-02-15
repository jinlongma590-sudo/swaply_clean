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
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const requestId = crypto.randomUUID();

  try {
    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    // ✅ 强制检查：没有 service role 直接报错（否则 RLS 会把你挡死）
    if (!url || !serviceKey) {
      throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in Edge Function env");
    }

    const supabase = createClient(url, serviceKey);

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
    const listing_id = body.listing_id as string | undefined; // ✅ 可选（Reward Center 场景允许不传）
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

    const campaignCode = campaign.code;

    // ------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------
    async function addSpinsAtomic(delta: number, reason: string): Promise<number> {
      if (delta <= 0) throw new Error(`addSpinsAtomic: delta must be > 0, got ${delta}`);
      const { data, error } = await supabase.rpc("reward_grant_spins_v2", {
        p_user: user.id,
        p_campaign: campaignCode,
        p_add: delta,
        p_reason: reason,
        p_ref: requestId ?? null,
      });
      if (error) throw new Error(`addSpinsAtomic failed: ${error.message}`);
      if (!data || data.length === 0) throw new Error("addSpinsAtomic returned empty");
      const row = data[0];
      if (!row.ok) throw new Error(`addSpinsAtomic rejected: ${reason}`);
      return Number(row.spins_balance);
    }

    // ❌ 废弃的 CAS 函数，保留引用但标记为弃用
    async function addSpinsCAS(add: number): Promise<number> {
      console.error(`[DEPRECATED] addSpinsCAS called, use addSpinsAtomic instead`);
      return await addSpinsAtomic(add, "legacy_addSpinsCAS");
    }

    async function finalizeRequest(result_type: string, result_payload: any) {
      const { error } = await supabase
        .from("reward_spin_requests")
        .update({
          result_type,
          result_payload,
        })
        .eq("user_id", user.id)
        .eq("campaign_code", campaignCode)
        .eq("request_id", request_id);

      if (error) console.error(`[Spin] Failed to finalize spin request: ${error.message}`);
    }

    // ------------------------------------------------------------
    // ✅ Step 1: Reservation（先占位幂等记录）
    // ------------------------------------------------------------
    const reservation = {
      user_id: user.id,
      campaign_code: campaignCode,
      request_id,
      listing_id: listing_id ?? null, // ✅ 可空
      device_id: device_id ?? null,
      result_type: null,
      result_payload: null,
    };

    const { error: insReqErr } = await supabase.from("reward_spin_requests").insert(reservation);

    if (insReqErr) {
      // unique violation => 幂等：读已有结果返回（不会重复扣 spin）
      if ((insReqErr as any).code === "23505") {
        const { data: existed } = await supabase
          .from("reward_spin_requests")
          .select("result_type, result_payload")
          .eq("user_id", user.id)
          .eq("campaign_code", campaignCode)
          .eq("request_id", request_id)
          .maybeSingle();

        const { data: st } = await supabase
          .from("user_reward_state")
          .select("spins_balance, airtime_points, qualified_listings_count, lifetime_spins")
          .eq("user_id", user.id)
          .eq("campaign_code", campaignCode)
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
            pending: existed?.result_type == null,
          }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
        );
      }

      throw new Error(`Failed to create spin request: ${insReqErr.message}`);
    }

    // ------------------------------------------------------------
    // ✅ Step 2: Atomically consume 1 spin (RPC)
    // 你即将创建的函数：reward_consume_spin(p_user uuid, p_campaign text) -> table(spins_left int)
    // ------------------------------------------------------------
    const { data: consumed, error: consumeErr } = await supabase.rpc("reward_consume_spin_v2", {
      p_user: user.id,
      p_campaign: campaignCode,
      p_ref: requestId,
    });

    if (consumeErr) {
      // RPC 异常：标记为 none，方便幂等回放
      await finalizeRequest("none", { result_type: "none", reason: "consume_rpc_error" });
      throw new Error(`consume spin rpc failed: ${consumeErr.message}`);
    }

    const noSpins = consumeErr || !consumed || consumed.length === 0 || consumed[0]?.ok === false || Number(consumed[0]?.spins_left ?? -1) < 0;
    if (noSpins) {
      await finalizeRequest("none", { result_type: "none", reason: "no_spins" });
      return new Response(JSON.stringify({ ok: false, reason: "no_spins", spins_left: 0 }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      });
    }
    let spinsLeft = Number(consumed[0].spins_left);

    // ------------------------------------------------------------
    // ✅ Step 3: Read state for response fields (points/qualified_count)
    // ------------------------------------------------------------
    const { data: st2, error: st2Err } = await supabase
      .from("user_reward_state")
      .select("qualified_listings_count, airtime_points, spins_balance, lifetime_spins")
      .eq("user_id", user.id)
      .eq("campaign_code", campaignCode)
      .maybeSingle();

    if (st2Err) {
      // 这里已经扣了 spin，为避免用户“被扣但没结果”，尽量退款 + finalize
      try {
        const { data: refunded, error: refundErr } = await supabase.rpc("reward_grant_spins_v2", {
          p_user: user.id,
          p_campaign: campaignCode,
          p_add: 1,
          p_reason: "refund",
          p_ref: requestId,
        });
        if (refundErr) throw new Error(`refund failed: ${refundErr.message}`);
        if (!refunded || refunded.length === 0 || refunded[0]?.ok !== true) throw new Error("refund rejected/empty");
        await finalizeRequest("none", { result_type: "none", reason: "state_read_error_refunded" });
      } catch (refundErr: any) {
        await finalizeRequest("none", { result_type: "none", reason: "state_read_error_refund_failed", error: String(refundErr?.message ?? refundErr) });
        throw refundErr;
      }
      throw new Error(`Failed to read user state after consume: ${st2Err.message}`);
    }

    const qualifiedCount = Number(st2?.qualified_listings_count ?? 0);
    let latestPoints = Number(st2?.airtime_points ?? 0);
    let latestSpins = Number(st2?.spins_balance ?? spinsLeft); // 保险

    // ------------------------------------------------------------
    // ✅ Step 4: Load pool
    // ------------------------------------------------------------
    const { data: poolRows, error: poolErr } = await supabase
      .from("reward_pool_items")
      .select("id, title, item_type, payload, weight")
      .eq("campaign_code", campaignCode)
      .eq("is_active", true)
      .order("sort_order", { ascending: true });

    if (poolErr) {
      // refund spin
      try {
        const { data: refunded, error: refundErr } = await supabase.rpc("reward_grant_spins_v2", {
          p_user: user.id,
          p_campaign: campaignCode,
          p_add: 1,
          p_reason: "refund",
          p_ref: requestId,
        });
        if (refundErr) throw new Error(`refund failed: ${refundErr.message}`);
        if (!refunded || refunded.length === 0 || refunded[0]?.ok !== true) throw new Error("refund rejected/empty");
        latestSpins = Number(refunded[0].spins_balance);
        await finalizeRequest("none", { result_type: "none", reason: "pool_error_refunded" });
      } catch (refundErr: any) {
        await finalizeRequest("none", { result_type: "none", reason: "pool_error_refund_failed", error: String(refundErr?.message ?? refundErr) });
        throw refundErr;
      }
      throw new Error(`Failed to load pool: ${poolErr.message}`);
    }

    const pool = (poolRows || []) as PoolRow[];
    if (!pool.length) {
      // refund spin
      try {
        const { data: refunded, error: refundErr } = await supabase.rpc("reward_grant_spins_v2", {
          p_user: user.id,
          p_campaign: campaignCode,
          p_add: 1,
          p_reason: "refund",
          p_ref: requestId,
        });
        if (refundErr) throw new Error(`refund failed: ${refundErr.message}`);
        if (!refunded || refunded.length === 0 || refunded[0]?.ok !== true) throw new Error("refund rejected/empty");
        latestSpins = Number(refunded[0].spins_balance);
        await finalizeRequest("none", { result_type: "none", reason: "no_pool_refunded" });
      } catch (refundErr: any) {
        await finalizeRequest("none", { result_type: "none", reason: "no_pool_refund_failed", error: String(refundErr?.message ?? refundErr) });
        throw refundErr;
      }
      throw new Error("No pool configured");
    }

    // Get lifetime spins count for new user script
    const lifetimeSpins = Number(st2?.lifetime_spins ?? 0);
    let selected: PoolRow;
    
    // New user script: first 3 spins are fixed rewards
    if (lifetimeSpins === 0) {
      // First spin: 10 Points
      selected = pool.find(item => item.title.includes("10 Airtime Points")) || pool[0];
    } else if (lifetimeSpins === 1) {
      // Second spin: 5 Points
      selected = pool.find(item => item.title.includes("5 Airtime Points")) || pool[0];
    } else if (lifetimeSpins === 2) {
      // Third spin: Category Boost
      selected = pool.find(item => item.title.includes("Category Boost")) || pool[0];
    } else {
      // From 4th spin onwards: normal weighted random
      selected = pickWeighted(pool);
    }

    // ------------------------------------------------------------
    // ✅ Step 5: Issue reward (仍然只写 reward_spin_requests，不写 reward_entries)
    // ------------------------------------------------------------
    let rewardType: string = selected.item_type;
    let rewardPayload: any = null;

    if (selected.item_type === "airtime_points") {
      const pts = Number(selected.payload?.points ?? 0);

      if (pts > 0) {
        const { data: newPoints, error: ptsErr } = await supabase.rpc("reward_add_points", {
          p_user: user.id,
          p_points: pts,
          p_campaign: campaignCode,
        });

        if (ptsErr) {
          try {
            const { data: refunded, error: refundErr } = await supabase.rpc("reward_grant_spins_v2", {
              p_user: user.id,
              p_campaign: campaignCode,
              p_add: 1,
              p_reason: "refund",
              p_ref: requestId,
            });
            if (refundErr) throw new Error(`refund failed: ${refundErr.message}`);
            if (!refunded || refunded.length === 0 || refunded[0]?.ok !== true) throw new Error("refund rejected/empty");
            await finalizeRequest("none", { result_type: "none", reason: "points_error_refunded" });
          } catch (refundErr: any) {
            await finalizeRequest("none", { result_type: "none", reason: "points_error_refund_failed", error: String(refundErr?.message ?? refundErr) });
            throw refundErr;
          }
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
          listing_id: listing_id ?? null, // ✅ 可空
          device_id: device_id ?? null,
          campaign_code: campaignCode,
          pool_item_id: selected.id,
          pin_scope: scope,
          pin_days: pinDays,
        },
      });

      if (cErr || !couponId || typeof couponId !== "string") {
        // refund spin
        try {
          const { data: refunded, error: refundErr } = await supabase.rpc("reward_grant_spins_v2", {
            p_user: user.id,
            p_campaign: campaignCode,
            p_add: 1,
            p_reason: "refund",
            p_ref: requestId,
          });
          if (refundErr) throw new Error(`refund failed: ${refundErr.message}`);
          if (!refunded || refunded.length === 0 || refunded[0]?.ok !== true) throw new Error("refund rejected/empty");
          latestSpins = Number(refunded[0].spins_balance);
          await finalizeRequest("none", { result_type: "none", reason: "coupon_error_refunded" });
        } catch (refundErr: any) {
          await finalizeRequest("none", { result_type: "none", reason: "coupon_error_refund_failed", error: String(refundErr?.message ?? refundErr) });
          throw refundErr;
        }
        throw new Error(`Failed to issue coupon: ${cErr?.message ?? "coupon id missing"}`);
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
    // ✅ Step 6: Finalize request record (幂等回放关键)
    // ------------------------------------------------------------
    await finalizeRequest(rewardType, rewardPayload);

    // ------------------------------------------------------------
    // ✅ Step 7: Update lifetime spins count (for new user script)
    // ------------------------------------------------------------
    try {
      const { error: updateErr } = await supabase
        .from("user_reward_state")
        .update({ lifetime_spins: (lifetimeSpins + 1) })
        .eq("user_id", user.id)
        .eq("campaign_code", campaignCode);
      if (updateErr) {
        console.error(`[Spin] Failed to update lifetime_spins: ${updateErr.message}`);
      }
    } catch (updateErr) {
      console.error(`[Spin] Exception updating lifetime_spins: ${updateErr}`);
    }

    // ------------------------------------------------------------
    // ✅ Response
    // 注意：前端 RewardBottomSheet 需要 reward 里有 result_type 字段
    // ------------------------------------------------------------
    return new Response(
      JSON.stringify({
        ok: true,
        spins_left: latestSpins, // ✅ 以 state 为准（如果中途退款也正确）
        airtime_points: latestPoints,
        qualified_count: qualifiedCount,
        reward: rewardPayload, // ✅ 包含 result_type
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
