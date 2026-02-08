import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:swaply/main.dart' as app;
import 'package:swaply/core/qa_keys.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> safeSettle(
      WidgetTester tester, {
        Duration step = const Duration(milliseconds: 120),
        int maxAttempts = 60,
      }) async {
    for (int i = 0; i < maxAttempts; i++) {
      await tester.pump(step);
      if (!binding.hasScheduledFrame) return;
    }
    // ignore: avoid_print
    print(
      '[safeSettle] still busy after ${maxAttempts * step.inMilliseconds}ms, continue',
    );
  }

  Future<bool> waitForKey(
      WidgetTester tester,
      String key, {
        Duration timeout = const Duration(seconds: 30),
        Duration step = const Duration(milliseconds: 250),
      }) async {
    final finder = find.byKey(Key(key));
    final endTime = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(endTime)) {
      await tester.pump(step);
      if (finder.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  Future<bool> waitForAny(
      WidgetTester tester,
      List<Finder> finders, {
        Duration timeout = const Duration(seconds: 30),
        Duration step = const Duration(milliseconds: 250),
      }) async {
    final endTime = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(endTime)) {
      await tester.pump(step);
      for (final f in finders) {
        if (f.evaluate().isNotEmpty) return true;
      }
    }
    return false;
  }

  Future<void> scrollUntilVisible(
      WidgetTester tester,
      Finder finder,
      double delta, {
        int maxScrolls = 80,
      }) async {
    // 兼容 Column/SingleChildScrollView/ListView：优先找一个可滚动的
    final scrollable = find.byType(Scrollable);
    for (int i = 0; i < maxScrolls; i++) {
      if (finder.evaluate().isNotEmpty) return;
      if (scrollable.evaluate().isEmpty) break;
      await tester.drag(scrollable.first, Offset(0, -delta));
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('Full App Smoke via QA Panel', (tester) async {
    // 1) 冷启动 App
    app.main();
    await tester.pump(const Duration(milliseconds: 300));
    await safeSettle(tester);

    // 2) Welcome Screen → Guest
    print('🔍 Checking WelcomeScreen...');
    final welcomeGuestBtn = find.byKey(Key(QaKeys.welcomeGuestBtn));
    if (welcomeGuestBtn.evaluate().isNotEmpty) {
      print('✅ Found welcome_guest_btn, tapping to enter guest mode');
      await tester.tap(welcomeGuestBtn.first);
      await tester.pump(const Duration(milliseconds: 800));
      await safeSettle(tester);

      // 处理可能的对话框：优先 key / 其次 text
      final continueKeyBtn = find.byKey(Key(QaKeys.welcomeContinueBtn));
      final continueTextBtn = find.text('Continue');

      final hasDialog = await waitForAny(
        tester,
        [continueKeyBtn, continueTextBtn],
        timeout: const Duration(seconds: 12),
      );

      if (hasDialog) {
        if (continueKeyBtn.evaluate().isNotEmpty) {
          print('✅ Found Continue button (key), tapping');
          await tester.tap(continueKeyBtn.first);
        } else if (continueTextBtn.evaluate().isNotEmpty) {
          print('✅ Found Continue button (text), tapping');
          await tester.tap(continueTextBtn.first);
        }
        await tester.pump(const Duration(milliseconds: 800));
        await safeSettle(tester);
      }
    } else {
      print('ℹ️ Already past WelcomeScreen');
    }

    // 3) 等待 MainNavigationPage 加载并点击 qa_fab
    print('🔍 Waiting for qa_fab...');
    final qaFab = find.byKey(Key(QaKeys.qaFab));

    final fabOk = await waitForAny(
      tester,
      [qaFab],
      timeout: const Duration(seconds: 40),
    );
    if (!fabOk) {
      debugDumpApp();
      fail('qa_fab not visible. Ensure QA_MODE=true and FAB is rendered.');
    }

    await tester.tap(qaFab.first);
    await tester.pump(const Duration(milliseconds: 500));
    await safeSettle(tester);

    // 4) 验证 QA Panel 打开
    print('🔍 Verifying QA Panel opened...');
    final qaPanelAppBar = find.text('QA Panel');

    final panelOk = await waitForAny(
      tester,
      [qaPanelAppBar],
      timeout: const Duration(seconds: 10),
    );
    if (!panelOk) {
      debugDumpApp();
      fail('QA Panel not opened after tapping qa_fab');
    }

    // 5) 功能按钮映射：按钮Key -> 页面根Key（用于断言页面打开）
    final Map<String, String?> buttonToPageRoot = {
      QaKeys.qaNavHome: QaKeys.pageHomeRoot,
      QaKeys.qaNavSearchResults: QaKeys.searchResultsRoot,
      QaKeys.qaNavCategoryProducts: QaKeys.listingGrid,
      QaKeys.qaNavProductDetail: QaKeys.listingDetailRoot,
      QaKeys.qaNavSavedList: QaKeys.savedListRoot,
      QaKeys.qaNavNotifications: QaKeys.pageNotificationsRoot,
      QaKeys.qaNavProfile: QaKeys.pageProfileRoot,
      QaKeys.qaNavRewardCenter: QaKeys.rewardCenterRulesCard, // 规则卡片作为标识
      QaKeys.qaNavRules: QaKeys.rewardRulesTitle,
    };

    // 不导航到独立页面，仅验证按钮存在
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
    final int total = buttonToPageRoot.length + standaloneButtons.length;

    // 6) 遍历所有导航按钮
    for (final entry in buttonToPageRoot.entries) {
      final buttonKey = entry.key;
      final pageRootKey = entry.value;

      print('🧪 Testing button: $buttonKey -> $pageRootKey');

      final buttonFinder = find.byKey(Key(buttonKey));
      await scrollUntilVisible(tester, buttonFinder, 60);

      if (buttonFinder.evaluate().isEmpty) {
        debugDumpApp();
        fail('Button $buttonKey should exist in QA Panel');
      }

      await tester.tap(buttonFinder.first);
      await tester.pump(const Duration(milliseconds: 500));
      await safeSettle(tester, maxAttempts: 80);

      // ✅ 验证页面根 Key（如果提供了）
      if (pageRootKey != null) {
        final ok = await waitForKey(
          tester,
          pageRootKey,
          timeout: const Duration(seconds: 15),
        );

        if (!ok) {
          debugDumpApp();
          fail('Page root key $pageRootKey should appear after tapping $buttonKey');
        }
        print('✅ Page $pageRootKey opened successfully');
      }

      // 返回 QA Panel
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 500));
      await safeSettle(tester);

      // 确保回到 QA Panel
      final backOk = await waitForAny(
        tester,
        [find.text('QA Panel')],
        timeout: const Duration(seconds: 10),
      );
      if (!backOk) {
        debugDumpApp();
        fail('Should be back in QA Panel after pageBack() from $buttonKey');
      }

      passed++;
    }

    // 7) 验证独立按钮存在（不导航）
    for (final buttonKey in standaloneButtons) {
      print('🧪 Verifying standalone button: $buttonKey');
      final buttonFinder = find.byKey(Key(buttonKey));
      await scrollUntilVisible(tester, buttonFinder, 60);

      if (buttonFinder.evaluate().isEmpty) {
        debugDumpApp();
        fail('Button $buttonKey should exist in QA Panel');
      }
      passed++;
    }

    print('✅ Full App Smoke passed: $passed/$total checks');
    expect(passed, total, reason: 'All buttons should be tested');
  });
}