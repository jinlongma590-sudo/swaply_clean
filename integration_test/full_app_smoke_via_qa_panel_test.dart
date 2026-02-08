import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:swaply/main.dart' as app;
import 'package:swaply/core/qa_keys.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  // 安全的 pumpAndSettle（有限超时，避免卡死）
  Future<void> safeSettle(WidgetTester tester,
      {Duration step = const Duration(milliseconds: 100),
      int maxAttempts = 50}) async {
    for (int i = 0; i < maxAttempts; i++) {
      await tester.pump(step);
      if (!binding.hasScheduledFrame) {
        return;
      }
    }
    // 超时：dump widget tree 帮助调试
    debugDumpApp();
    fail('safeSettle timed out after ${maxAttempts * step.inMilliseconds}ms');
  }

  // 辅助函数：等待特定Key出现
  Future<bool> waitForKey(WidgetTester tester, String key,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final finder = find.byKey(Key(key));
    final endTime = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(endTime)) {
      await tester.pump(const Duration(milliseconds: 500));
      if (finder.evaluate().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  testWidgets('Full App Smoke via QA Panel', (tester) async {
    // 1) 冷启动 App
    app.main();
    await tester.pump(const Duration(milliseconds: 300));
    await safeSettle(tester);

    // 2) Welcome Screen → Guest 流程
    print('🔍 Checking WelcomeScreen...');
    final welcomeGuestBtn = find.byKey(Key(QaKeys.welcomeGuestBtn));
    if (welcomeGuestBtn.evaluate().isNotEmpty) {
      print('✅ Found welcome_guest_btn, tapping to enter guest mode');
      await tester.tap(welcomeGuestBtn);
      await safeSettle(tester);
      // 处理可能的对话框 "Guest Mode"
      final continueBtn = find.text('Continue');
      if (continueBtn.evaluate().isNotEmpty) {
        print('✅ Found Continue button in dialog, tapping');
        await tester.tap(continueBtn);
        await safeSettle(tester);
      }
    } else {
      print('ℹ️ Already past WelcomeScreen');
    }

    // 3) 等待 MainNavigationPage 加载并点击 qa_fab
    print('🔍 Waiting for qa_fab...');
    final qaFab = find.byKey(Key(QaKeys.qaFab));
    expect(qaFab, findsOneWidget, reason: 'qa_fab should be visible in QA_MODE');
    await tester.tap(qaFab);
    await safeSettle(tester);

    // 4) 验证 QA Panel 打开
    print('🔍 Verifying QA Panel opened...');
    final qaPanelAppBar = find.text('QA Panel');
    expect(qaPanelAppBar, findsOneWidget, reason: 'QA Panel should be open');

    // 5) 功能按钮映射：按钮Key -> 页面根Key（用于断言页面打开）
    final Map<String, String?> buttonToPageRoot = {
      QaKeys.qaNavHome: QaKeys.pageHomeRoot,
      QaKeys.qaNavSearchResults: QaKeys.searchResultsRoot,
      QaKeys.qaNavCategoryProducts: QaKeys.listingGrid,
      QaKeys.qaNavProductDetail: QaKeys.listingDetailRoot,
      QaKeys.qaNavSavedList: QaKeys.savedListRoot,
      QaKeys.qaNavNotifications: QaKeys.pageNotificationsRoot,
      QaKeys.qaNavProfile: QaKeys.pageProfileRoot,
      QaKeys.qaNavRewardCenter: QaKeys.rewardCenterRulesCard, // 使用规则卡片作为页面标识
      QaKeys.qaNavRules: QaKeys.rewardRulesTitle,
    };
    // 以下按钮不导航到独立页面，仅验证按钮存在
    final List<String> standaloneButtons = [
      QaKeys.qaNavFavoriteToggle,
      QaKeys.qaNavSellMockPublish,
      QaKeys.qaOpenRewardBottomSheet,
      QaKeys.qaSeedPoolMock,
      QaKeys.qaQuickPublish,
      QaKeys.qaSmokeOpenTabs,
      QaKeys.qaDebugLog,
    ];

    int passed = 0;
    int total = buttonToPageRoot.length + standaloneButtons.length;

    // 6) 遍历所有功能按钮
    for (final entry in buttonToPageRoot.entries) {
      final buttonKey = entry.key;
      final pageRootKey = entry.value;
      print('🧪 Testing button: $buttonKey -> $pageRootKey');
      
      // 查找按钮（滚动到视图中）
      final buttonFinder = find.byKey(Key(buttonKey));
      await scrollUntilVisible(tester, buttonFinder, 50);
      expect(buttonFinder, findsOneWidget, reason: 'Button $buttonKey should exist in QA Panel');
      
      // 点击按钮
      await tester.tap(buttonFinder);
      await safeSettle(tester, maxAttempts: 80); // 给页面加载更多时间
      
      // 验证页面根Key存在（如果提供了）
      if (pageRootKey != null) {
        final pageRootFinder = find.byKey(Key(pageRootKey));
        final found = await waitForKey(tester, pageRootKey, timeout: Duration(seconds: 10));
        expect(found, isTrue, reason: 'Page root key $pageRootKey should appear after tapping $buttonKey');
        print('✅ Page $pageRootKey opened successfully');
      }
      
      // 返回 QA Panel（点击返回按钮或系统返回）
      await tester.pageBack();
      await safeSettle(tester);
      
      // 确保回到 QA Panel
      expect(find.text('QA Panel'), findsOneWidget, reason: 'Should be back in QA Panel');
      passed++;
    }

    // 7) 验证独立按钮存在（不导航）
    for (final buttonKey in standaloneButtons) {
      print('🧪 Verifying standalone button: $buttonKey');
      final buttonFinder = find.byKey(Key(buttonKey));
      await scrollUntilVisible(tester, buttonFinder, 50);
      expect(buttonFinder, findsOneWidget, reason: 'Button $buttonKey should exist in QA Panel');
      passed++;
    }

    // 8) 完成
    print('✅ Full App Smoke passed: $passed/$total checks');
    expect(passed, total, reason: 'All buttons should be tested');
  });

  // 滚动直到控件可见（从 Flutter 测试工具复制）
  Future<void> scrollUntilVisible(
    WidgetTester tester,
    Finder finder,
    double delta,
  ) async {
    while (finder.evaluate().isEmpty) {
      await tester.drag(find.byType(ListView), Offset(0, -delta));
      await tester.pump();
    }
  }
}