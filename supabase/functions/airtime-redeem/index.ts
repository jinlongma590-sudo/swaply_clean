import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Phone validation function (E.164 format)
function validatePhone(phone: string): { valid: boolean; error?: string; cleanPhone?: string } {
  if (!phone || typeof phone !== 'string') {
    return { valid: false, error: 'Phone number is required' };
  }
  
  // 1. trim 去空格
  const trimmed = phone.trim();
  
  if (trimmed.length === 0) {
    return { valid: false, error: 'Phone number is required' };
  }
  
  // 2. 检查 + 只能出现在开头
  if (trimmed.includes('+') && !trimmed.startsWith('+')) {
    return { valid: false, error: 'Plus sign (+) must be at the beginning' };
  }
  
  // 3. 只允许 + 和数字
  const allowedPattern = /^\+?[0-9]+$/;
  if (!allowedPattern.test(trimmed)) {
    return { valid: false, error: 'Only numbers and + at the beginning allowed' };
  }
  
  // 4. 计算数字长度（不包括 +）
  const digits = trimmed.replace('+', '');
  const totalLength = trimmed.length; // 包含 + 的总长度
  
  // E.164 最长 15 位数字，带 + 最多 16
  if (digits.length < 8 || digits.length > 15) {
    return { valid: false, error: 'Phone number must be 8-15 digits (E.164 format)' };
  }
  
  if (totalLength < 8 || totalLength > 16) {
    return { valid: false, error: 'Total length (with +) must be 8-16 characters' };
  }
  
  return { valid: true, cleanPhone: trimmed };
}

