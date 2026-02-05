import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type LotteryPoolItem =
  | {
      type: "boost_coupon";
      coupon_type: "category" | "search" | "trending";
      pin_days?: number;
      weight: number;
    }
  | { type: "airtime_points"; points: number; weight: number };

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

// coupons.type：你现有系统中通常是 category / featured
// 这里保持兼容：search/trending 都映射为 featured；真正置顶类型用 pin_scope 控制
function mapScopeToType(scope: "category" | "search" | "trending"): string {
  if (scope === "category") return "category";
  return "featured"; // search / trending
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Auth
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) throw new Error("No authorization header");
    const token = authHeader.replace("Bearer ", "");

    const { data: userData, error: authError } = await supabase.auth.getUser(token);
    if (authError || !userData?.user) throw new Error("Authentication failed");
    const user = userData.user;

    // Body
    const body = await req.json().catch(() => ({}));
    const listing_id = body.listing_id as string | undefined;
    const device_id = body.device_id as string | undefined;

    if (!listing_id) {
      return new Response(JSON.stringify({ ok: false, error: "listing_id is required" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    // Campaign
    const { data: campaign, error: campaignError } = await supabase
      .from("reward_campaigns")
      .select("id, code, is_enabled, rules")
      .eq("code", "launch_v1")
      .eq("is_enabled", true)
      .maybeSingle();

    if (campaignError || !campaign) {
      return new Response(JSON.stringify({ ok: false, error: "Campaign not found or disabled" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 404,
      });
    }

    const rules = campaign.rules || {};
    const minPrice = Number(rules.min_listing_price || 50);
    const minImageCount = Number(rules.min_image_count || 2);

    // Listing check
    const { data: listing, error: listingError } = await supabase
      .from("listings")
      .select("id, user_id, images, title, category, city, price, status, is_active")
      .eq("id", listing_id)
      .single();

    if (listingError || !listing) {
      return new Response(JSON.stringify({ ok: false, error: "Listing not found" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 404,
      });
    }

    if (listing.user_id !== user.id) {
      return new Response(JSON.stringify({ ok: false, error: "Not your listing" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 403,
      });
    }

    const images = Array.isArray(listing.images)
      ? listing.images
      : listing.images
      ? [listing.images]
      : [];

    const isQualified =
      images.length >= minImageCount &&
      !!listing.title?.trim?.() &&
      !!listing.category?.trim?.() &&
      !!listing.city?.trim?.() &&
      listing.price != null &&
      Number(listing.price) >= minPrice &&
      listing.status === "active" &&
      listing.is_active !== false;

    if (!isQualified) {
      return new Response(
        JSON.stringify({
          ok: false,
          reason: "not_qualified",
          detail: {
            images: images.length,
            min_images: minImageCount,
            price: listing.price,
            min_price: minPrice,
            status: listing.status,
            is_active: listing.is_active,
          },
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
      );
    }

    // ✅ 读取 state（含 spins_balance）
    const { data: state } = await supabase
      .from("user_reward_state")
      .select("qualified_listings_count, airtime_points, spins_balance")
      .eq("user_id", user.id)
      .eq("campaign_code", campaign.code)
      .maybeSingle();

    const isFirstListing = !state || Number(state.qualified_listings_count ?? 0) === 0;

    // Device risk (first listing only)
    if (device_id && isFirstListing && rules.device_fingerprint_enabled) {
      const { data: deviceRow } = await supabase
        .from("reward_device_map")
        .select("user_id")
        .eq("device_id", device_id)
        .maybeSingle();

      if (deviceRow && deviceRow.user_id !== user.id) {
        return new Response(
          JSON.stringify({
            ok: false,
            reason: "device_blocked",
            message: "Device already claimed first-listing reward",
          }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 403 }
        );
      }

      await supabase.from("reward_device_map").upsert(
        { device_id, user_id: user.id, first_seen_at: new Date().toISOString() },
        { onConflict: "device_id" }
      );
    }

    // Idempotency (listing_id unique)
    const { error: eventError } = await supabase.from("reward_listing_events").insert({
      user_id: user.id,
      listing_id,
      campaign_code: campaign.code,
      qualified: true,
      device_fingerprint: device_id || null,
    });

    // -------------------- helpers --------------------

    // ✅ 原子增加 spins：调用数据库原子 RPC，失败抛异常
    async function addSpinsAtomic(delta: number, reason: string): Promise<number> {
      const { data, error } = await supabase.rpc("reward_add_spins", {
        p_user: user.id,
        p_campaign: campaign.code,
        p_add: delta,
      });
      
      if (error) {
        console.error("[addSpinsAtomic] FAIL", {
          userId: user.id,
          campaign: campaign.code,
          delta,
          reason,
          error
        });
        throw new Error(`addSpinsAtomic failed: ${error.message}`);
      }
      
      if (data == null) {
        throw new Error("addSpinsAtomic returned null");
      }
      
      return Number(data);
    }

    // ❌ 废弃的 CAS 函数，保留引用但标记为弃用
    async function addSpinsCAS(add: number): Promise<number> {
      console.error(`[DEPRECATED] addSpinsCAS called, use addSpinsAtomic instead`);
      return await addSpinsAtomic(add, "legacy_addSpinsCAS");
    }

    async function issueCoupon(scope: "category" | "search" | "trending", pinDays: number, triggerN: number) {
      const couponType = mapScopeToType(scope);
      const scopeNames: Record<string, string> = { category: "Category", search: "Search", trending: "Trending" };

      const title = `${pinDays}-Day ${scopeNames[scope]} Boost`;
      const description = `Reward for publishing #${triggerN} qualified listing`;

      const { data: couponId, error: couponError } = await supabase.rpc("_coupon_insert_v2", {
        p_user: user.id,
        p_source: "lottery_reward",
        p_type: couponType,
        p_title: title,
        p_desc: description,
        p_code_prefix: "RWD",
        p_valid_days: 30,
        p_metadata: {
          source: "lottery_reward",
          trigger_n: triggerN,
          listing_id,
          campaign_code: campaign.code,
        },
      });

      if (couponError) throw new Error(`Failed to issue coupon: ${couponError.message}`);
      if (!couponId || typeof couponId !== "string") throw new Error("Coupon ID not returned");

      const { error: updateError } = await supabase
        .from("coupons")
        .update({
          pin_scope: scope,
          pin_days: pinDays,
          duration_days: pinDays,
          updated_at: new Date().toISOString(),
        })
        .eq("id", couponId);

      if (updateError) console.error(`[Reward] Failed to update coupon scope: ${updateError.message}`);

      await supabase.from("reward_entries").insert({
        user_id: user.id,
        campaign_code: campaign.code,
        trigger_n: triggerN,
        listing_id,
        result_type: "boost_coupon",
        result_payload: { coupon_id: couponId, pin_scope: scope, pin_days: pinDays },
      });

      try {
        await supabase.from("reward_logs").insert({
          user_id: user.id,
          reward_type: "lottery_reward",
          reward_reason: `Listing #${triggerN} reward`,
          coupon_id: couponId,
          metadata: { pin_scope: scope, pin_days: pinDays, campaign_code: campaign.code },
        });
      } catch (_) {}

      return { result_type: "boost_coupon", coupon_id: couponId, pin_scope: scope, pin_days: pinDays };
    }

    async function addPoints(points: number, triggerN: number, reason?: string) {
      const { data: newPoints, error: pointsError } = await supabase.rpc("reward_add_points", {
        p_user: user.id,
        p_points: points,
        p_campaign: campaign.code,
      });
      if (pointsError) throw new Error(`Failed to add points: ${pointsError.message}`);

      await supabase.from("reward_entries").insert({
        user_id: user.id,
        campaign_code: campaign.code,
        trigger_n: triggerN,
        listing_id,
        result_type: "airtime_points",
        result_payload: { points, reason },
      });

      return { result_type: "airtime_points", points, new_points: newPoints, reason };
    }

    // ✅ 统一发 spin（符合 reward_entries_result_type_check）
    // - 只写 result_type="spin"
    // - 成功插入后再 addSpinsCAS，保证 spins_balance 真变
    async function grantSpinOnce(triggerN: number, reason: string, add: number) {
      if (!add || add <= 0) return { granted: false, spins_added: 0, trigger_n: triggerN };

      const { data: entryRow, error: insErr } = await supabase
        .from("reward_entries")
        .insert({
          user_id: user.id,
          campaign_code: campaign.code,
          trigger_n: triggerN,
          listing_id,
          result_type: "spin", // ✅ 必须是 spin
          result_payload: { spins: add, reason, status: "pending" }, // 标记为pending
        })
        .select("id")
        .maybeSingle();

      if (insErr) {
        // 23505 => 已经发过（幂等）
        if ((insErr as any).code !== "23505") {
          throw new Error(`Failed to write spin entry: ${(insErr as any).message}`);
        }
        return { granted: false, spins_added: 0, trigger_n: triggerN };
      }

      if (entryRow?.id) {
        try {
          const newSpins = await addSpinsAtomic(add, reason);
          // 更新为成功状态
          await supabase
            .from("reward_entries")
            .update({ 
              result_payload: { spins: add, new_spins: newSpins, reason, status: "completed" }
            })
            .eq("id", entryRow.id);

          return { granted: true, spins_added: add, trigger_n: triggerN, spins_balance_after: newSpins };
        } catch (spinError) {
          // addSpinsAtomic失败，标记reward_entries记录为失败
          console.error(`[grantSpinOnce] Failed to add spins after inserting entry: ${spinError}`, {
            userId: user.id,
            campaign: campaign.code,
            triggerN,
            entryId: entryRow.id
          });
          
          await supabase
            .from("reward_entries")
            .update({ 
              result_payload: { spins: add, reason, status: "failed", error: String(spinError) }
            })
            .eq("id", entryRow.id);
          
          throw new Error(`Spin grant failed after entry recorded: ${spinError}`);
        }
      }

      return { granted: false, spins_added: 0, trigger_n: triggerN };
    }

    // 先把 loop 规则读取出来，保证 already_processed 也能返回进度
    async function readSpinLoopRule() {
      const { data: ruleLoop } = await supabase
        .from("reward_rules")
        .select("trigger_n, payload")
        .eq("campaign_id", campaign.id)
        .eq("trigger_type", "spin_grant_loop")
        .eq("is_enabled", true)
        .order("trigger_n", { ascending: true })
        .maybeSingle();

      if (!ruleLoop) return null;

      const startAt = Number(ruleLoop.trigger_n ?? 0);
      const spinsEach = Number(ruleLoop.payload?.spins ?? 1);
      const interval = Number(ruleLoop.payload?.loop_interval ?? 10);

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

    const loopRulePre = await readSpinLoopRule();

    // ✅ 里程碑配置（只用于返回给前端，不改你的发奖逻辑）
    const milestoneSteps = [1, 5, 10, 20, 30];
    const milestoneSpinsEach = 1;

    function buildMilestoneProgressText(currentCount: number): string {
      const c = Number(currentCount ?? 0);
      const next = milestoneSteps.find((x) => x > c) ?? null;

      // #30 特殊：保证积分文案
      if (next === 30) return `${c}/30 listings to guarantee 100 points`;

      // 普通：解锁一次 spin
      if (next != null) return `${c}/${next} listings to unlock 1 spin`;

      return "All milestones completed!";
    }

    // -------------------- already processed branch --------------------
    if (eventError) {
      if ((eventError as any).code === "23505") {
        const currentState = state || {
          qualified_listings_count: 0,
          airtime_points: 0,
          spins_balance: 0,
        };

        const spinsNow = currentState.spins_balance ?? 0;

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

        const loop = loopRulePre
          ? calcSpinLoopProgress(Number(currentState.qualified_listings_count ?? 0), loopRulePre)
          : { enabled: false };

        // ✅ 兼容旧字段：next_milestone/milestone_progress（不推荐前端继续用）
        const c = Number(currentState.qualified_listings_count ?? 0);
        const nextMilestoneLegacy = c < 10 ? 10 : c < 30 ? 30 : null;

        return new Response(
          JSON.stringify({
            ok: true,
            reason: "already_processed",
            qualified_count: currentState.qualified_listings_count,
            airtime_points: currentState.airtime_points,
            spins: spinsNow,
            pool,

            // ✅ 本函数不开奖（奖励在 reward-spin 中处理）
            reward: null,

            // ✅ NEW：里程碑配置 & 文案（前端优先用这些）
            milestone_steps: milestoneSteps,
            milestone_spins_each: milestoneSpinsEach,
            milestone_progress_text: buildMilestoneProgressText(c),

            // ✅ 旧字段保留（兼容）
            next_milestone: nextMilestoneLegacy,
            milestone_progress:
              nextMilestoneLegacy === 10
                ? `${c}/10 listings to unlock milestone`
                : nextMilestoneLegacy === 30
                ? `${c}/30 listings to guarantee 100 points`
                : "All milestones completed!",

            // ✅ loop 进度字段（前端用）
            spin_loop_enabled: loop.enabled === true,
            spin_loop_start_at: (loop as any).startAt ?? null,
            spin_loop_interval: (loop as any).interval ?? null,
            spin_loop_next_at: (loop as any).nextAt ?? null,
            spin_loop_remaining: (loop as any).remaining ?? null,
            spin_loop_progress_text:
              loop.enabled === true
                ? c >= (loop as any).startAt
                  ? `${(loop as any).remaining} more listing${(loop as any).remaining === 1 ? "" : "s"} until next spin (#${(loop as any).nextAt})`
                  : `${(loop as any).startAt - c} more listing${((loop as any).startAt - c) === 1 ? "" : "s"} to unlock spin loop (starting at #${(loop as any).startAt})`
                : null,

            // ✅ 这次没有新发 spin
            spin_granted_now: false,
            spins_added_now: 0,
            spin_grant_trigger_n: null,
          }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
        );
      }
      throw new Error(`Failed to record event: ${(eventError as any).message}`);
    }

    // -------------------- main flow --------------------

    // ✅ Bump state (RPC) - 调用 3 参数版本，记录 last_qualified_listing_id
    const { data: bumpResult, error: bumpError } = await supabase.rpc("reward_bump_state", {
      p_user: user.id,
      p_campaign: campaign.code,
      p_listing_id: listing_id, // ✅ 关键：用 3 参数版本
    });
    if (bumpError) throw new Error(`Failed to bump state: ${bumpError.message}`);

    const currentCount = bumpResult?.[0]?.qualified_count ?? 1;
    let currentPoints = bumpResult?.[0]?.airtime_points ?? 0;

    // 本函数不直接发开奖奖励（由 reward-spin 决定）
    let reward: any = null;

    // ✅ 记录本次是否新发 spin（给前端提示）
    let spinGrantedNow = false;
    let spinsAddedNow = 0;
    let spinGrantTriggerN: number | null = null;

    // =========================
    // 你的新规则：里程碑只发 spin
    // 触发点：1 / 5 / 10 / 20 / 30
    // =========================
    const milestoneSpinSet = new Set(milestoneSteps);
    if (milestoneSpinSet.has(currentCount)) {
      const { data: ruleSpin } = await supabase
        .from("reward_rules")
        .select("payload")
        .eq("campaign_id", campaign.id)
        .eq("trigger_n", currentCount)
        .eq("trigger_type", "spin_grant")
        .eq("is_enabled", true)
        .maybeSingle();

      const add = Number(ruleSpin?.payload?.spins ?? 0);
      if (add > 0) {
        const r = await grantSpinOnce(currentCount, `milestone_${currentCount}`, add);
        spinGrantedNow = r.granted === true;
        spinsAddedNow = Number((r as any).spins_added ?? 0);
        spinGrantTriggerN = spinGrantedNow ? currentCount : null;
      }
    }

    // ✅ Trigger #30: guarantee >= 100 points（不改你的规则）
    if (currentCount === 30) {
      const { data: rule30 } = await supabase
        .from("reward_rules")
        .select("payload")
        .eq("campaign_id", campaign.id)
        .eq("trigger_n", 30)
        .eq("trigger_type", "guarantee_airtime")
        .eq("is_enabled", true)
        .maybeSingle();

      if (rule30?.payload) {
        const { data: existing30 } = await supabase
          .from("reward_entries")
          .select("id")
          .eq("user_id", user.id)
          .eq("campaign_code", campaign.code)
          .eq("trigger_n", 30)
          .eq("result_type", "airtime_points")
          .maybeSingle();

        // 注意：这里用 (trigger_n=30 + result_type=airtime_points) 做幂等
        if (!existing30) {
          const minPoints = Number(rule30.payload.min_points || 100);
          if (currentPoints < minPoints) {
            const r30 = await addPoints(minPoints - currentPoints, 30, "guarantee");
            reward = r30; // 这是补齐积分，不是转盘奖励
            currentPoints = Number((r30 as any)?.new_points ?? minPoints);
          }
        }
      }
    }

    // ✅ Trigger #40/#50/#60... loop spins（30之后每10次）
    const loopRule = loopRulePre;
    if (loopRule && currentCount >= loopRule.startAt) {
      const offset = (currentCount - loopRule.startAt) % loopRule.interval;
      const isGrantPoint = offset === 0; // 40,50,60...

      if (isGrantPoint) {
        const add = Number(loopRule.spinsEach || 1);

        // 用 trigger_n = currentCount 做一次性锁：40/50/60...
        const r = await grantSpinOnce(currentCount, "spin_loop", add);

        // 只有当本次没在里程碑发过 spin，才覆盖提示（避免同时命中时混乱）
        if (!spinGrantedNow && r.granted === true) {
          spinGrantedNow = true;
          spinsAddedNow = Number((r as any).spins_added ?? add);
          spinGrantTriggerN = currentCount;
        }
      }
    }

    // ✅ 读取最新 spins_balance
    const { data: latestState } = await supabase
      .from("user_reward_state")
      .select("spins_balance")
      .eq("user_id", user.id)
      .eq("campaign_code", campaign.code)
      .maybeSingle();

    const spins = latestState?.spins_balance ?? 0;

    // ✅ 返回奖池（用于前端画转盘；真正中奖由 reward-spin 决定）
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

    const loop = loopRule
      ? calcSpinLoopProgress(Number(currentCount ?? 0), loopRule)
      : { enabled: false };

    // ✅ 旧字段 nextMilestone 保留（兼容旧 UI），但不再是准确里程碑表
    const nextMilestoneLegacy = currentCount < 10 ? 10 : currentCount < 30 ? 30 : null;

    return new Response(
      JSON.stringify({
        ok: true,
        qualified_count: currentCount,
        airtime_points: currentPoints,
        spins,
        pool,

        // ✅ 本函数不发“转盘中奖奖励”，中奖在 reward-spin 里做
        reward: reward ?? null,

        // ✅ NEW：里程碑配置 & 文案（前端优先用这些）
        milestone_steps: milestoneSteps,
        milestone_spins_each: milestoneSpinsEach,
        milestone_progress_text: buildMilestoneProgressText(Number(currentCount ?? 0)),

        // ✅ 旧字段保留（兼容）
        next_milestone: nextMilestoneLegacy,
        milestone_progress:
          nextMilestoneLegacy === 10
            ? `${currentCount}/10 listings to unlock milestone`
            : nextMilestoneLegacy === 30
            ? `${currentCount}/30 listings to guarantee 100 points`
            : "All milestones completed!",

        // ✅ loop 进度字段
        spin_loop_enabled: loop.enabled === true,
        spin_loop_start_at: (loop as any).startAt ?? null,
        spin_loop_interval: (loop as any).interval ?? null,
        spin_loop_next_at: (loop as any).nextAt ?? null,
        spin_loop_remaining: (loop as any).remaining ?? null,
        spin_loop_progress_text:
          loop.enabled === true
            ? currentCount >= (loop as any).startAt
              ? `${(loop as any).remaining} more listing${(loop as any).remaining === 1 ? "" : "s"} until next spin (#${(loop as any).nextAt})`
              : `${(loop as any).startAt - currentCount} more listing${((loop as any).startAt - currentCount) === 1 ? "" : "s"} to unlock spin loop (starting at #${(loop as any).startAt})`
            : null,

        // ✅ NEW：前端用来决定是否弹出“去转盘/点击开始”
        spin_granted_now: spinGrantedNow,
        spins_added_now: spinsAddedNow,
        spin_grant_trigger_n: spinGrantTriggerN,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
    );
  } catch (err) {
    console.error("[Reward] Error:", err);
    return new Response(JSON.stringify({ ok: false, error: String((err as any)?.message ?? err) }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    });
  }
});