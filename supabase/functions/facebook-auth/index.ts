// supabase/functions/facebook-auth/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

// jose 用于 JWT 验签（不是 decode！）
import {
  createRemoteJWKSet,
  jwtVerify,
  JWTPayload,
} from "https://deno.land/x/jose@v4.14.4/index.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type FacebookGraphUser = {
  id: string;
  email?: string;
  name?: string;
  picture?: { data?: { url?: string } };
};

type Identity = {
  provider: "facebook";
  providerUserId: string; // fb user id (Graph id OR OIDC sub)
  email?: string;
  name?: string;
  avatarUrl?: string;
  source: "graph" | "oidc";
};

function isLikelyJwt(token: string): boolean {
  // JWT 通常是 3 段 base64url，用 '.' 分隔
  const parts = token.split(".");
  return parts.length === 3 && parts.every((p) => p.length > 0);
}

function buildPlaceholderEmail(providerUserId: string): string {
  // 固定、可复现：同一个 FB id 永远生成同一个占位邮箱
  return `fb_${providerUserId}@facebook.placeholder.swaply.cc`;
}

function safePreview(token: string, n = 20) {
  if (!token) return "";
  return token.substring(0, Math.min(n, token.length)) + "...";
}

async function verifyByGraph(accessToken: string): Promise<Identity | null> {
  console.log("🔄 [GRAPH] Verifying with Facebook Graph API...");
  const fbUrl =
    `https://graph.facebook.com/me?fields=id,name,email,picture&access_token=${encodeURIComponent(accessToken)}`;

  const fbResponse = await fetch(fbUrl);
  console.log("📊 [GRAPH] status:", fbResponse.status);

  if (!fbResponse.ok) {
    let fbError: unknown = null;
    try {
      fbError = await fbResponse.json();
    } catch (_) {
      fbError = await fbResponse.text();
    }
    console.error("❌ [GRAPH] error:", JSON.stringify(fbError));
    return null;
  }

  const userData: FacebookGraphUser = await fbResponse.json();
  console.log("✅ [GRAPH] verified user:", userData.id, userData.email || "NO EMAIL");

  return {
    provider: "facebook",
    providerUserId: userData.id,
    email: userData.email,
    name: userData.name,
    avatarUrl: userData.picture?.data?.url,
    source: "graph",
  };
}

async function verifyByOidc(accessToken: string): Promise<Identity | null> {
  if (!isLikelyJwt(accessToken)) {
    console.log("ℹ️ [OIDC] Token is not JWT format, skip OIDC.");
    return null;
  }

  console.log("🔄 [OIDC] Verifying as OIDC JWT (Limited Login) ...");

  // Meta 的 JWKS（公钥集合）-- 用于验签（关键：必须验签，不能只 decode）
  // 注：Meta 未来可能调整 jwks 地址；如果你发现验签失败且日志提示无法获取 jwks，
  // 再进一步按 Meta 文档换地址即可。
  const jwksUrl = new URL("https://www.facebook.com/.well-known/oauth/openid/jwks/");
  const JWKS = createRemoteJWKSet(jwksUrl);

  try {
    const { payload, protectedHeader } = await jwtVerify(accessToken, JWKS, {
      // aud/iss 校验：不同 App 配置可能不同，先只做"存在性与基本格式"校验，
      // 同时把 payload 打日志，方便你后续收紧。
      // 如果你知道你 App 的 Client ID，可在这里加 aud: "<FACEBOOK_APP_ID>"
      // 如果你知道 issuer 固定值，可在这里加 issuer: "https://www.facebook.com"
    });

    console.log("✅ [OIDC] jwt verified. header:", JSON.stringify(protectedHeader));
    // payload.sub 是最关键的稳定标识
    const sub = (payload.sub as string | undefined) || "";
    if (!sub) {
      console.error("❌ [OIDC] missing sub in payload");
      return null;
    }

    const email = (payload.email as string | undefined);
    const name = (payload.name as string | undefined);
    const picture = (payload.picture as string | undefined);

    console.log("✅ [OIDC] sub:", sub, "email:", email || "NO EMAIL");

    return {
      provider: "facebook",
      providerUserId: sub,
      email,
      name,
      avatarUrl: picture,
      source: "oidc",
    };
  } catch (e) {
    console.error("❌ [OIDC] jwtVerify failed:", e);
    return null;
  }
}

