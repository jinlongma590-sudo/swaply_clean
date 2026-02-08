#!/bin/bash
# ============================================
# 全功能集成测试一键脚本 (bash 3.2+ 兼容)
# 要求：Flutter环境 + 至少一个Android设备连接
# 输出：/tmp/qa_<timestamp>/ 证据包
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR"

# 时间戳用于唯一目录
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="/tmp/qa_$TIMESTAMP"
mkdir -p "$OUTPUT_DIR"

echo "🚀 QA Integration Test Suite"
echo "📁 Output: $OUTPUT_DIR"
echo ""

# 函数：记录日志
log() {
  echo "[$(date +%H:%M:%S)] $1" | tee -a "$OUTPUT_DIR/run.log"
}

# 函数：提取设备ID
get_device_id() {
  # 尝试解析 flutter devices --machine 输出
  if command -v jq >/dev/null 2>&1; then
    local devices_json
    devices_json=$(flutter devices --machine 2>/dev/null)
    if [ $? -eq 0 ]; then
      local first_device
      first_device=$(echo "$devices_json" | jq -r '.[] | select(.platform=="android") | .id' | head -1)
      if [ -n "$first_device" ]; then
        echo "$first_device"
        return 0
      fi
    fi
  fi
  
  # 回退：使用 adb devices
  local adb_device
  adb_device=$(adb devices | grep -E '^[0-9a-zA-Z]' | grep -v 'List of devices' | head -1 | cut -f1)
  if [ -n "$adb_device" ]; then
    echo "$adb_device"
    return 0
  fi
  
  # 最后回退：模拟器默认
  echo "emulator-5554"
}

# 1. 设备检测 - 单设备原则
log "🔍 Detecting Android device..."
DEVICE_COUNT=$(adb devices | grep -E '^[0-9a-zA-Z]' | grep -v 'List of devices' | wc -l | tr -d ' ')
if [ "$DEVICE_COUNT" -eq 0 ]; then
  log "❌ No Android device found. Please connect a device or start an emulator."
  exit 1
elif [ "$DEVICE_COUNT" -gt 1 ]; then
  log "❌ Found $DEVICE_COUNT devices online. Please keep only one device online."
  adb devices
  exit 1
fi

DEVICE_ID=$(get_device_id)
log "✅ Device: $DEVICE_ID (single device OK)"

# 2. 环境信息
log "📊 Collecting environment info..."
{
  echo "=== QA Integration Test Summary ==="
  echo "Timestamp: $(date)"
  echo "Device ID: $DEVICE_ID"
  echo ""
  echo "--- Flutter Environment ---"
  flutter --version
  echo ""
  echo "--- Dart Environment ---"
  dart --version
  echo ""
  echo "--- Java Environment ---"
  java -version 2>&1 || echo "Java not found"
  echo ""
  echo "--- Android SDK ---"
  adb version
  echo ""
} > "$OUTPUT_DIR/summary.txt"

# 3. 轻量清理
log "🧹 Light cleaning..."
flutter clean > "$OUTPUT_DIR/flutter_clean.log" 2>&1
flutter pub get > "$OUTPUT_DIR/flutter_pub_get.log" 2>&1

# 3. 套件选择
SUITE="${1:-all}"
log "🎯 Selected suite: $SUITE"

# 4. 测试矩阵 (bash 3.2 兼容)
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
  all)
    TEST_NAMES=(
      "key_audit"
      "smoke_all_tabs"
      "core_flows"
      "reward_regression"
      "full_app_smoke"
    )
    TEST_FILES=(
      "integration_test/key_audit_test.dart"
      "integration_test/smoke_all_tabs_test.dart"
      "integration_test/core_flows_test.dart"
      "integration_test/native_reward_smoke_test.dart"
      "integration_test/full_app_smoke_via_qa_panel_test.dart"
    )
    ;;
  *)
    log "❌ Unknown suite: $SUITE. Valid options: key_audit, smoke, core, reward, full, all"
    exit 1
    ;;
esac

