#!/usr/bin/env bash
set -euo pipefail

echo "✅ [ci_run_e2e] Emulator booted, devices:"
adb start-server >/dev/null 2>&1 || true
adb devices -l || true

# 防止偶发 adb offline：等一等 device ready
echo "⏳ [ci_run_e2e] Waiting for device..."
adb wait-for-device || true

# suite：workflow_dispatch 有输入就用输入；push/PR 没输入就 smoke
SUITE="${SUITE_INPUT:-}"
if [[ -z "$SUITE" ]]; then
  SUITE="smoke"
fi
echo "🚀 [ci_run_e2e] Running suite=$SUITE"

# 可选：Gradle stop（存在才执行，避免 not found）
if [[ -f "./android/gradlew" ]]; then
  chmod +x ./android/gradlew || true
  (cd android && ./gradlew --stop) || true
fi

chmod +x ./tool/qa/run_all_integration.sh
./tool/qa/run_all_integration.sh "$SUITE"