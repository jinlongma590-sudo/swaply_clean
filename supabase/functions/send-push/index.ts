import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "npm:jose@5.9.6";

type Payload = {
  user_id: string;
  title: string;
  body: string;
  data?: Record<string, string>;
  platform?: "ios" | "android";
  // ✅ 可选：用于幂等（建议传 notifications.id 或你业务唯一 id）
  message_id?: string;
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// ================================
// ✅ 0) 可选 webhook secret 校验（配了才强制）
// ================================
function checkWebhookSecret(req: Request) {
  const secret = Deno.env.get("WEBHOOK_SECRET");
  if (!secret) return true;
  const auth = req.headers.get("authorization") || "";
  return auth === `Bearer ${secret}`;
}

// ================================
// ✅ 1) Google access token 缓存（best-effort）
// ================================
type TokenCache = { token: string; expiresAt: number; projectId: string };
let cached: TokenCache | null = null;

async function getGoogleAccessToken() {
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID")!;
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL")!;
  let privateKey = Deno.env.get("FIREBASE_PRIVATE_KEY")!;
  privateKey = privateKey.replace(/\\n/g, "\n");

  const nowMs = Date.now();
  if (cached && cached.projectId === projectId && cached.expiresAt > nowMs) {
    return { access_token: cached.token, projectId };
  }

  const now = Math.floor(nowMs / 1000);
  const aud = "https://oauth2.googleapis.com/token";
  const scope = "https://www.googleapis.com/auth/firebase.messaging";

  const key = await importPKCS8(privateKey, "RS256");
  const assertion = await new SignJWT({ scope })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(clientEmail)
    .setSubject(clientEmail)
    .setAudience(aud)
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);

  const resp = await fetch(aud, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  const text = await resp.text();
  if (!resp.ok) throw new Error(`oauth_token_error: ${resp.status} ${text}`);

  let parsed: any = null;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error(`oauth_token_invalid_json: ${text}`);
  }

  const access_token = parsed?.access_token;
  const expires_in = Number(parsed?.expires_in ?? 3600);
  if (!access_token) throw new Error(`oauth_token_missing_access_token: ${text}`);

  // ✅ 提前 2 分钟过期
  cached = {
    token: access_token,
    projectId,
    expiresAt: nowMs + Math.max(60, expires_in - 120) * 1000,
  };

  return { access_token, projectId };
}

// ================================
// ✅ 2) 判断是否应回收 token
// ================================
function shouldRemoveTokenFromFCMError(text: string) {
  let obj: any = null;
  try {
    obj = JSON.parse(text);
  } catch {
    return false;
  }

  const err = obj?.error;
  if (!err) return false;

  let code: string | undefined;

  if (Array.isArray(err.details)) {
    for (const d of err.details) {
      if (d?.["@type"]?.includes("google.firebase.fcm.v1.FcmError") && d.errorCode) {
        code = d.errorCode;
        break;
      }
    }
    if (!code) {
      for (const d of err.details) {
        if (d?.errorCode) {
          code = d.errorCode;
          break;
        }
      }
    }
  }
  if (!code && err.status) code = err.status;

  const msg = String(err.message ?? "").toLowerCase();

  return (
    ["UNREGISTERED", "INVALID_ARGUMENT", "NOT_FOUND", "INVALID_REGISTRATION"].includes(String(code)) ||
    msg.includes("not a valid fcm registration token") ||
    msg.includes("registration token is not a valid")
  );
}

// ================================
// ✅ 3) 发送 FCM（分平台）
// ================================
async function sendFCM(
  accessToken: string,
  projectId: string,
  token: string,
  p: Payload,
  platform: "ios" | "android" | "unknown",
) {
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  // ✅ 强制 data 为 string
  const data: Record<string, string> = {};
  for (const [k, v] of Object.entries(p.data ?? {})) data[k] = String(v);

  const message: any = {
    token,
    notification: { title: p.title, body: p.body },
    data,
  };

  if (platform === "android") {
    message.android = {
      priority: "HIGH",
      notification: {
        title: p.title,
        body: p.body,
        sound: "default",
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
    };
  } else if (platform === "ios") {
    message.apns = {
      headers: {
        "apns-priority": "10",
        "apns-push-type": "alert",
      },
      payload: {
        aps: {
          alert: { title: p.title, body: p.body },
          sound: "default",
        },
      },
    };
  }

  const resp = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ message }),
  });

  const text = await resp.text();
  return { ok: resp.ok, status: resp.status, text };
}

