#!/usr/bin/env bash
set -euo pipefail

echo "✅ [ci_run_e2e] Bootstrapping ADB..."
adb start-server >/dev/null 2>&1 || true

print_devices() {
  echo "🔎 [ci_run_e2e] adb devices -l:"
  adb devices -l || true
}

adb_self_heal() {
  local out
  out="$(adb devices 2>/dev/null || true)"

  if echo "$out" | grep -q "offline"; then
    echo "⚠️ [ci_run_e2e] Detected device offline. Restarting adb..."
    adb kill-server || true
    sleep 2
    adb start-server || true
    sleep 2
  fi

  if echo "$out" | grep -q "unauthorized"; then
    echo "⚠️ [ci_run_e2e] Detected device unauthorized. Restarting adb (best-effort)..."
    adb kill-server || true
    sleep 2
    adb start-server || true
    sleep 2
  fi
}

print_devices
adb_self_heal
print_devices

echo "⏳ [ci_run_e2e] Waiting for device..."
adb wait-for-device || true

echo "⏳ [ci_run_e2e] Waiting for emulator to be fully ready..."
READY="0"
for i in $(seq 1 120); do
  adb_self_heal

  BOOT1="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
  BOOT2="$(adb shell getprop dev.bootcomplete 2>/dev/null | tr -d '\r' || true)"
  BOOTANIM="$(adb shell getprop init.svc.bootanim 2>/dev/null | tr -d '\r' || true)"

  if [[ "$BOOT1" == "1" && "$BOOT2" == "1" && "$BOOTANIM" == "stopped" ]]; then
    READY="1"
    echo "✅ [ci_run_e2e] Emulator ready (sys.boot_completed=1, dev.bootcomplete=1, bootanim=stopped)"
    break
  fi

  if (( i % 10 == 0 )); then
    echo "… [ci_run_e2e] still waiting (attempt=$i) sys=$BOOT1 dev=$BOOT2 bootanim=$BOOTANIM"
    print_devices
  fi

  sleep 2
done

if [[ "$READY" != "1" ]]; then
  echo "⚠️ [ci_run_e2e] Emulator readiness not fully confirmed, continue anyway (best effort)"
  print_devices
fi

# suite：workflow_dispatch 有输入就用输入；push/PR 没输入就 smoke
SUITE="${SUITE_INPUT:-}"
if [[ -z "$SUITE" ]]; then
  SUITE="smoke"
fi
echo "🚀 [ci_run_e2e] Running suite=$SUITE"

# Gradle stop（存在才执行）
if [[ -f "./android/gradlew" ]]; then
  chmod +x ./android/gradlew || true
  (cd android && ./gradlew --stop) || true
fi

chmod +x ./tool/qa/run_all_integration.sh

echo "🔥 [ci_run_e2e] Prebuilding debug APK to warm Gradle/Flutter..."
flutter --version
flutter pub get
flutter clean || true

# 预热构建（可能较慢，但避免 integration 阶段 assembleDebug 卡住导致误判/超时）
flutter build apk --debug -v

echo "✅ [ci_run_e2e] Prebuild done. Start integration suite..."
./tool/qa/run_all_integration.sh "$SUITE"