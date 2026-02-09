#!/bin/bash
# ============================================
# Full Integration Test Runner (bash 3.2+)
# Requires: Flutter + one Android device/emulator ONLINE (state=device)
# Evidence: /tmp/qa_<timestamp>/
# ============================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="/tmp/qa_$TIMESTAMP"
mkdir -p "$OUTPUT_DIR"

echo "🚀 QA Integration Test Suite"
echo "📁 Output: $OUTPUT_DIR"
echo ""

log() {
  echo "[$(date +%H:%M:%S)] $1" | tee -a "$OUTPUT_DIR/run.log"
}

get_device_id() {
  if command -v jq >/dev/null 2>&1; then
    local devices_json
    devices_json=$(flutter devices --machine 2>/dev/null)
    if [ $? -eq 0 ]; then
      local first_device
      first_device=$(echo "$devices_json" | jq -r '.[] | select(.platform=="android") | .id' | head -1)
      if [ -n "$first_device" ] && [ "$first_device" != "null" ]; then
        echo "$first_device"
        return 0
      fi
    fi
  fi

  local adb_device
  adb_device=$(adb devices | awk 'NR>1 && $1!="" {print $1 "\t" $2}' | grep -E '\tdevice$' | head -1 | cut -f1)
  if [ -n "$adb_device" ]; then
    echo "$adb_device"
    return 0
  fi

  echo "emulator-5554"
}

adb_tail_logcat() {
  local out_file="$1"
  local tail_lines="${2:-350}"
  adb -s "$DEVICE_ID" logcat -d -t 1200 2>/dev/null | tail -n "$tail_lines" > "$out_file" || true
}

# ========= 0) Require credentials =========
QA_EMAIL_ENV="${QA_EMAIL:-}"
QA_PASS_ENV="${QA_PASS:-}"

if [ -z "$QA_EMAIL_ENV" ] || [ -z "$QA_PASS_ENV" ]; then
  log "❌ Missing QA credentials. Please set env vars: QA_EMAIL and QA_PASS"
  log "   Example: QA_EMAIL='xxx@gmail.com' QA_PASS='***' ./tool/qa/run_all_integration.sh smoke"
  exit 3
fi

# 1) Single ONLINE device only (state=device)
log "🔍 Detecting Android device..."
DEVICE_ONLINE_COUNT=$(adb devices | awk 'NR>1 && $1!="" {print $2}' | grep -c '^device$' | tr -d ' ')
if [ "$DEVICE_ONLINE_COUNT" -eq 0 ]; then
  log "❌ No ONLINE Android device found (state=device)."
  adb devices || true
  exit 1
elif [ "$DEVICE_ONLINE_COUNT" -gt 1 ]; then
  log "❌ Found $DEVICE_ONLINE_COUNT devices online. Please keep only one device online."
  adb devices || true
  exit 1
fi

DEVICE_ID=$(get_device_id)
log "✅ Device: $DEVICE_ID (single device OK)"

# 2) Environment info
log "📊 Collecting environment info..."
{
  echo "=== QA Integration Test Summary ==="
  echo "Timestamp: $(date)"
  echo "Device ID: $DEVICE_ID"
  echo ""
  echo "--- Flutter ---"
  flutter --version
  echo ""
  echo "--- Dart ---"
  dart --version
  echo ""
  echo "--- Java ---"
  java -version 2>&1 || echo "Java not found"
  echo ""
  echo "--- Android SDK ---"
  adb version
  echo ""
  echo "--- QA ENV ---"
  echo "QA_EMAIL: ${QA_EMAIL_ENV%%@*}@***"
  echo "QA_PASS: (set)"
  echo ""
} > "$OUTPUT_DIR/summary.txt"

# 3) Clean + pub get
log "🧹 Light cleaning..."
flutter clean > "$OUTPUT_DIR/flutter_clean.log" 2>&1 || true
flutter pub get > "$OUTPUT_DIR/flutter_pub_get.log" 2>&1

# 4) Suite select
SUITE="${1:-smoke}"

