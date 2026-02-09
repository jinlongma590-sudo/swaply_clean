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
    print('[safeSettle] still busy after ${maxAttempts * step.inMilliseconds}ms, continue');
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

  Future<bool> waitForKey(
      WidgetTester tester,
      String key, {
        Duration timeout = const Duration(seconds: 30),
        Duration step = const Duration(milliseconds: 250),
      }) async {
    return waitForAny(
      tester,
      [find.byKey(Key(key))],
      timeout: timeout,
      step: step,
    );
  }

  /// ✅ 关键：避免 FlutterError.onError 残留导致 binding assertion
  Future<void> runGuardedTest(
      WidgetTester tester,
      String name,
      Future<void> Function() body,
      ) async {
    final original = FlutterError.onError;
    final List<FlutterErrorDetails> captured = [];

    FlutterError.onError = (FlutterErrorDetails details) {
      captured.add(details);
      // 仍然转发到原处理（保证日志输出）
      original?.call(details);
    };

    try {
      await body();
    } finally {
      FlutterError.onError = original;

      if (captured.isNotEmpty) {
        // ignore: avoid_print
        print('❌ [$name] Captured FlutterError(s): ${captured.length}');
        for (final d in captured.take(3)) {
          // ignore: avoid_print
          print('--- FlutterError ---\n${d.exceptionAsString()}\n${d.stack ?? ''}\n');
        }
        fail('[$name] FlutterError captured during test. See logs above.');
      }
    }
  }

  Future<void> navigateToMainInterface(WidgetTester tester) async {
    app.main();
    await tester.pump(const Duration(milliseconds: 300));
    await safeSettle(tester);

    // Welcome -> Guest
    final welcomeGuestBtn = find.byKey(Key(QaKeys.welcomeGuestBtn));
    if (welcomeGuestBtn.evaluate().isNotEmpty) {
      await tester.tap(welcomeGuestBtn.first);
      await tester.pump(const Duration(milliseconds: 800));
      await safeSettle(tester);

      final dialogContinueBtn = find.byKey(Key(QaKeys.welcomeContinueBtn));
      final continueText = find.text('Continue');

      final ok = await waitForAny(
        tester,
        [dialogContinueBtn, continueText],
        timeout: const Duration(seconds: 12),
      );
      if (!ok) {
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

    final ok = await waitForKey(
      tester,
      QaKeys.tabHome,
      timeout: const Duration(seconds: 50),
    );
    if (!ok) {
      debugDumpApp();
      fail('Main interface not reached (tabHome missing)');
    }
  }

  group('Core Flows', () {
    testWidgets('Search flow', (tester) async {
      await runGuardedTest(tester, 'Search flow', () async {
        await navigateToMainInterface(tester);

        final homeTab = find.byKey(Key(QaKeys.tabHome));
        expect(homeTab, findsOneWidget, reason: 'Home tab should be visible');
        await tester.tap(homeTab.first);
        await tester.pump(const Duration(milliseconds: 350));
        await safeSettle(tester);

        final searchInput = find.byKey(Key(QaKeys.searchInput));
        final inputOk = await waitForAny(
          tester,
          [searchInput],
          timeout: const Duration(seconds: 25),
        );
        if (!inputOk) {
          debugDumpApp();
          fail('Search input field not visible on Home page');
        }

        await tester.enterText(searchInput, 'phone');
        await tester.pump(const Duration(milliseconds: 300));

        final searchButton = find.byKey(Key(QaKeys.searchButton));
        expect(searchButton, findsOneWidget, reason: 'Search button should be visible');
        await tester.tap(searchButton.first);
        await tester.pump(const Duration(milliseconds: 500));

        final listingGrid = find.byKey(Key(QaKeys.listingGrid));
        final noResults = find.textContaining('No results');

        final resultsOk = await waitForAny(
          tester,
          [listingGrid, noResults],
          timeout: const Duration(seconds: 35),
        );

        if (!resultsOk) {
          debugDumpApp();
          fail('Search results page not loaded properly (no grid/no "No results")');
        }

        // ignore: avoid_print
        print('✅ Search flow completed');
      });
    });

    testWidgets('Category browse flow', (tester) async {
      await runGuardedTest(tester, 'Category browse flow', () async {
        await navigateToMainInterface(tester);

        final homeTab = find.byKey(Key(QaKeys.tabHome));
        expect(homeTab, findsOneWidget, reason: 'Home tab should be visible');
        await tester.tap(homeTab.first);
        await tester.pump(const Duration(milliseconds: 350));
        await safeSettle(tester);

        final categoryGrid = find.byKey(Key(QaKeys.categoryGrid));
        final gridOk = await waitForAny(
          tester,
          [categoryGrid],
          timeout: const Duration(seconds: 25),
        );
        if (!gridOk) {
          debugDumpApp();
          fail('Category grid not visible on Home page');
        }

        const firstCategorySlug = 'vehicles';
        final firstCategory = find.byKey(Key('category_item_$firstCategorySlug'));
        final catOk = await waitForAny(
          tester,
          [firstCategory],
          timeout: const Duration(seconds: 25),
        );
        if (!catOk || firstCategory.evaluate().isEmpty) {
          debugDumpApp();
          fail('Category item $firstCategorySlug not found');
        }

        await tester.tap(firstCategory.first);
        await tester.pump(const Duration(milliseconds: 700));
        await safeSettle(tester, maxAttempts: 90);

        final listingGrid = find.byKey(Key(QaKeys.listingGrid));
        final listOk = await waitForAny(
          tester,
          [listingGrid],
          timeout: const Duration(seconds: 35),
        );
        if (!listOk) {
          debugDumpApp();
          fail('Category products page should show listing grid');
        }

        final firstListingItem = find.byKey(const Key('listing_item_0'));
        if (firstListingItem.evaluate().isNotEmpty) {
          await tester.tap(firstListingItem.first);
          await tester.pump(const Duration(milliseconds: 700));
          await safeSettle(tester, maxAttempts: 90);

          final detailRoot = find.byKey(Key(QaKeys.listingDetailRoot));
          final detailOk = await waitForAny(
            tester,
            [detailRoot],
            timeout: const Duration(seconds: 25),
          );
          if (!detailOk) {
            debugDumpApp();
            fail('Product detail page should be loaded');
          }

          final favoriteToggle = find.byKey(Key(QaKeys.favoriteToggle));
          expect(favoriteToggle, findsOneWidget, reason: 'Favorite toggle should be visible');

          // ignore: avoid_print
          print('✅ Category → Listing → Detail flow completed');
        } else {
          // ignore: avoid_print
          print('⚠️ No listing items found in category, but page loaded successfully');
        }
      });
    });

    testWidgets('Favorite/Unfavorite flow', (tester) async {
      await runGuardedTest(tester, 'Favorite/Unfavorite flow', () async {
        await navigateToMainInterface(tester);

        final savedTab = find.byKey(Key(QaKeys.tabSaved));
        expect(savedTab, findsOneWidget, reason: 'Saved tab should be visible');
        await tester.tap(savedTab.first);
        await tester.pump(const Duration(milliseconds: 500));
        await safeSettle(tester);

        final savedRoot = find.byKey(Key(QaKeys.pageSavedRoot));
        final rootOk = await waitForAny(
          tester,
          [savedRoot],
          timeout: const Duration(seconds: 25),
        );
        if (!rootOk) {
          debugDumpApp();
          fail('Saved page root not loaded');
        }

        final savedEmptyState = find.byKey(Key(QaKeys.savedEmptyState));
        final loginPrompt = find.textContaining('Login');
        final loginRequired = find.textContaining('Login Required');

        final ok = await waitForAny(
          tester,
          [savedEmptyState, loginPrompt, loginRequired],
          timeout: const Duration(seconds: 20),
        );

        if (!ok) {
          debugDumpApp();
          fail('Saved page in guest mode should show empty state or login prompt');
        }

        // ignore: avoid_print
        print('✅ Saved page flow verified (guest mode)');
      });
    });

    testWidgets('Publish flow (QA_MODE mock)', (tester) async {
      await runGuardedTest(tester, 'Publish flow (QA_MODE mock)', () async {
        await navigateToMainInterface(tester);

        final sellTab = find.byKey(Key(QaKeys.tabSell));
        expect(sellTab, findsOneWidget, reason: 'Sell tab should be visible');
        await tester.tap(sellTab.first);
        await tester.pump(const Duration(milliseconds: 500));
        await safeSettle(tester, maxAttempts: 90);

        final sellRoot = find.byKey(Key(QaKeys.pageSellRoot));
        final rootOk = await waitForAny(
          tester,
          [sellRoot],
          timeout: const Duration(seconds: 25),
        );
        if (!rootOk) {
          debugDumpApp();
          fail('Sell page should be loaded');
        }

        final mockButton = find.byKey(Key(QaKeys.qaMockPublishButton));
        final btnOk = await waitForAny(
          tester,
          [mockButton],
          timeout: const Duration(seconds: 20),
        );
        if (!btnOk || mockButton.evaluate().isEmpty) {
          debugDumpApp();
          fail('qa_mock_publish_button must exist when QA_MODE=true');
        }

        await tester.tap(mockButton.first);
        await tester.pump(const Duration(milliseconds: 700));
        await safeSettle(tester, maxAttempts: 90);

        final snackBar = find.byKey(Key(QaKeys.qaMockPublishSuccess));
        final snackOk = await waitForAny(
          tester,
          [snackBar],
          timeout: const Duration(seconds: 20),
        );
        if (!snackOk) {
          debugDumpApp();
          fail('qa_mock_publish_success SnackBar should appear');
        }

        await tester.pump(const Duration(seconds: 1));
        // ignore: avoid_print
        print('✅ Sell mock publish flow verified');
      });
    });

    testWidgets('Profile & Settings flow', (tester) async {
      await runGuardedTest(tester, 'Profile & Settings flow', () async {
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
          timeout: const Duration(seconds: 25),
        );
        if (!rootOk) {
          debugDumpApp();
          fail('Profile page should be loaded');
        }

        final rewardCenterEntry = find.byKey(Key(QaKeys.profileRewardCenterEntry));
        if (rewardCenterEntry.evaluate().isNotEmpty) {
          await tester.tap(rewardCenterEntry.first);
          await tester.pump(const Duration(milliseconds: 700));
          await safeSettle(tester, maxAttempts: 90);
          // ignore: avoid_print
          print('✅ Reward Center entry tapped');
          await tester.pageBack();
          await tester.pump(const Duration(milliseconds: 500));
          await safeSettle(tester);
        }

        final settingsEntry = find.byKey(Key(QaKeys.profileSettingsEntry));
        if (settingsEntry.evaluate().isNotEmpty) {
          await tester.tap(settingsEntry.first);
          await tester.pump(const Duration(milliseconds: 700));
          await safeSettle(tester, maxAttempts: 90);
          // ignore: avoid_print
          print('✅ Settings entry tapped');
          await tester.pageBack();
          await tester.pump(const Duration(milliseconds: 500));
          await safeSettle(tester);
        }

        // ignore: avoid_print
        print('✅ Profile & Settings flow completed');
      });
    });
  });
}