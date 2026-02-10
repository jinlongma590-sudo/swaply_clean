import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Allowlist of allowed actions (must be code constant, no DB/env reads)
const ALLOWED_ACTIONS = [
  // coupons
  "redeem_search_popular_coupon",
  "use_coupon_for_pinning",
  "ensure_welcome_coupon",

  // referrals
  "link_referral",
  "complete_referral",
  "issue_referral_milestone_reward",

  // messaging / offers
  "send_offer_message_v2",

  // analytics
  "increment_listing_views",

  // verification (read only)
  "get_user_verification_public",

  // seller contact (sensitive fields via Edge Function)
  "get_seller_contact",

  // admin functions (separate Edge Function would be better, but keep for now)
  "admin_get_user_email",
  "admin_find_user_by_email",

  // profile verification write
  "upsert_user_verification",

  // notifications
  "notify_favorite",

  // airtime redemption
  "airtime_redeem_request",
  "airtime_redeem_request_v2",
] as const;

type AllowedAction = typeof ALLOWED_ACTIONS[number];

// Anonymous actions (no JWT required)
const ANON_ACTIONS: AllowedAction[] = [
  "increment_listing_views",
  "get_user_verification_public",
];

// Authenticated actions (require JWT)
const AUTH_ACTIONS: AllowedAction[] = [
  "redeem_search_popular_coupon",
  "use_coupon_for_pinning",
  "ensure_welcome_coupon",
  "link_referral",
  "complete_referral",
  "issue_referral_milestone_reward",
  "send_offer_message_v2",
  "get_seller_contact",
  "upsert_user_verification",
  "notify_favorite",
  "airtime_redeem_request",
  "airtime_redeem_request_v2",
];

// Admin actions (require admin permission)
const ADMIN_ACTIONS: AllowedAction[] = [
  "admin_get_user_email",
  "admin_find_user_by_email",
];

// Create a Set for O(1) lookup
const ALLOWED_ACTIONS_SET = new Set(ALLOWED_ACTIONS as readonly string[]);

// Helper functions
function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 
      ...corsHeaders,
      "content-type": "application/json; charset=utf-8" 
    },
  });
}