case "$SUITE" in
  key_audit|smoke|core|reward|full|deeplink|real_publish|invite|deep_full|all) ;;
  *)
    log "❌ Unknown suite: $SUITE. Valid options: key_audit, smoke, core, reward, full, deeplink, real_publish, invite, deep_full, all"
    exit 1
    ;;
esac

log "🎯 Selected suite: $SUITE"

# 5) Test matrix
declare -a TEST_NAMES
declare -a TEST_FILES

case "$SUITE" in
  key_audit)
    TEST_NAMES=("key_audit")
    TEST_FILES=("integration_test/key_audit_test.dart")
    ;;
  smoke)
    TEST_NAMES=("smoke_all_tabs")
    TEST_FILES=("integration_test/smoke_all_tabs_test.dart")
    ;;
  core)
    TEST_NAMES=("core_flows")
    TEST_FILES=("integration_test/core_flows_test.dart")
    ;;
  reward)
    TEST_NAMES=("reward_regression")
    TEST_FILES=("integration_test/native_reward_smoke_test.dart")
    ;;
  full)
    TEST_NAMES=("full_app_smoke")
    TEST_FILES=("integration_test/full_app_smoke_via_qa_panel_test.dart")
    ;;
  deeplink)
    TEST_NAMES=("deeplink_test")
    TEST_FILES=("integration_test/deeplink_test.dart")
    ;;
  real_publish)
    TEST_NAMES=("real_publish_test")
    TEST_FILES=("integration_test/real_publish_test.dart")
    ;;
  invite)
    TEST_NAMES=("invite_flow_test")
    TEST_FILES=("integration_test/invite_flow_test.dart")
    ;;
  deep_full)
    TEST_NAMES=(
      "smoke_all_tabs"
      "core_flows"
      "reward_regression"
      "full_app_smoke"
      "deeplink_test"
      "real_publish_test"
      "invite_flow_test"
    )
    TEST_FILES=(
      "integration_test/smoke_all_tabs_test.dart"
      "integration_test/core_flows_test.dart"
      "integration_test/native_reward_smoke_test.dart"
      "integration_test/full_app_smoke_via_qa_panel_test.dart"
      "integration_test/deeplink_test.dart"
      "integration_test/real_publish_test.dart"
      "integration_test/invite_flow_test.dart"
    )
    ;;
  all)
    TEST_NAMES=(
      "key_audit"
      "smoke_all_tabs"
      "core_flows"
      "reward_regression"
      "full_app_smoke"
      "deeplink_test"
      "real_publish_test"
      "invite_flow_test"
    )
    TEST_FILES=(
      "integration_test/key_audit_test.dart"
      "integration_test/smoke_all_tabs_test.dart"
      "integration_test/core_flows_test.dart"
      "integration_test/native_reward_smoke_test.dart"
      "integration_test/full_app_smoke_via_qa_panel_test.dart"
      "integration_test/deeplink_test.dart"
      "integration_test/real_publish_test.dart"
      "integration_test/invite_flow_test.dart"
    )
    ;;
