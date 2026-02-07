#!/usr/bin/env bash
set -euo pipefail

FILE="supabase/functions/rpc-proxy/index.ts"

echo "🔍 Checking rpc-proxy allowlist hardening..."

# 1) 必须存在 ALLOWED_ACTIONS 常量
if ! rg -n "const ALLOWED_ACTIONS\\s*=\\s*\\[" "$FILE" >/dev/null 2>&1; then
    echo "❌ ALLOWED_ACTIONS constant not found in $FILE"
    exit 1
fi

# 2) 必须存在 unknown action 拒绝
if ! rg -n "Action '\\$\\{action\\}' is not allowed|is not allowed" "$FILE" >/dev/null 2>&1; then
    echo "❌ No 'action not allowed' check found in $FILE"
    exit 1
fi

# 3) 允许在严格 allowlist 检查后的通用 rpc 调用（已通过 ALLOWED_ACTIONS 验证）
# 检查是否存在 allowlist 验证
if ! rg -n "ALLOWED_ACTIONS\\.includes\\(action\\)" "$FILE" >/dev/null 2>&1; then
    echo "❌ Missing ALLOWED_ACTIONS.includes(action) check before rpc call"
    exit 1
fi

# 4) 必须存在 ANON_ACTIONS 或 AUTH_ACTIONS 分级
if ! rg -n "ANON_ACTIONS.*=|AUTH_ACTIONS.*=" "$FILE" >/dev/null 2>&1; then
    echo "❌ Missing auth level constants (ANON_ACTIONS/AUTH_ACTIONS)"
    exit 1
fi

# 5) 必须存在强制用户绑定逻辑
if ! rg -n "p_user.*=.*user\\.id|p_invitee.*=.*user\\.id|p_inviter.*=.*user\\.id|sender_id.*=.*user\\.id|user_id.*=.*user\\.id" "$FILE" >/dev/null 2>&1; then
    echo "❌ Missing forced user identity binding patterns"
    exit 1
fi

# 6) 必须存在结构化日志 (tag: "rpc_proxy")
if ! rg -n 'tag.*:.*"rpc_proxy"' "$FILE" >/dev/null 2>&1; then
    echo "❌ Missing structured logging with tag 'rpc_proxy'"
    exit 1
fi

echo "✅ rpc-proxy allowlist guard ok"
echo "✅ All security checks passed"