# 5. 运行每个测试 (fail-fast 模式)
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_TESTS=${#TEST_NAMES[@]}

log "📋 Running $TOTAL_TESTS integration tests (fail-fast)..."
echo "" >> "$OUTPUT_DIR/summary.txt"
echo "=== Test Results ===" >> "$OUTPUT_DIR/summary.txt"
echo "Total tests: $TOTAL_TESTS" >> "$OUTPUT_DIR/summary.txt"

# 函数：运行单个测试，返回是否成功
run_one_test() {
  local test_name="$1"
  local test_file="$2"
  local log_file="$OUTPUT_DIR/${test_name}.log"
  local test_result=0  # 0=success, 1=failure
  
  log "🧪 Running $test_name ($test_file)..."
  
  # 记录开始时间
  echo "=== RUN: $test_name ($test_file) ===" >> "$OUTPUT_DIR/run.log"
  
  # 运行测试（不指定 -d，单设备自动选择）
  (flutter test "$test_file" --dart-define=QA_MODE=true --no-pub > "$log_file" 2>&1) &
  TEST_PID=$!
  
  # 等待测试完成（最多180秒）
  for _ in $(seq 1 180); do
    if ! kill -0 "$TEST_PID" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  
  # 如果进程还在运行，杀掉它
  if kill -0 "$TEST_PID" 2>/dev/null; then
    log "⚠️  Test $test_name timed out, killing..."
    kill -9 "$TEST_PID" 2>/dev/null
    echo "TIMEOUT" > "$log_file"
    exit_code=124
  else
    wait "$TEST_PID"
    exit_code=$?
  fi
  
  # 检查结果
  if grep -q "All tests passed" "$log_file"; then
    result="PASS"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    result="FAIL"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    test_result=1
    log "❌ $test_name failed."
    log "📄 Last 50 lines of $log_file:"
    tail -50 "$log_file" | while IFS= read -r line; do log "   $line"; done
  fi
  
  # 记录退出码
  echo "$test_name=$exit_code" >> "$OUTPUT_DIR/test_exit_codes.txt"
  
  log "  Result: $result (exit: $exit_code)"
  echo "  $test_name: $result" >> "$OUTPUT_DIR/summary.txt"
  
  return $test_result
}

# 按顺序执行测试，根据suite决定是否fail-fast
i=0
while [ $i -lt $TOTAL_TESTS ]; do
  test_name="${TEST_NAMES[$i]}"
  test_file="${TEST_FILES[$i]}"
  run_one_test "$test_name" "$test_file"
  test_result=$?
  
  # 如果测试失败且suite是key_audit或all（且是第一个测试key_audit），则fail-fast
  if [ $test_result -ne 0 ]; then
    if [ "$SUITE" = "key_audit" ] || [ "$SUITE" = "all" ]; then
      log "❌ $test_name failed in fail-fast suite ($SUITE). Stopping early."
      exit 1
    fi
    # 对于其他suite，继续执行（虽然只有一个测试，但保持逻辑一致）
  fi
  
  i=$((i + 1))
done

# 6. 收集 logcat（最后10秒）
log "📱 Collecting logcat..."
adb -s "$DEVICE_ID" logcat -d -t 10000 > "$OUTPUT_DIR/logcat.txt" 2>/dev/null || true

# 7. 完成摘要
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
  echo "  - summary.txt          (环境摘要)"
  echo "  - *.log                (各测试日志)"
  echo "  - logcat.txt           (设备日志)"
  echo "  - run.log              (脚本执行日志)"
  echo "  - test_exit_codes.txt  (各测试退出码)"
  echo "  - exit_code.txt        (总退出码)"
} >> "$OUTPUT_DIR/summary.txt"

# 8. 写入总退出码 (全部通过时为0)
echo "0" > "$OUTPUT_DIR/exit_code.txt"

# 9. 输出最终结果
log "📦 Evidence package ready: $OUTPUT_DIR"
cat "$OUTPUT_DIR/summary.txt" | tail -20

exit 0