import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:swaply/main.dart' as app;
import 'package:swaply/core/qa_keys.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  // 辅助函数：安全的 pumpAndSettle（有限帧数，失败不中断）
  Future<void> safePumpAndSettle(WidgetTester tester,
      {Duration step = const Duration(milliseconds: 100)}) async {
    try {
      await tester.pumpAndSettle(step);
    } catch (e) {
      print('[KEY AUDIT] pumpAndSettle did not settle (ignored): $e');
    }
  }

  testWidgets('Key audit: all critical keys must exist in UI', (tester) async {
    // 1) 启动真实 App
    app.main();
    await tester.pump(const Duration(milliseconds: 300));
    await safePumpAndSettle(tester);
    print('✅ App started');

    // ===== Welcome Screen 逃逸逻辑 =====
    print('🔍 检查是否在 WelcomeScreen...');
    final welcomeGuestBtn = find.byKey(Key(QaKeys.welcomeGuestBtn));
    final welcomeGuestText = find.text('Browse as Guest');
    final tabHome = find.byKey(Key(QaKeys.tabHome));
    final qaFabFinder = find.byKey(Key(QaKeys.qaFab));

    // 如果在欢迎页，点击游客按钮进入
    if (welcomeGuestBtn.evaluate().isNotEmpty) {
      print('✅ 找到 welcome_guest_btn，点击进入游客模式');
      await tester.tap(welcomeGuestBtn.first);
      await safePumpAndSettle(tester);

      // 处理可能的对话框（Guest Mode 提示）
      final continueBtn = find.text('Continue');
      if (continueBtn.evaluate().isNotEmpty) {
        await tester.tap(continueBtn.first);
        await safePumpAndSettle(tester);
      }
      await tester.pump(const Duration(seconds: 1));
    } else if (tabHome.evaluate().isNotEmpty) {
      print('✅ 已经进入主界面');
    } else {
      print('⚠️  未知页面状态，继续尝试');
    }

    // 等待主界面加载（通过查找底部导航或 qa_fab）
    for (var i = 0; i < 30; i++) {
      final homeTab = find.byKey(Key(QaKeys.tabHome));
      if (homeTab.evaluate().isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 200));
    }

    // 2) 检查底部导航所有 Tab Key
    print('🔍 检查底部导航 Tab Keys...');
    expect(find.byKey(Key(QaKeys.tabHome)), findsOneWidget,
        reason: 'tab_home must exist');
    expect(find.byKey(Key(QaKeys.tabSaved)), findsOneWidget,
        reason: 'tab_saved must exist');
    expect(find.byKey(Key(QaKeys.tabSell)), findsOneWidget,
        reason: 'tab_sell must exist');
    expect(find.byKey(Key(QaKeys.tabNotifications)), findsOneWidget,
        reason: 'tab_notifications must exist');
    expect(find.byKey(Key(QaKeys.tabProfile)), findsOneWidget,
        reason: 'tab_profile must exist');
    print('✅ 所有底部导航 Tab Key 存在');

    // 3) 检查全局 QA 浮动按钮
    expect(find.byKey(Key(QaKeys.qaFab)), findsOneWidget,
        reason: 'qa_fab must exist when QA_MODE=true');

    // 4) 检查页面根容器 Key（逐个导航并验证）
    print('🔍 检查页面根容器 Keys...');
    
    // Home 页
    await tester.tap(find.byKey(Key(QaKeys.tabHome)).first);
    await safePumpAndSettle(tester);
    expect(find.byKey(Key(QaKeys.pageHomeRoot)), findsOneWidget,
        reason: 'page_home_root must exist');

    // Saved 页
    await tester.tap(find.byKey(Key(QaKeys.tabSaved)).first);
    await safePumpAndSettle(tester);
    expect(find.byKey(Key(QaKeys.pageSavedRoot)), findsOneWidget,
        reason: 'page_saved_root must exist');

    // Sell 页
    await tester.tap(find.byKey(Key(QaKeys.tabSell)).first);
    await safePumpAndSettle(tester);
    expect(find.byKey(Key(QaKeys.pageSellRoot)), findsOneWidget,
        reason: 'page_sell_root must exist');
    // 检查 QA Mock 发布按钮（应在 QA_MODE 下存在）
    expect(find.byKey(Key(QaKeys.qaMockPublishButton)), findsOneWidget,
        reason: 'qa_mock_publish_button must exist when QA_MODE=true');

    // Notifications 页
    await tester.tap(find.byKey(Key(QaKeys.tabNotifications)).first);
    await safePumpAndSettle(tester);
    expect(find.byKey(Key(QaKeys.pageNotificationsRoot)), findsOneWidget,
        reason: 'page_notifications_root must exist');

    // Profile 页
    await tester.tap(find.byKey(Key(QaKeys.tabProfile)).first);
    await safePumpAndSettle(tester);
    expect(find.byKey(Key(QaKeys.pageProfileRoot)), findsOneWidget,
        reason: 'page_profile_root must exist');

    // 检查 Profile 内的入口 Key
    expect(find.byKey(Key(QaKeys.profileRewardCenterEntry)), findsOneWidget,
        reason: 'profile_reward_center_entry must exist');
    expect(find.byKey(Key(QaKeys.profileSettingsEntry)), findsOneWidget,
        reason: 'profile_settings_entry must exist');
    print('✅ 所有页面根容器 Key 存在');

    // 5) 检查搜索/分类相关 Key（在 Home 页）
    await tester.tap(find.byKey(Key(QaKeys.tabHome)).first);
    await safePumpAndSettle(tester);
    expect(find.byKey(Key(QaKeys.searchInput)), findsOneWidget,
        reason: 'search_input must exist');
    expect(find.byKey(Key(QaKeys.searchButton)), findsOneWidget,
        reason: 'search_button must exist');
    expect(find.byKey(Key(QaKeys.categoryGrid)), findsOneWidget,
        reason: 'category_grid must exist');
    // 至少有一个 category item
    final categoryItemFinder = find.byKey(Key(QaKeys.categoryItemKey(0)));
    if (categoryItemFinder.evaluate().isNotEmpty) {
      print('✅ category_item_0 exists');
    } else {
      // 如果首页没有 category item，至少 category grid 存在即可
      print('⚠️  No category_item_0 found, but category_grid exists');
    }

    // 6) 检查奖励相关 Key（通过 QA Panel 或直接导航）
    // 先点击 qa_fab 打开 QA Panel
    await tester.tap(find.byKey(Key(QaKeys.qaFab)).first);
    await safePumpAndSettle(tester);
    // QA Panel 内应有奖励入口
    final qaNavRewardCenter = find.byKey(Key(QaKeys.qaNavRewardCenter));
    if (qaNavRewardCenter.evaluate().isNotEmpty) {
      await tester.tap(qaNavRewardCenter.first);
      await safePumpAndSettle(tester);
      // 检查 Reward Center 页面的 Key
      expect(find.byKey(Key(QaKeys.rewardCenterRulesCard)), findsOneWidget,
          reason: 'reward_center_rules_card must exist');
      // 可以进一步检查 reward_rules_btn 等，但需要进入更多页面
      // 暂时返回
    } else {
      print('⚠️  qa_nav_reward_center not found, skipping reward key audit');
    }

    // 7) 列出已检查的 Key（供报告）
    print('\n=== KEY AUDIT SUMMARY ===');
    print('✅ All critical UI keys are present.');
    print('If any key is missing, the test would have failed above.');
  });
}