// Mask phone for logs (show only last 4 digits)
function maskPhone(phone: string): string {
  if (!phone || phone.length < 4) return '****';
  const last4 = phone.slice(-4);
  return `****${last4}`;
}

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
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    // Debug logging as requested
    console.log(`[Airtime] hasAnonKey: ${!!anonKey}, hasServiceRoleKey: ${!!serviceRoleKey}, hasSupabaseUrl: ${!!supabaseUrl}`);

    const authHeader = req.headers.get("authorization") || req.headers.get("Authorization") || "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice("Bearer ".length) : null;
    
    console.log(`[Airtime] auth header present: ${!!authHeader}, token extracted: ${!!token}`);
    
    if (!token) {
      return new Response(JSON.stringify({ ok: false, error: "Missing bearer token" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 401,
      });
    }

    // Verify user with service role client
    const admin = createClient(supabaseUrl, serviceRoleKey);
    const { data: userRes, error: userErr } = await admin.auth.getUser(token);
    
    if (userErr || !userRes?.user) {
      console.log(`[Airtime] User verification failed: ${userErr?.message || "No user data"}`);
      return new Response(JSON.stringify({ ok: false, error: "Invalid user token" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 401,
      });
    }

    const user = userRes.user;
    console.log(`[Airtime] User verified: ${user.id}`);

    const body = await req.json().catch(() => ({}));
    console.log(`[Airtime] Request body:`, JSON.stringify(body));
    
    // ✅ 兼容两种参数格式
    // 旧格式：{ p_user, p_campaign, p_points } (来自 RewardCenterHub)
    // 新格式：{ phone, points, campaign } (来自 AirtimeRedeemPage)
    let phone: string | undefined = body?.phone;
    let points: number = Number(body?.points || body?.p_points || 0);
    const campaign: string = body?.campaign || body?.p_campaign || "launch_v1";
    const userIdFromBody: string | undefined = body?.p_user;
    
    console.log(`[Airtime] Parsed params: phone=${phone}, points=${points}, campaign=${campaign}, userIdFromBody=${userIdFromBody}`);
    
    // 验证用户ID（确保从token获取的用户与body中的用户一致）
    if (userIdFromBody && userIdFromBody !== user.id) {
      console.log(`[Airtime] User ID mismatch: token=${user.id}, body=${userIdFromBody}`);
      return new Response(JSON.stringify({ 
        ok: false, 
        error: "User ID mismatch" 
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    // ✅ 获取手机号：如果请求中没有，尝试从profile获取
    if (!phone || typeof phone !== 'string' || phone.trim() === '') {
      console.log(`[Airtime] Phone not provided in request, fetching from profile...`);
      
      try {
        // 使用service_role客户端查询profiles表
        const { data: profile, error: profileError } = await admin
          .from('profiles')
          .select('phone')
          .eq('id', user.id)
          .maybeSingle();
          
        if (profileError) {
          console.log(`[Airtime] Error fetching profile:`, profileError);
        } else if (profile?.phone) {
          phone = profile.phone;
          console.log(`[Airtime] Found phone in profile: ${phone}`);
        } else {
          console.log(`[Airtime] No phone found in profile`);
        }
      } catch (profileErr) {
        console.log(`[Airtime] Exception fetching profile:`, profileErr);
      }
    }
    
    // ✅ 如果仍然没有手机号，返回错误
    if (!phone || phone.trim() === '') {
      console.log(`[Airtime] Missing phone number`);
      return new Response(JSON.stringify({ 
        ok: false, 
        error: "Phone number required. Please update your profile with a phone number.",
        code: "PHONE_REQUIRED"
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    // ✅ Phone validation (E.164 format)
    const phoneValidation = validatePhone(phone);
    if (!phoneValidation.valid) {
      console.log(`[Airtime] Invalid phone format: ${phoneValidation.error}`);
      return new Response(JSON.stringify({
        ok: false,
        error: `Invalid phone number: ${phoneValidation.error}`,
        code: "INVALID_PHONE_FORMAT"
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }
    
    // Use cleaned phone (trimmed)
    const cleanPhone = phoneValidation.cleanPhone!;
    
    // ✅ 脱敏日志：只显示后4位
    const maskedPhone = maskPhone(cleanPhone);
    console.log(`[Airtime] User ${user.id} redeeming ${points} points for ${maskedPhone} (campaign: ${campaign})`);
    console.log(`[Airtime] Raw phone (for debugging): ${cleanPhone}`);

    // ✅ 方案1：使用 service_role 调用 v2 函数（首选，不依赖 auth.uid()）
    const adminClient = createClient(supabaseUrl, serviceRoleKey);
    const v2Args = {
      p_user_id: user.id,
      p_campaign: campaign,
      p_phone: cleanPhone,
      p_points: points,
    };
    console.log(`[Airtime] Attempt 1: Calling airtime_redeem_request_v2 with args:`, v2Args);
    
    let result = null;
    let rpcError = null;
    
    try {
      const { data, error } = await adminClient.rpc("airtime_redeem_request_v2", v2Args);
      result = data;
      rpcError = error;
    } catch (e) {
      console.log(`[Airtime] v2 call failed:`, e);
      rpcError = { message: `v2 call exception: ${e.message}` };
    }

    // ✅ 方案2：如果 v2 不存在，回退到原函数（使用 anonKey + JWT）
    if (rpcError && rpcError.message && rpcError.message.includes('function') && rpcError.message.includes('not found')) {
      console.log(`[Airtime] v2 function not found, falling back to original function`);
      
      const userSb = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: `Bearer ${token}` } },
      });

      const originalArgs = {
        p_campaign: campaign,
        p_phone: cleanPhone,
        p_points: points,
      };
      console.log(`[Airtime] Attempt 2: Calling airtime_redeem_request with args:`, originalArgs);

      const { data: originalData, error: originalError } = await userSb.rpc("airtime_redeem_request", originalArgs);
      result = originalData;
      rpcError = originalError;
    }

    if (rpcError) {
      console.log(`[Airtime] RPC error: ${rpcError.message}, details:`, rpcError);
      return new Response(JSON.stringify({ 
        ok: false, 
        error: `RPC error: ${rpcError.message}`,
        details: rpcError,
        suggestion: rpcError.message.includes('function') && rpcError.message.includes('not found') 
          ? 'Please create airtime_redeem_request_v2 function in database' 
          : undefined
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    console.log(`[Airtime] RPC success:`, result);
    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (err) {
    console.error("[Airtime] Unexpected error:", err);
    return new Response(JSON.stringify({ 
      ok: false, 
      error: String((err as any)?.message ?? err) 
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
