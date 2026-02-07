import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const cronSecret = Deno.env.get("MONITOR_CRON_SECRET") ?? "";
    const headerSecret = req.headers.get("x-monitor-secret") ?? "";
    
    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error("Missing Supabase environment variables");
    }
    
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);
    
    // ✅ 如果带对 secret，就放行（无需 JWT）
    // ✅ 否则走 JWT 认证逻辑
    const cronAuthed = cronSecret.length > 0 && headerSecret === cronSecret;
    
    if (!cronAuthed) {
      // 走 JWT 校验
      const authHeader = req.headers.get("Authorization");
      if (!authHeader) {
        return new Response(
          JSON.stringify({
            ok: false,
            error: { code: "UNAUTHORIZED", message: "Missing authorization header" }
          }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 401,
          }
        );
      }
      
      const token = authHeader.replace("Bearer ", "");
      const { data: userRes, error: authErr } = await supabaseAdmin.auth.getUser(token);
      if (authErr || !userRes?.user) {
        return new Response(
          JSON.stringify({
            ok: false,
            error: { code: "AUTH_FAILED", message: "Authentication failed" }
          }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 401,
          }
        );
      }
      
      // 可选：检查用户权限（如 admin）
      // 暂时跳过，因为 monitor-daily 主要供内部使用
    }
    
    // 1) 执行每日对账检查
    console.log("[monitor-daily] Starting daily spin reconciliation check...");
    const { error: checkError } = await supabaseAdmin.rpc("monitor_spin_daily_check");
    
    if (checkError) {
      console.error("[monitor-daily] monitor_spin_daily_check error:", checkError);
      throw new Error(`Daily check failed: ${checkError.message}`);
    }
    
    // 2) 检查最近24小时的告警
    const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    
    const { data: recentAlerts, error: alertsError } = await supabaseAdmin
      .from("monitor_alerts")
      .select("alert_type, severity, created_at, payload")
      .gte("created_at", twentyFourHoursAgo)
      .order("created_at", { ascending: false })
      .limit(10);
    
    if (alertsError) {
      console.error("[monitor-daily] Failed to fetch alerts:", alertsError);
      throw new Error(`Alerts fetch failed: ${alertsError.message}`);
    }
    
    // 3) 检查 Spin 对账视图（直接验证）
    const { data: spinRecon, error: reconError } = await supabaseAdmin
      .from("monitor_spin_recon")
      .select("user_id, campaign_code, state_balance, ledger_balance, diff")
      .limit(5);
    
    if (reconError) {
      console.error("[monitor-daily] Failed to fetch spin recon:", reconError);
    }
    
    // 4) 查找对账不一致的记录
    const { data: badRows, error: badRowsError } = await supabaseAdmin
      .from("monitor_spin_recon")
      .select("user_id, campaign_code, state_balance, ledger_balance, diff")
      .neq("diff", 0)
      .limit(10);
    
    const hasBadRows = !badRowsError && badRows && badRows.length > 0;
    
    // 5) 汇总结果
    const summary = {
      timestamp: new Date().toISOString(),
      alerts_last_24h: recentAlerts?.length || 0,
      alerts: recentAlerts || [],
      spin_recon_sample: spinRecon || [],
      has_bad_rows: hasBadRows,
      bad_rows_count: hasBadRows ? badRows?.length : 0,
      status: hasBadRows ? "warning" : "healthy"
    };
    
    console.log("[monitor-daily] Daily check completed:", JSON.stringify({
      tag: "monitor_daily",
      alerts_count: summary.alerts_last_24h,
      has_bad_rows: summary.has_bad_rows,
      status: summary.status
    }));
    
    return new Response(
      JSON.stringify({
        ok: true,
        data: summary,
        message: hasBadRows 
          ? `⚠️ Found ${summary.bad_rows_count} spin reconciliation discrepancies` 
          : "✅ Daily monitoring check passed"
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
    
  } catch (err) {
    console.error("[monitor-daily] Error:", err);
    return new Response(
      JSON.stringify({ 
        ok: false, 
        error: {
          message: String((err as any)?.message ?? err),
          code: "MONITOR_ERROR"
        }
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      }
    );
  }
});