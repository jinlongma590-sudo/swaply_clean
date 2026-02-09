#!/bin/bash
set -e

echo "🚀 Swaply Native Integration Test (QA_MODE=true)"
echo "=================================================="

# Use running emulator
DEVICE_ID="emulator-5554"
DEVICE_NAME="Android Emulator"
echo "📱 设备选择: $DEVICE_NAME ($DEVICE_ID)"

# Clean & deps (optional)
if [ "${1:-}" != "--no-clean" ]; then
    echo "📦 清理并获取依赖..."
    flutter clean
    flutter pub get
fi

# Analyze
echo "🔍 静态分析..."
if ! flutter analyze --no-fatal-infos; then
    echo "⚠️  flutter analyze 发现警告（继续执行）"
fi

# Run native integration test
echo "🧪 运行原生 integration_test..."
TEST_FILE="integration_test/native_reward_smoke_test.dart"
if [ ! -f "$TEST_FILE" ]; then
    echo "❌ 测试文件不存在: $TEST_FILE"
    exit 1
fi

echo "   执行: flutter test -d \"$DEVICE_ID\" $TEST_FILE --dart-define=QA_MODE=true -r expanded"
if ! flutter test -d "$DEVICE_ID" "$TEST_FILE" --dart-define=QA_MODE=true -r expanded; then
    echo "❌ Native integration test 失败"
    exit 1
fi

echo "✅ Native integration test 通过！"
echo ""
echo "📊 测试完成："
echo "   - 设备: $DEVICE_NAME"
echo "   - 测试文件: $TEST_FILE"
echo "   - QA_MODE: true"
echo ""
echo "🎉 原生集成测试能力已验证！"