esac

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_TESTS=${#TEST_NAMES[@]}

log "📋 Running $TOTAL_TESTS integration tests (fail-fast for suite=all/key_audit)..."
echo "" >> "$OUTPUT_DIR/summary.txt"
echo "=== Test Results ===" >> "$OUTPUT_DIR/summary.txt"
echo "Total tests: $TOTAL_TESTS" >> "$OUTPUT_DIR/summary.txt"

DART_DEFINES=(
  "--dart-define=QA_MODE=true"
  "--dart-define=QA_EMAIL=$QA_EMAIL_ENV"
  "--dart-define=QA_PASS=$QA_PASS_ENV"
)

run_one_test() {
  local test_name="$1"
  local test_file="$2"
  local log_file="$OUTPUT_DIR/${test_name}.log"
  local test_result=0

  log "🧪 Running $test_name ($test_file)..."
  echo "=== RUN: $test_name ($test_file) ===" >> "$OUTPUT_DIR/run.log"

  case "$test_name" in
    key_audit)         timeout_seconds=1200 ;;  # 20m
    smoke_all_tabs)    timeout_seconds=900 ;;   # 15m
    core_flows)        timeout_seconds=1500 ;;  # 25m
    reward_regression) timeout_seconds=900 ;;   # 15m
    full_app_smoke)    timeout_seconds=1800 ;;  # 30m
    deeplink_test)     timeout_seconds=900 ;;   # 15m
    real_publish_test) timeout_seconds=2400 ;;  # 40m
    invite_flow_test)  timeout_seconds=1500 ;;  # 25m
    *)                 timeout_seconds=900 ;;
  esac

  log "⏱️  Timeout set to ${timeout_seconds}s for $test_name"

  # ✅ TRUE fail-fast + TRUE timeout (no background PID polling)
  # exit_code:
  #   0   pass
  #   124 timeout (from coreutils timeout)
  #   else fail
  timeout "${timeout_seconds}s" flutter test "$test_file" "${DART_DEFINES[@]}" -r expanded > "$log_file" 2>&1
  exit_code=$?

  # Always collect a small tail logcat for each test (helps debug even when pass)
  adb_tail_logcat "$OUTPUT_DIR/${test_name}_logcat_tail.txt" 220

  if [ "$exit_code" -eq 0 ]; then
    result="PASS"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    result="FAIL"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    test_result=1

    if [ "$exit_code" -eq 124 ]; then
      log "⚠️  Test $test_name timed out after ${timeout_seconds}s"
      adb_tail_logcat "$OUTPUT_DIR/${test_name}_logcat_timeout.txt" 350
      echo "" >> "$log_file"
      echo "TIMEOUT after ${timeout_seconds}s" >> "$log_file"
    else
      log "❌ $test_name failed (exit=$exit_code)."
      adb_tail_logcat "$OUTPUT_DIR/${test_name}_logcat_failure.txt" 350
    fi

    log "📄 Last 160 lines of $log_file:"
    tail -160 "$log_file" | while IFS= read -r line; do log "   $line"; done
  fi

  echo "$test_name=$exit_code" >> "$OUTPUT_DIR/test_exit_codes.txt"
  log "  Result: $result (exit: $exit_code)"
  echo "  $test_name: $result (exit=$exit_code)" >> "$OUTPUT_DIR/summary.txt"

  return $test_result
}

i=0
while [ $i -lt $TOTAL_TESTS ]; do
  test_name="${TEST_NAMES[$i]}"
  test_file="${TEST_FILES[$i]}"

  run_one_test "$test_name" "$test_file"
  test_result=$?

  # fail-fast only for suite=key_audit or suite=all
  if [ $test_result -ne 0 ]; then
    if [ "$SUITE" = "key_audit" ] || [ "$SUITE" = "all" ]; then
      log "❌ $test_name failed in fail-fast suite ($SUITE). Stopping early."
      echo "1" > "$OUTPUT_DIR/exit_code.txt"
      exit 1
    fi
  fi

  i=$((i + 1))
done

# final full logcat
log "📱 Collecting full logcat..."
adb -s "$DEVICE_ID" logcat -d -t 30000 > "$OUTPUT_DIR/logcat.txt" 2>/dev/null || true

{
  echo ""
  echo "Passed: $PASS_COUNT"
  echo "Failed: $FAIL_COUNT"
  echo ""
  if [ $FAIL_COUNT -eq 0 ]; then
    echo "✅ ALL TESTS PASSED"
  else
    echo "❌ SOME TESTS FAILED"
  fi
  echo ""
  echo "Evidence package: $OUTPUT_DIR"
  echo "  - summary.txt"
  echo "  - *.log"
  echo "  - *_logcat_*.txt"
  echo "  - logcat.txt"
  echo "  - run.log"
  echo "  - test_exit_codes.txt"
  echo "  - exit_code.txt"
} >> "$OUTPUT_DIR/summary.txt"

if [ $FAIL_COUNT -eq 0 ]; then
  echo "0" > "$OUTPUT_DIR/exit_code.txt"
  log "📦 Evidence package ready: $OUTPUT_DIR"
  tail -20 "$OUTPUT_DIR/summary.txt"
  exit 0
else
  echo "1" > "$OUTPUT_DIR/exit_code.txt"
  log "📦 Evidence package ready: $OUTPUT_DIR"
  tail -20 "$OUTPUT_DIR/summary.txt"
  exit 1
fi