// ================================
// ✅ 4) 幂等（原子 claim + sending 卡死 takeover）
// 需要表 notification_push_deliveries 且 UNIQUE(notification_id, token_id)
// 若表不存在/类型不匹配/没传 message_id => 自动降级不影响主流程
// ================================
const SENDING_TTL_MS = 2 * 60 * 1000; // sending 超过 2 分钟认为卡死可接管

async function claimDelivery(
  supabase: any,
  notificationId: string,
  tokenId: string,
) {
  if (!notificationId) return { mode: "disabled" as const, claimed: true, skipped: false, reason: "no_message_id" };

  // 如果你表里 notification_id 是 uuid，而你传的是非 uuid，会直接 22P02
  if (!UUID_RE.test(notificationId)) {
    return { mode: "disabled" as const, claimed: true, skipped: false, reason: "message_id_not_uuid" };
  }

  const nowIso = new Date().toISOString();

  // 1) 先尝试原子插入（失败则说明已存在）
  const ins = await supabase
    .from("notification_push_deliveries")
    .insert({
      notification_id: notificationId,
      token_id: tokenId,
      status: "sending",
      sent_at: nowIso,
    })
    .select("status,sent_at");

  if (ins.error) {
    // 表不存在 / 无权限 / 类型不匹配：降级
    const code = String(ins.error.code ?? "");
    const msg = String(ins.error.message ?? "").toLowerCase();
    if (code === "42P01" || msg.includes("relation") || msg.includes("does not exist")) {
      return { mode: "disabled" as const, claimed: true, skipped: false, reason: "table_missing" };
    }
    if (code === "42501" || msg.includes("permission")) {
      return { mode: "disabled" as const, claimed: true, skipped: false, reason: "no_permission" };
    }
    if (code === "22P02") {
      return { mode: "disabled" as const, claimed: true, skipped: false, reason: "bad_id_type" };
    }

    // 唯一冲突：说明有人已处理/正在处理
    if (code === "23505") {
      // 2) 读取现有状态
      const cur = await supabase
        .from("notification_push_deliveries")
        .select("status,sent_at")
        .eq("notification_id", notificationId)
        .eq("token_id", tokenId)
        .maybeSingle();

      const status = cur.data?.status as string | undefined;
      const sentAt = cur.data?.sent_at ? new Date(cur.data.sent_at).getTime() : 0;

      if (status === "sent") {
        return { mode: "enabled" as const, claimed: false, skipped: true, reason: "already_sent" };
      }

      // 3) sending 卡死接管（条件 update，只有一个实例能成功）
      const expiredIso = new Date(Date.now() - SENDING_TTL_MS).toISOString();
      const takeover = await supabase
        .from("notification_push_deliveries")
        .update({ status: "sending", sent_at: nowIso })
        .eq("notification_id", notificationId)
        .eq("token_id", tokenId)
        .eq("status", "sending")
        .lt("sent_at", expiredIso)
        .select("notification_id");

      if (takeover.data && takeover.data.length > 0) {
        return { mode: "enabled" as const, claimed: true, skipped: false, reason: "takeover_stuck_sending" };
      }

      // failed / 正在 sending 未超时：跳过（避免重复推）
      return { mode: "enabled" as const, claimed: false, skipped: true, reason: status ? `duplicate_${status}` : "duplicate_unknown" };
    }

    // 其他插入错误：降级放行（不影响主流程）
    console.error("claimDelivery insert error:", ins.error);
    return { mode: "disabled" as const, claimed: true, skipped: false, reason: "idempotency_error" };
  }

  // 插入成功，拿到发送权
  return { mode: "enabled" as const, claimed: true, skipped: false, reason: "claimed" };
}

