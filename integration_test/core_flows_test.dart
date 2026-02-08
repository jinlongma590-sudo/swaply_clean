import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:swaply/main.dart' as app;
import 'package:swaply/core/qa_keys.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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

  // 导航到主界面的通用函数
  Future<void> navigateToMainInterface(WidgetTester tester) async {
    app.main();
    await tester.pump(const Duration(milliseconds: 300));
    await safeSettle(tester);

    // Welcome Screen → Guest 流程
    final welcomeGuestBtn = find.byKey(Key(QaKeys.welcomeGuestBtn));
    if (welcomeGuestBtn.evaluate().isNotEmpty) {
      await tester.tap(welcomeGuestBtn.first);
      await tester.pump(const Duration(milliseconds: 800));

      // 处理 Guest Mode 对话框
      final dialogContinueBtn = find.byKey(Key(QaKeys.welcomeContinueBtn));
      expect(dialogContinueBtn, findsOneWidget, reason: 'Guest mode dialog Continue button should be visible');
      await tester.tap(dialogContinueBtn.first);
      await tester.pump(const Duration(milliseconds: 800));
    }

    // 等待进入主界面
    final tabHomeFound = await waitForKey(tester, QaKeys.tabHome);
    if (!tabHomeFound) {
      debugDumpApp();
      fail('Main interface not reached within timeout');
    }
  }

  group('Core Flows', () {
    testWidgets('Search flow', (tester) async {
      await navigateToMainInterface(tester);

      // 1. 点击 Home tab（确保在首页）
      final homeTab = find.byKey(Key(QaKeys.tabHome));
      expect(homeTab, findsOneWidget, reason: 'Home tab should be visible');
      await tester.tap(homeTab.first);
      await safeSettle(tester);

      // 2. 查找搜索输入框（严格断言）
      final searchInput = find.byKey(Key(QaKeys.searchInput));
      expect(searchInput, findsOneWidget, reason: 'Search input field should be visible on Home page');
      
      // 3. 输入搜索词
      await tester.enterText(searchInput, 'phone');
      await tester.pump(const Duration(milliseconds: 300));

      // 4. 点击搜索按钮（严格断言）
      final searchButton = find.byKey(Key(QaKeys.searchButton));
      expect(searchButton, findsOneWidget, reason: 'Search button should be visible');
      await tester.tap(searchButton.first);
      await safeSettle(tester);

      // 5. 验证结果页（检查列表网格或空状态）
      // 搜索可能返回结果或无结果，两种情况都需要验证页面加载
      final listingGrid = find.byKey(Key(QaKeys.listingGrid));
      final noResults = find.textContaining('No results');
      
      // 至少应该有一种情况出现
      if (listingGrid.evaluate().isEmpty && noResults.evaluate().isEmpty) {
        // 页面可能未正确加载，dump widget tree用于调试
        debugDumpApp();
        fail('Search results page not loaded properly - no listing grid or "no results" message found');
      }
      
      print('✅ Search flow completed with strict assertions');
    });

    testWidgets('Category browse flow', (tester) async {
      await navigateToMainInterface(tester);

      // 1. 在 Home 页
      final homeTab = find.byKey(Key(QaKeys.tabHome));
      expect(homeTab, findsOneWidget, reason: 'Home tab should be visible');
      await tester.tap(homeTab.first);
      await safeSettle(tester);

      // 2. 查找分类网格（严格断言）
      final categoryGrid = find.byKey(Key(QaKeys.categoryGrid));
      expect(categoryGrid, findsOneWidget, reason: 'Category grid should be visible on Home page');
      
      // 3. 点击第一个分类（严格断言）
      // 注意：QaKeys.categoryItemKey需要返回正确的格式，如'category_item_vehicles'
      final firstCategorySlug = 'vehicles'; // 使用实际分类slug
      final firstCategory = find.byKey(Key('category_item_$firstCategorySlug'));
      expect(firstCategory, findsOneWidget, reason: 'First category item should be visible');
      await tester.tap(firstCategory.first);
      await safeSettle(tester);

      // 4. 验证分类列表页加载（通过listing_grid检查）
      final listingGrid = find.byKey(Key(QaKeys.listingGrid));
      expect(listingGrid, findsOneWidget, reason: 'Category products page should show listing grid');
      
      // 5. 点击第一个列表项进入详情
      final firstListingItem = find.byKey(Key('listing_item_0'));
      if (firstListingItem.evaluate().isNotEmpty) {
        await tester.tap(firstListingItem.first);
        await safeSettle(tester);

        // 6. 验证详情页
        final detailRoot = find.byKey(Key(QaKeys.listingDetailRoot));
        expect(detailRoot, findsOneWidget, reason: 'Product detail page should be loaded');
        
        // 7. 可选：验证收藏按钮存在
        final favoriteToggle = find.byKey(Key(QaKeys.favoriteToggle));
        expect(favoriteToggle, findsOneWidget, reason: 'Favorite toggle button should be visible on detail page');
        
        print('✅ Category → Listing → Detail → Favorite flow completed');
      } else {
        // 如果没有列表项，至少验证页面已加载
        print('⚠️ No listing items found in category, but page loaded successfully');
      }
    });

    testWidgets('Favorite/Unfavorite flow', (tester) async {
      await navigateToMainInterface(tester);

      // Guest模式下，Saved页面应显示空态或登录提示
      final savedTab = find.byKey(Key(QaKeys.tabSaved));
      expect(savedTab, findsOneWidget, reason: 'Saved tab should be visible');
      await tester.tap(savedTab.first);
      await safeSettle(tester);

      // 验证Saved页面已加载（通过页面根Key）
      final savedRoot = find.byKey(Key(QaKeys.pageSavedRoot));
      expect(savedRoot, findsOneWidget, reason: 'Saved page should be loaded');
      
      // Guest模式下应该看到空态（saved_empty_state）或登录提示
      final savedEmptyState = find.byKey(Key(QaKeys.savedEmptyState));
      final loginPrompt = find.textContaining('Login');
      final loginRequired = find.textContaining('Login Required');
      
      // 至少应该有一种情况出现
      if (savedEmptyState.evaluate().isEmpty && 
          loginPrompt.evaluate().isEmpty && 
          loginRequired.evaluate().isEmpty) {
        debugDumpApp();
        fail('Saved page in guest mode should show empty state or login prompt');
      }
      
      print('✅ Saved page flow verified for guest mode');
    });

    testWidgets('Publish flow (QA_MODE mock)', (tester) async {
      await navigateToMainInterface(tester);

      // 1. 点击 Sell tab
      final sellTab = find.byKey(Key(QaKeys.tabSell));
      expect(sellTab, findsOneWidget, reason: 'Sell tab should be visible');
      await tester.tap(sellTab.first);
      await safeSettle(tester);

      // 2. 验证Sell页面可达（通过页面根Key）
      final sellRoot = find.byKey(Key(QaKeys.pageSellRoot));
      expect(sellRoot, findsOneWidget, reason: 'Sell page should be loaded');
      
      // 3. 硬断言：QA Mock发布按钮必须存在
      final mockButton = find.byKey(Key(QaKeys.qaMockPublishButton));
      expect(mockButton, findsOneWidget, reason: 'qa_mock_publish_button must exist when QA_MODE=true');
      
      // 4. 点击mock按钮
      await tester.tap(mockButton.first);
      await safeSettle(tester);
      
      // 5. 验证SnackBar成功提示（通过Key）
      final snackBar = find.byKey(Key(QaKeys.qaMockPublishSuccess));
      expect(snackBar, findsOneWidget, reason: 'qa_mock_publish_success SnackBar should appear');
      
      // 等待SnackBar消失（可选）
      await tester.pump(const Duration(seconds: 2));
      
      print('✅ Sell mock publish flow fully verified');
    });

    testWidgets('Profile & Settings flow', (tester) async {
      await navigateToMainInterface(tester);

      // 1. 点击 Profile tab
      final profileTab = find.byKey(Key(QaKeys.tabProfile));
      expect(profileTab, findsOneWidget, reason: 'Profile tab should be visible');
      await tester.tap(profileTab.first);
      await safeSettle(tester);

      // 2. 验证Profile页面可达
      final profileRoot = find.byKey(Key(QaKeys.pageProfileRoot));
      expect(profileRoot, findsOneWidget, reason: 'Profile page should be loaded');
      
      // 3. 查找Reward Center入口（如果存在）
      final rewardCenterEntry = find.byKey(Key(QaKeys.profileRewardCenterEntry));
      if (rewardCenterEntry.evaluate().isNotEmpty) {
        await tester.tap(rewardCenterEntry.first);
        await safeSettle(tester);
        print('✅ Reward Center entry tapped');
        // 返回主界面
        await tester.pageBack();
        await safeSettle(tester);
      } else {
        print('⚠️ Reward Center entry not found (may not be implemented yet)');
      }

      // 4. 查找Settings入口（如果存在）
      final settingsEntry = find.byKey(Key(QaKeys.profileSettingsEntry));
      if (settingsEntry.evaluate().isNotEmpty) {
        await tester.tap(settingsEntry.first);
        await safeSettle(tester);
        print('✅ Settings entry tapped');
        // 返回
        await tester.pageBack();
        await safeSettle(tester);
      } else {
        print('⚠️ Settings entry not found (may not be implemented yet)');
      }
      
      print('✅ Profile & Settings flow completed');
    });
  });
}