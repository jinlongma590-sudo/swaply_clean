#!/usr/bin/env bash
set -euo pipefail
cd ~/swaply_clean

echo "==[0] Environment info =="
flutter --version
dart --version
flutter devices
echo ""

echo "==[1] Fixed device selection =="
DEV="emulator-5554"
echo "✅ Device: $DEV"

TS="$(date +%Y%m%d_%H%M%S)"
OUT="/tmp/qa_${TS}"
mkdir -p "$OUT"

echo "==[2] Clean lightweight (no flutter test, no patrol) =="
flutter clean > "$OUT/flutter_clean.log" 2>&1 || true
flutter pub get > "$OUT/flutter_pub_get.log" 2>&1

echo "==[3] Run ONLY integration_test (native) =="
TEST_FILE="integration_test/native_reward_smoke_test.dart"
if [ ! -f "$TEST_FILE" ]; then
  echo "❌ Missing: $TEST_FILE"
  ls -la integration_test || true
  exit 1
fi

set +e
flutter test -d "$DEV" "$TEST_FILE" \
  --dart-define=QA_MODE=true \
  -r expanded \
  --timeout 15m \
  2>&1 | tee "$OUT/integration_test.log"
RC=${PIPESTATUS[0]}
set -e

echo "EXIT_CODE=$RC" | tee "$OUT/exit_code.txt"

echo "==[4] Collect evidence (logs + logcat scan) =="
adb logcat -d > "$OUT/logcat_full.txt" 2>&1 || true
grep -nE "RenderFlex|overflowed|EXCEPTION|FATAL|CRASH" "$OUT/logcat_full.txt" > "$OUT/logcat_keyfinds.txt" 2>&1 || true

echo "==[5] Summary =="
echo "ExitCode: $RC" | tee "$OUT/summary.txt"
echo "Artifacts: $OUT" | tee -a "$OUT/summary.txt"

echo ""
echo "========== RESULT =========="
cat "$OUT/summary.txt"
echo "============================"

if [ "$RC" -ne 0 ]; then
  echo "❌ integration_test FAILED. Open logs:"
  echo "  $OUT/integration_test.log"
  echo "  $OUT/logcat_keyfinds.txt"
  exit "$RC"
else
  echo "✅ integration_test PASSED."
fi