async function finishDelivery(
  supabase: any,
  notificationId: string,
  tokenId: string,
  ok: boolean,
  errorText: string | null,
) {
  if (!notificationId || !UUID_RE.test(notificationId)) return;
  await supabase
    .from("notification_push_deliveries")
    .update({
      status: ok ? "sent" : "failed",
      error_message: ok ? null : (errorText ?? "").slice(0, 500),
      sent_at: new Date().toISOString(),
    })
    .eq("notification_id", notificationId)
    .eq("token_id", tokenId);
}

// ================================
// ✅ 主服务
// ================================
Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });
  if (!checkWebhookSecret(req)) return json(401, { error: "Unauthorized" });

  const sbUrl = Deno.env.get("SUPABASE_URL") ?? Deno.env.get("SB_URL");
  const sbServiceKey =
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SB_SERVICE_ROLE_KEY");
  if (!sbUrl || !sbServiceKey) return json(500, { error: "missing_supabase_env" });

  const supabase = createClient(sbUrl, sbServiceKey);

  let payload: Payload;
  try {
    payload = await req.json();
  } catch {
    return json(400, { error: "invalid json" });
  }

  if (!payload?.user_id || !payload?.title || !payload?.body) {
    return json(400, { error: "missing user_id/title/body" });
  }

  // ✅ 脱敏日志
  console.log("send-push", {
    user_id: payload.user_id,
    platform: payload.platform ?? "all",
    message_id: payload.message_id ?? null,
  });

  // 取 tokens
  let q = supabase
    .from("user_fcm_tokens")
    .select("id, fcm_token, platform")
    .eq("user_id", payload.user_id);

  if (payload.platform) q = q.eq("platform", payload.platform);

  const { data: rows, error: qerr } = await q;
  if (qerr) return json(500, { error: "db_error", detail: qerr.message });
  if (!rows || rows.length === 0) return json(200, { ok: true, sent: 0, note: "no tokens" });

  let access_token: string, projectId: string;
  try {
    ({ access_token, projectId } = await getGoogleAccessToken());
  } catch (e) {
    return json(500, { error: "google_auth_failed", detail: String(e) });
  }

  const results: any[] = [];
  const tokenIdsToRemove: string[] = [];

  for (const r of rows) {
    const platformRaw = String(r.platform ?? "").toLowerCase();
    const platform: "ios" | "android" | "unknown" =
      platformRaw === "ios" ? "ios" : platformRaw === "android" ? "android" : "unknown";

    // ✅ 幂等 claim（只有 claimed=true 的实例才发）
    const claim = await claimDelivery(supabase, payload.message_id ?? "", r.id);
    if (claim.skipped) {
      results.push({ token_id: r.id, platform: r.platform, ok: true, status: 200, skipped: true, reason: claim.reason });
      continue;
    }

    const res = await sendFCM(access_token, projectId, r.fcm_token, payload, platform);
    results.push({ token_id: r.id, platform: r.platform, ...res });

    // ✅ 回写 delivery 状态（若幂等启用）
    if (claim.mode === "enabled") {
      await finishDelivery(supabase, payload.message_id ?? "", r.id, res.ok, res.ok ? null : res.text);
    }

    // ✅ token 回收
    if (!res.ok && shouldRemoveTokenFromFCMError(res.text)) {
      tokenIdsToRemove.push(r.id);
    }
  }

  if (tokenIdsToRemove.length > 0) {
    await supabase.from("user_fcm_tokens").delete().in("id", tokenIdsToRemove);
  }

  return json(200, {
    ok: true,
    sent: results.filter((x) => x.ok && !x.skipped).length,
    skipped: results.filter((x) => x.skipped).length,
    removed_tokens: tokenIdsToRemove.length,
    results,
  });
});
