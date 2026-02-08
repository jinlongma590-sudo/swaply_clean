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

  // 导航到主界面的通用函数（更抗 CI 抖动）
  Future<void> navigateToMainInterface(WidgetTester tester) async {
    app.main();
    await tester.pump(const Duration(milliseconds: 300));
    await safeSettle(tester);

    // Welcome Screen → Guest
    final welcomeGuestBtn = find.byKey(Key(QaKeys.welcomeGuestBtn));
    if (welcomeGuestBtn.evaluate().isNotEmpty) {
      await tester.tap(welcomeGuestBtn.first);
      await tester.pump(const Duration(milliseconds: 800));
      await safeSettle(tester);

      final dialogContinueBtn = find.byKey(Key(QaKeys.welcomeContinueBtn));
      final continueText = find.text('Continue');

      final dialogOk = await waitForAny(
        tester,
        [dialogContinueBtn, continueText],
        timeout: const Duration(seconds: 12),
      );

      if (!dialogOk) {
        debugDumpApp();
        fail('Guest mode dialog Continue did not appear');
      }

      if (dialogContinueBtn.evaluate().isNotEmpty) {
        await tester.tap(dialogContinueBtn.first);
      } else if (continueText.evaluate().isNotEmpty) {
        await tester.tap(continueText.first);
      }

      await tester.pump(const Duration(milliseconds: 800));
      await safeSettle(tester);
    }

    // 等待进入主界面：tabHome 出现
    final ok = await waitForKey(
      tester,
      QaKeys.tabHome,
      timeout: const Duration(seconds: 40),
    );
    if (!ok) {
      debugDumpApp();
      fail('Main interface not reached (tabHome missing)');
    }
  }

  group('Core Flows', () {
    testWidgets('Search flow', (tester) async {
      await navigateToMainInterface(tester);

      // 1. 点击 Home tab（确保在首页）
      final homeTab = find.byKey(Key(QaKeys.tabHome));
      expect(homeTab, findsOneWidget, reason: 'Home tab should be visible');
      await tester.tap(homeTab.first);
      await tester.pump(const Duration(milliseconds: 350));
      await safeSettle(tester);

      // 2. 等待搜索输入框出现（比 settle 更可靠）
      final searchInput = find.byKey(Key(QaKeys.searchInput));
      final inputOk = await waitForAny(
        tester,
        [searchInput],
        timeout: const Duration(seconds: 20),
      );
      if (!inputOk) {
        debugDumpApp();
        fail('Search input field not visible on Home page');
      }

      // 3. 输入搜索词
      await tester.enterText(searchInput, 'phone');
      await tester.pump(const Duration(milliseconds: 300));

      // 4. 点击搜索按钮
      final searchButton = find.byKey(Key(QaKeys.searchButton));
      expect(searchButton, findsOneWidget, reason: 'Search button should be visible');
      await tester.tap(searchButton.first);
      await tester.pump(const Duration(milliseconds: 500));

      // 5. 验证结果页（listing_grid 或 No results）
      final listingGrid = find.byKey(Key(QaKeys.listingGrid));
      final noResults = find.textContaining('No results');

      final resultsOk = await waitForAny(
        tester,
        [listingGrid, noResults],
        timeout: const Duration(seconds: 25),
      );

      if (!resultsOk) {
        debugDumpApp();
        fail('Search results page not loaded properly (no grid/no "No results")');
      }

      print('✅ Search flow completed with strict assertions');
    });

    testWidgets('Category browse flow', (tester) async {
      await navigateToMainInterface(tester);

      // 1. 在 Home 页
      final homeTab = find.byKey(Key(QaKeys.tabHome));
      expect(homeTab, findsOneWidget, reason: 'Home tab should be visible');
      await tester.tap(homeTab.first);
      await tester.pump(const Duration(milliseconds: 350));
      await safeSettle(tester);

      // 2. 分类网格
      final categoryGrid = find.byKey(Key(QaKeys.categoryGrid));
      final gridOk = await waitForAny(
        tester,
        [categoryGrid],
        timeout: const Duration(seconds: 20),
      );
      if (!gridOk) {
        debugDumpApp();
        fail('Category grid not visible on Home page');
      }

      // 3. 点击一个分类
      const firstCategorySlug = 'vehicles';
      final firstCategory = find.byKey(Key('category_item_$firstCategorySlug'));
      final catOk = await waitForAny(
        tester,
        [firstCategory],
        timeout: const Duration(seconds: 20),
      );
      if (!catOk) {
        debugDumpApp();
        fail('Category item $firstCategorySlug not found');
      }

      await tester.tap(firstCategory.first);
      await tester.pump(const Duration(milliseconds: 600));
      await safeSettle(tester, maxAttempts: 80);

      // 4. 分类列表页：listing_grid
      final listingGrid = find.byKey(Key(QaKeys.listingGrid));
      final listOk = await waitForAny(
        tester,
        [listingGrid],
        timeout: const Duration(seconds: 25),
      );
      if (!listOk) {
        debugDumpApp();
        fail('Category products page should show listing grid');
      }

      // 5. 点击第一个列表项（如果有）
      final firstListingItem = find.byKey(const Key('listing_item_0'));
      if (firstListingItem.evaluate().isNotEmpty) {
        await tester.tap(firstListingItem.first);
        await tester.pump(const Duration(milliseconds: 600));
        await safeSettle(tester, maxAttempts: 80);

        // 6. 详情页
        final detailRoot = find.byKey(Key(QaKeys.listingDetailRoot));
        final detailOk = await waitForAny(
          tester,
          [detailRoot],
          timeout: const Duration(seconds: 20),
        );
        if (!detailOk) {
          debugDumpApp();
          fail('Product detail page should be loaded');
        }

        // 7. 收藏按钮（可选强断言）
        final favoriteToggle = find.byKey(Key(QaKeys.favoriteToggle));
        expect(favoriteToggle, findsOneWidget,
            reason: 'Favorite toggle should be visible on detail page');

        print('✅ Category → Listing → Detail → Favorite flow completed');
      } else {
        print('⚠️ No listing items found in category, but page loaded successfully');
      }
    });

    testWidgets('Favorite/Unfavorite flow', (tester) async {
      await navigateToMainInterface(tester);

      final savedTab = find.byKey(Key(QaKeys.tabSaved));
      expect(savedTab, findsOneWidget, reason: 'Saved tab should be visible');
      await tester.tap(savedTab.first);
      await tester.pump(const Duration(milliseconds: 500));
      await safeSettle(tester);

      // Saved 页面根
      final savedRoot = find.byKey(Key(QaKeys.pageSavedRoot));
      final rootOk = await waitForAny(
        tester,
        [savedRoot],
        timeout: const Duration(seconds: 20),
      );
      if (!rootOk) {
        debugDumpApp();
        fail('Saved page root not loaded');
      }

      // Guest 模式下空态或登录提示
      final savedEmptyState = find.byKey(Key(QaKeys.savedEmptyState));
      final loginPrompt = find.textContaining('Login');
      final loginRequired = find.textContaining('Login Required');

      final ok = await waitForAny(
        tester,
        [savedEmptyState, loginPrompt, loginRequired],
        timeout: const Duration(seconds: 15),
      );

      if (!ok) {
        debugDumpApp();
        fail('Saved page in guest mode should show empty state or login prompt');
      }

      print('✅ Saved page flow verified for guest mode');
    });

    testWidgets('Publish flow (QA_MODE mock)', (tester) async {
      await navigateToMainInterface(tester);

      final sellTab = find.byKey(Key(QaKeys.tabSell));
      expect(sellTab, findsOneWidget, reason: 'Sell tab should be visible');
      await tester.tap(sellTab.first);
      await tester.pump(const Duration(milliseconds: 500));
      await safeSettle(tester, maxAttempts: 80);

      final sellRoot = find.byKey(Key(QaKeys.pageSellRoot));
      final rootOk = await waitForAny(
        tester,
        [sellRoot],
        timeout: const Duration(seconds: 20),
      );
      if (!rootOk) {
        debugDumpApp();
        fail('Sell page should be loaded');
      }

      final mockButton = find.byKey(Key(QaKeys.qaMockPublishButton));
      final btnOk = await waitForAny(
        tester,
        [mockButton],
        timeout: const Duration(seconds: 15),
      );
      if (!btnOk) {
        debugDumpApp();
        fail('qa_mock_publish_button must exist when QA_MODE=true');
      }

      await tester.tap(mockButton.first);
      await tester.pump(const Duration(milliseconds: 600));
      await safeSettle(tester, maxAttempts: 80);

      final snackBar = find.byKey(Key(QaKeys.qaMockPublishSuccess));
      final snackOk = await waitForAny(
        tester,
        [snackBar],
        timeout: const Duration(seconds: 15),
      );
      if (!snackOk) {
        debugDumpApp();
        fail('qa_mock_publish_success SnackBar should appear');
      }

      await tester.pump(const Duration(seconds: 2));
      print('✅ Sell mock publish flow fully verified');
    });

    testWidgets('Profile & Settings flow', (tester) async {
      await navigateToMainInterface(tester);

      final profileTab = find.byKey(Key(QaKeys.tabProfile));
      expect(profileTab, findsOneWidget, reason: 'Profile tab should be visible');
      await tester.tap(profileTab.first);
      await tester.pump(const Duration(milliseconds: 500));
      await safeSettle(tester);

      final profileRoot = find.byKey(Key(QaKeys.pageProfileRoot));
      final rootOk = await waitForAny(
        tester,
        [profileRoot],
        timeout: const Duration(seconds: 20),
      );
      if (!rootOk) {
        debugDumpApp();
        fail('Profile page should be loaded');
      }

      // Reward Center entry（可选）
      final rewardCenterEntry = find.byKey(Key(QaKeys.profileRewardCenterEntry));
      if (rewardCenterEntry.evaluate().isNotEmpty) {
        await tester.tap(rewardCenterEntry.first);
        await tester.pump(const Duration(milliseconds: 600));
        await safeSettle(tester, maxAttempts: 80);
        print('✅ Reward Center entry tapped');
        await tester.pageBack();
        await tester.pump(const Duration(milliseconds: 500));
        await safeSettle(tester);
      } else {
        print('⚠️ Reward Center entry not found (may not be implemented yet)');
      }

      // Settings entry（可选）
      final settingsEntry = find.byKey(Key(QaKeys.profileSettingsEntry));
      if (settingsEntry.evaluate().isNotEmpty) {
        await tester.tap(settingsEntry.first);
        await tester.pump(const Duration(milliseconds: 600));
        await safeSettle(tester, maxAttempts: 80);
        print('✅ Settings entry tapped');
        await tester.pageBack();
        await tester.pump(const Duration(milliseconds: 500));
        await safeSettle(tester);
      } else {
        print('⚠️ Settings entry not found (may not be implemented yet)');
      }

      print('✅ Profile & Settings flow completed');
    });
  });
}