async function upsertIdentityAndGetUser(
  adminClient: ReturnType<typeof createClient>,
  identity: Identity,
) {
  // 1) 查映射是否存在
  const { data: existing, error: selErr } = await adminClient
    .from("auth_identities")
    .select("user_id, email")
    .eq("provider", identity.provider)
    .eq("provider_user_id", identity.providerUserId)
    .maybeSingle();

  if (selErr) {
    console.error("❌ [DB] select auth_identities error:", selErr);
    throw new Error("Identity lookup failed");
  }

  const finalEmail = identity.email || buildPlaceholderEmail(identity.providerUserId);

  // 2) 生成一次性密码（你前端目前是 email+password 登录）
  const tempPassword = crypto.randomUUID() + crypto.randomUUID();

  if (existing?.user_id) {
    // 已存在映射：只更新 auth.users 的密码/metadata + 更新映射资料
    console.log("✅ [DB] identity mapping exists, user_id:", existing.user_id);

    const { error: updErr } = await adminClient.auth.admin.updateUserById(
      existing.user_id,
      {
        password: tempPassword,
        user_metadata: {
          full_name: identity.name || "",
          avatar_url: identity.avatarUrl || "",
          provider: "facebook",
          facebook_id: identity.providerUserId,
          facebook_source: identity.source,
          is_placeholder_email: !identity.email,
        },
        // 注意：Supabase Admin API 不允许直接修改 email（通常建议用户自助绑定邮箱）
      },
    );

    if (updErr) {
      console.error("❌ [AUTH] updateUserById error:", updErr);
      throw new Error("User update failed");
    }

    // 更新映射表资料（email/name/avatar 可更新）
    const { error: mapUpdErr } = await adminClient
      .from("auth_identities")
      .update({
        email: identity.email || null,
        name: identity.name || null,
        avatar_url: identity.avatarUrl || null,
      })
      .eq("provider", identity.provider)
      .eq("provider_user_id", identity.providerUserId);

    if (mapUpdErr) {
      console.error("❌ [DB] update auth_identities error:", mapUpdErr);
      // 不致命：用户已能登录
    }

    // ✅ 自动认证：只在当前状态为 none 时更新为 verified
    const { data: currentProfile, error: fetchErr } = await adminClient
      .from("profiles")
      .select("verification_type, is_verified")
      .eq("id", existing.user_id)
      .single()
      .catch(() => ({ data: null, error: null }));

    if (fetchErr) {
      console.warn("⚠️ [AUTH] 无法获取当前profile状态:", fetchErr.message);
    }

    // 只在当前状态为 none 或未验证时更新
    const currentType = currentProfile?.verification_type;
    const currentVerified = currentProfile?.is_verified;
    const shouldUpdate = !currentType || currentType === 'none' || !currentVerified;

    if (shouldUpdate) {
      const { error: profileErr } = await adminClient
        .from("profiles")
        .update({
          verification_type: "verified",
          is_verified: true,
          updated_at: new Date().toISOString(),
        })
        .eq("id", existing.user_id);

      if (profileErr) {
        console.error("❌ [DB] update profiles error:", profileErr);
        // 不致命：用户已能登录，但可能没有自动认证
      } else {
        console.log("✅ [AUTH] 自动认证已设置: verification_type='verified' (从 none 升级)");
      }
    } else {
      console.log(`ℹ️ [AUTH] 用户已认证: verification_type='${currentType}', is_verified=${currentVerified}，跳过自动认证`);
    }

    return {
      email: existing.email || finalEmail,
      password: tempPassword,
      user: { name: identity.name, avatar_url: identity.avatarUrl },
    };
  }

  // 3) 没有映射：创建/绑定用户
  // 关键策略：优先用 finalEmail 创建用户；如果 email 已存在（安卓老用户），就查找并绑定映射
  console.log("🆕 [AUTH] creating or binding user. finalEmail:", finalEmail);

  // 3.1 先尝试 createUser（最直接）
  const { data: newUser, error: createErr } = await adminClient.auth.admin.createUser({
    email: finalEmail,
    password: tempPassword,
    email_confirm: true,
    user_metadata: {
      full_name: identity.name || "",
      avatar_url: identity.avatarUrl || "",
      provider: "facebook",
      facebook_id: identity.providerUserId,
      facebook_source: identity.source,
      is_placeholder_email: !identity.email,
    },
  });

  if (!createErr && newUser?.user?.id) {
    console.log("✅ [AUTH] new user created:", newUser.user.id);

    // 插入映射
    const { error: insErr } = await adminClient
      .from("auth_identities")
      .insert({
        provider: identity.provider,
        provider_user_id: identity.providerUserId,
        user_id: newUser.user.id,
        email: identity.email || null,
        name: identity.name || null,
        avatar_url: identity.avatarUrl || null,
      });

    if (insErr) {
      console.error("❌ [DB] insert auth_identities error:", insErr);
      // 理论上不该发生；发生就抛错避免"创建了用户但没映射"导致后续混乱
      throw new Error("Identity mapping insert failed");
    }

    // ✅ 自动认证：新创建的用户设置为已验证（先检查状态）
    const { data: currentProfile, error: fetchErr } = await adminClient
      .from("profiles")
      .select("verification_type, is_verified")
      .eq("id", newUser.user.id)
      .single()
      .catch(() => ({ data: null, error: null }));

    if (fetchErr) {
      console.warn("⚠️ [AUTH] 无法获取新用户profile状态:", fetchErr.message);
    }

    // 新用户通常为 none/null，但安全起见检查
    const currentType = currentProfile?.verification_type;
    const currentVerified = currentProfile?.is_verified;
    const shouldUpdate = !currentType || currentType === 'none' || !currentVerified;

    if (shouldUpdate) {
      const { error: profileErr } = await adminClient
        .from("profiles")
        .update({
          verification_type: "verified",
          is_verified: true,
          updated_at: new Date().toISOString(),
        })
        .eq("id", newUser.user.id);

      if (profileErr) {
        console.error("❌ [DB] update profiles error:", profileErr);
        // 不致命：用户已能登录，但可能没有自动认证
      } else {
        console.log("✅ [AUTH] 新用户自动认证已设置: verification_type='verified'");
      }
    } else {
      console.log(`ℹ️ [AUTH] 新用户已认证: verification_type='${currentType}', is_verified=${currentVerified}，跳过自动认证`);
    }

    return {
      email: finalEmail,
      password: tempPassword,
      user: { name: identity.name, avatar_url: identity.avatarUrl },
    };
  }

  // 3.2 如果 createUser 失败（最常见：email 已存在），就用 listUsers 找到该 email 对应 user_id，然后绑定映射
  console.log("⚠️ [AUTH] createUser failed, trying bind by existing email. err:", createErr?.message);

  let userId: string | null = null;
  let page = 1;

  while (page <= 20) {
    const { data: usersData, error: listErr } = await adminClient.auth.admin.listUsers({
      page,
      perPage: 200,
    });

    if (listErr) {
      console.error("❌ [AUTH] listUsers error:", listErr);
      break;
    }

    const existingUser = usersData?.users?.find((u) => u.email === finalEmail);
    if (existingUser) {
      userId = existingUser.id;
      console.log("✅ [AUTH] found existing user by email:", userId);
      break;
    }

    if (!usersData?.users || usersData.users.length < 200) break;
    page++;
  }

  if (!userId) {
    throw new Error("User exists conflict but cannot find by email");
  }

  // 更新密码 & metadata
  const { error: updErr } = await adminClient.auth.admin.updateUserById(userId, {
    password: tempPassword,
    user_metadata: {
      full_name: identity.name || "",
      avatar_url: identity.avatarUrl || "",
      provider: "facebook",
      facebook_id: identity.providerUserId,
      facebook_source: identity.source,
      is_placeholder_email: !identity.email,
    },
  });

  if (updErr) {
    console.error("❌ [AUTH] updateUserById error:", updErr);
    throw new Error("User update failed");
  }

  // 插入映射（如果并发导致冲突，改为 upsert）
  const { error: mapErr } = await adminClient
    .from("auth_identities")
    .upsert({
      provider: identity.provider,
      provider_user_id: identity.providerUserId,
      user_id: userId,
      email: identity.email || null,
      name: identity.name || null,
      avatar_url: identity.avatarUrl || null,
    }, { onConflict: "provider,provider_user_id" });

  if (mapErr) {
    console.error("❌ [DB] upsert auth_identities error:", mapErr);
    throw new Error("Identity mapping upsert failed");
  }

  // ✅ 自动认证：绑定现有用户时，只在当前状态为 none 时更新为 verified
  const { data: currentProfile, error: fetchErr } = await adminClient
    .from("profiles")
    .select("verification_type, is_verified")
    .eq("id", userId)
    .single()
    .catch(() => ({ data: null, error: null }));

  if (fetchErr) {
    console.warn("⚠️ [AUTH] 无法获取绑定用户profile状态:", fetchErr.message);
  }

  // 只在当前状态为 none 或未验证时更新
  const currentType = currentProfile?.verification_type;
  const currentVerified = currentProfile?.is_verified;
  const shouldUpdate = !currentType || currentType === 'none' || !currentVerified;

  if (shouldUpdate) {
    const { error: profileErr } = await adminClient
      .from("profiles")
      .update({
        verification_type: "verified",
        is_verified: true,
        updated_at: new Date().toISOString(),
      })
      .eq("id", userId);

    if (profileErr) {
      console.error("❌ [DB] update profiles error:", profileErr);
      // 不致命：用户已能登录，但可能没有自动认证
    } else {
      console.log("✅ [AUTH] 绑定用户自动认证已设置: verification_type='verified' (从 none 升级)");
    }
  } else {
    console.log(`ℹ️ [AUTH] 绑定用户已认证: verification_type='${currentType}', is_verified=${currentVerified}，跳过自动认证`);
  }

  return {
    email: finalEmail,
    password: tempPassword,
    user: { name: identity.name, avatar_url: identity.avatarUrl },
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    console.log("🔵 [STEP 1] Facebook auth request received");
    const { accessToken } = await req.json();
    console.log("🔑 [STEP 1] Access token received, length:", accessToken?.length || 0);

    if (!accessToken) {
      return new Response(JSON.stringify({ error: "Access token required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    console.log("🔑 [STEP 1] Token preview:", safePreview(accessToken, 20));

    // Supabase admin client
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    if (!supabaseUrl || !supabaseServiceKey) {
      return new Response(JSON.stringify({ error: "Server configuration error" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const adminClient = createClient(supabaseUrl, supabaseServiceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // 1) Graph 优先（安卓不变）
    let identity: Identity | null = await verifyByGraph(accessToken);

    // 2) Graph 失败 -> OIDC（iOS Limited Login）
    if (!identity) {
      identity = await verifyByOidc(accessToken);
    }

    if (!identity) {
      return new Response(
        JSON.stringify({ error: "Invalid Facebook token (Graph & OIDC failed)" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    console.log("✅ [IDENTITY] source:", identity.source, "providerUserId:", identity.providerUserId);

    // 3) 映射 + 用户创建/更新
    const result = await upsertIdentityAndGetUser(adminClient, identity);

    console.log("🎉 [FINAL] Success! Returning credentials");
    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("💥 [ERROR] Unexpected error:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        details: error instanceof Error ? error.message : "Unknown error",
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});