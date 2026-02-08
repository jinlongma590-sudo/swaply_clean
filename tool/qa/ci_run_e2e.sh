#!/usr/bin/env bash
set -euo pipefail

echo "✅ [ci_run_e2e] Emulator booted, devices:"
adb start-server >/dev/null 2>&1 || true
adb devices -l || true

echo "⏳ [ci_run_e2e] Waiting for device..."
adb wait-for-device || true

# 等系统真正 ready（避免偶发 offline/半启动）
echo "⏳ [ci_run_e2e] Waiting for sys.boot_completed=1 ..."
BOOT_OK="0"
for i in $(seq 1 90); do
  BOOT="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
  if [[ "$BOOT" == "1" ]]; then
    BOOT_OK="1"
    echo "✅ [ci_run_e2e] boot_completed=1"
    break
  fi
  sleep 2
done

if [[ "$BOOT_OK" != "1" ]]; then
  echo "⚠️ [ci_run_e2e] boot_completed not reached, continue anyway (best effort)"
fi

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

# ✅ 关键：先预热 Debug APK 构建（避免 integration test 阶段卡 assembleDebug 直到超时）
echo "🔥 [ci_run_e2e] Prebuilding debug APK to warm Gradle/Flutter..."
flutter --version
flutter pub get
flutter clean || true

# 预热构建（这一步可能慢，但它会输出详细进度，并且不会被你 run_all 的 6min/15min kill）
flutter build apk --debug -v

echo "✅ [ci_run_e2e] Prebuild done. Start integration suite..."
./tool/qa/run_all_integration.sh "$SUITE"