function errMsg(e: unknown) {
  return e instanceof Error ? e.message : String(e);
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const start = Date.now();

  // ✅ 这些变量必须先定义，catch 永远可用
  let action = "";
  let authLevel: "anon" | "auth" | "admin" | "unknown" = "unknown";
  let userId: string | null = null;
  let user: any = null;

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);
    
    // Parse request
    const body = await req.json().catch(() => ({}));
    action = String(body?.action ?? "");
    const params = body?.params || {};

    // ✅ unknown action：直接 400 返回，绝不 throw
    if (!ALLOWED_ACTIONS_SET.has(action)) {
      console.log(JSON.stringify({
        tag: "rpc_proxy",
        ok: false,
        reason: "action_not_allowed",
        action,
        authLevel,
        userId,
        ms: Date.now() - start,
      }));

      return json(400, {
        ok: false,
        error: {
          code: "ACTION_NOT_ALLOWED",
          message: `Action '${action}' is not allowed`,
        },
      });
    }

    // Authentication & authorization
    const authHeader = req.headers.get("Authorization");
    
    // Determine authentication level based on action
    if (ANON_ACTIONS.includes(action as AllowedAction)) {
      authLevel = 'anon';
      // No JWT required for anonymous actions
    } else if (AUTH_ACTIONS.includes(action as AllowedAction) || ADMIN_ACTIONS.includes(action as AllowedAction)) {
      // Require JWT for authenticated and admin actions
      if (!authHeader) {
        return json(401, {
          ok: false,
          error: {
            code: "AUTH_REQUIRED",
            message: "Authorization header required for this action",
          },
        });
      }
      
      const token = authHeader.replace("Bearer ", "");
      const { data: userRes, error: authErr } = await supabaseAdmin.auth.getUser(token);
      if (authErr || !userRes?.user) {
        return json(401, {
          ok: false,
          error: {
            code: "AUTH_FAILED",
            message: "Authentication failed",
          },
        });
      }
      user = userRes.user;
      userId = user.id;
      
      if (ADMIN_ACTIONS.includes(action as AllowedAction)) {
        authLevel = 'admin';
        // Check admin permission
        const adminUids = (Deno.env.get("SWAPLY_ADMIN_UIDS") ?? "").split(",").map(s => s.trim());
        if (!adminUids.includes(user.id)) {
          // Fallback: check if user has admin role in profiles
          const { data: profile } = await supabaseAdmin
            .from("profiles")
            .select("is_admin, role")
            .eq("id", user.id)
            .maybeSingle();
          
          const isAdmin = profile?.is_admin === true || profile?.role === 'admin';
          if (!isAdmin) {
            return json(403, {
              ok: false,
              error: {
                code: "ADMIN_REQUIRED",
                message: "Admin permission required",
              },
            });
          }
        }
      } else {
        authLevel = 'auth';
      }
    } else {
      // This should not happen because of the allowlist check above
      return json(500, {
        ok: false,
        error: {
          code: "INTERNAL_ERROR",
          message: `Action '${action}' has no defined auth level`,
        },
      });
    }
    
    // Log request start with auth level
    console.log(JSON.stringify({
      tag: "rpc_proxy",
      action,
      auth_level: authLevel,
      user_id: userId,
      ok: true,
      start: true,
      ms: Date.now() - start
    }));
    
    // Prepare RPC parameters with user identity binding
    let rpcParams = { ...params };
    
    // Force user identity binding for specific actions
    if (user) {
      switch (action) {
        case "ensure_welcome_coupon":
          // Force p_user to be current user
          rpcParams.p_user = user.id;
          break;
          
        case "link_referral":
          // Force p_invitee to be current user (cannot invite others on behalf)
          rpcParams.p_invitee = user.id;
          break;
          
        case "complete_referral":
          // Force p_invitee to be current user
          rpcParams.p_invitee = user.id;
          break;
          
        case "issue_referral_milestone_reward":
          // Force p_inviter to be current user (reward the inviter)
          rpcParams.p_inviter = user.id;
          break;
          
        case "send_offer_message_v2":
          // Force sender to be current user
          rpcParams.sender_id = user.id;
          break;
          
        case "upsert_user_verification":
          // Force user_id to be current user
          rpcParams.user_id = user.id;
          break;
          
        case "notify_favorite":
          // Force actor to be current user if actor field exists
          if (rpcParams.p_actor_id !== undefined) {
            rpcParams.p_actor_id = user.id;
          }
          break;
          
        case "redeem_search_popular_coupon":
        case "use_coupon_for_pinning":
          // These should be user-specific by design
          break;
          
        case "get_seller_contact":
          // Keep seller_id from params, just validate user is logged in
          break;
          
        case "admin_get_user_email":
          // Admin action, keep target user from params
          break;
      }
    }
    
    let data: any = null;
    let error: any = null;
    
    // Special handling for non-RPC actions
    if (action === "get_seller_contact") {
      const { seller_id } = rpcParams;
      if (!seller_id) {
        return json(400, {
          ok: false,
          error: {
            code: "BAD_REQUEST",
            message: "Missing seller_id parameter",
          },
        });
      }
      
      // Query profiles table for phone (service_role has access)
      const { data: profile, error: queryError } = await supabaseAdmin
        .from("profiles")
        .select("phone, whatsapp")
        .eq("id", seller_id)
        .maybeSingle();
        
      if (queryError) {
        error = queryError;
      } else {
        data = { 
          phone: profile?.phone || null,
          whatsapp: profile?.whatsapp || null
        };
      }
    } else if (action === "admin_get_user_email") {
      const { user_id } = rpcParams;
      if (!user_id) {
        return json(400, {
          ok: false,
          error: {
            code: "BAD_REQUEST",
            message: "Missing user_id parameter",
          },
        });
      }
      
      const { data: profile, error: queryError } = await supabaseAdmin
        .from("profiles")
        .select("email")
        .eq("id", user_id)
        .maybeSingle();
        
      if (queryError) {
        error = queryError;
      } else {
        data = { email: profile?.email || null };
      }
    } else if (action === "admin_find_user_by_email") {
      const { email } = rpcParams;
      if (!email) {
        return json(400, {
          ok: false,
          error: {
            code: "BAD_REQUEST",
            message: "Missing email parameter",
          },
        });
      }
      
      const { data: profile, error: queryError } = await supabaseAdmin
        .from("profiles")
        .select("id, email, full_name, avatar_url")
        .eq("email", email)
        .maybeSingle();
        
      if (queryError) {
        error = queryError;
      } else {
        data = profile || null;
      }
    } else {
      // Execute RPC for all other actions
      const rpcResult = await supabaseAdmin.rpc(action, rpcParams);
      data = rpcResult.data;
      error = rpcResult.error;
    }
    
    if (error) {
      console.log(JSON.stringify({
        tag: "rpc_proxy",
        action,
        auth_level: authLevel,
        user_id: userId,
        ok: false,
        error_code: error.code || "RPC_ERROR",
        ms: Date.now() - start
      }));
      console.error(`[rpc-proxy] Error for ${action}:`, error);
      return json(400, {
        ok: false,
        error: {
          code: error.code || "RPC_ERROR",
          message: `${action} error: ${error.message}`,
        },
      });
    }
    
    // Success log
    console.log(JSON.stringify({
      tag: "rpc_proxy",
      action,
      auth_level: authLevel,
      user_id: userId,
      ok: true,
      ms: Date.now() - start
    }));
    
    // Return result
    return json(200, { ok: true, data });
    
  } catch (err) {
    const msg = errMsg(err);

    // ✅ 日志必须可序列化：只打字符串/数字
    console.error(JSON.stringify({
      tag: "rpc_proxy",
      ok: false,
      action: action || "(unset)",
      authLevel,
      userId,
      ms: Date.now() - start,
      err: msg,
    }));

    return json(500, {
      ok: false,
      error: { code: "RPC_PROXY_INTERNAL", message: msg },
    });
  }
});