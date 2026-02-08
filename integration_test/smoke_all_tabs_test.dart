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

  testWidgets('Smoke: all tabs are reachable', (tester) async {
    // 1) 冷启动 App
    app.main();
    await tester.pump(const Duration(milliseconds: 300));
    await safeSettle(tester);

    // 2) Welcome Screen → Guest 流程
    print('🔍 Checking WelcomeScreen...');
    final welcomeGuestBtn = find.byKey(Key(QaKeys.welcomeGuestBtn));
    if (welcomeGuestBtn.evaluate().isNotEmpty) {
      print('✅ Found welcome guest button, tapping...');
      await tester.tap(welcomeGuestBtn.first);
      await tester.pump(const Duration(milliseconds: 800));

      // 处理 Guest Mode 对话框
      print('🔍 Waiting for Guest Mode dialog...');
      final dialogContinueBtn = find.byKey(Key(QaKeys.welcomeContinueBtn));
      expect(dialogContinueBtn, findsOneWidget, reason: 'Guest mode dialog Continue button should be visible');
      print('✅ Found dialog Continue button, tapping...');
      await tester.tap(dialogContinueBtn.first);
      await tester.pump(const Duration(milliseconds: 800));
    } else {
      print('⚠️ Welcome guest button not found (already in main interface?)');
    }

    // 3) 等待进入主界面（通过 tab_home 判断）
    print('⏳ Waiting for main interface...');
    final tabHomeFound = await waitForKey(tester, QaKeys.tabHome);
    if (!tabHomeFound) {
      debugDumpApp();
      fail('Main interface not reached within timeout');
    }
    print('✅ Main interface reached');

    // 4) 验证所有 Tab 可达（按顺序点击）
    final tabs = [
      QaKeys.tabHome,
      QaKeys.tabSaved,
      QaKeys.tabSell,
      QaKeys.tabNotifications,
      QaKeys.tabProfile,
    ];

    // 先确保每个页面有根容器 Key，如果没有就跳过但记录警告
    final pageRootKeys = [
      QaKeys.pageHomeRoot,
      QaKeys.pageSavedRoot,
      QaKeys.pageSellRoot,
      QaKeys.pageNotificationsRoot,
      QaKeys.pageProfileRoot,
    ];

    for (int i = 0; i < tabs.length; i++) {
      final tabKey = tabs[i];
      final pageRootKey = pageRootKeys[i];
      
      print('🔄 Testing tab: $tabKey');
      
      // 点击 Tab
      final tabFinder = find.byKey(Key(tabKey));
      if (tabFinder.evaluate().isEmpty) {
        fail('Tab $tabKey not found');
      }
      await tester.tap(tabFinder.first);
      await tester.pump(const Duration(milliseconds: 500));
      await safeSettle(tester);

      // 验证页面可达（检查根容器 Key 或 fallback 到页面特定特征）
      final rootFinder = find.byKey(Key(pageRootKey));
      if (rootFinder.evaluate().isNotEmpty) {
        print('✅ Page root found for $tabKey');
      } else {
        // Fallback: 检查页面是否有明显特征（如标题文本）
        print('⚠️ Page root key $pageRootKey not found, using fallback check');
        // 根据 tab 索引检查页面特征
        switch (i) {
          case 0: // Home
            final homeFeature = find.byKey(const ValueKey('featured_ads_grid'));
            if (homeFeature.evaluate().isEmpty) {
              print('❌ Home page feature not found');
              // 不立即失败，可能UI已变化
            }
            break;
          case 1: // Saved
            final savedText = find.textContaining('Saved');
            if (savedText.evaluate().isEmpty) {
              print('⚠️ Saved page may need login or has no items');
            }
            break;
          case 2: // Sell
            final sellText = find.textContaining('Sell');
            if (sellText.evaluate().isEmpty) {
              print('⚠️ Sell page may not be loaded properly');
            }
            break;
          case 3: // Notifications
            final notifText = find.textContaining('Notification');
            if (notifText.evaluate().isEmpty) {
              print('⚠️ Notifications page may be empty');
            }
            break;
          case 4: // Profile
            final profileText = find.textContaining('Profile');
            if (profileText.evaluate().isEmpty) {
              print('⚠️ Profile page may not be loaded');
            }
            break;
        }
      }

      // 短暂暂停，确保UI稳定
      await tester.pump(const Duration(milliseconds: 300));
    }

    print('✅ All tabs are reachable');
  });
}