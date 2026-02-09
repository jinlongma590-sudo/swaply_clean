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
      }) async {
    return waitForAny(
      tester,
      [find.byKey(Key(key))],
      timeout: timeout,
    );
  }

  Future<void> scrollUntilVisible(
      WidgetTester tester,
      Finder finder,
      double delta, {
        int maxScrolls = 80,
      }) async {
    final scrollable = find.byType(Scrollable);
    for (int i = 0; i < maxScrolls; i++) {
      if (finder.evaluate().isNotEmpty) return;
      if (scrollable.evaluate().isEmpty) break;
      await tester.drag(scrollable.first, Offset(0, -delta));
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> openQaPanel(WidgetTester tester) async {
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

    final panelOk = await waitForAny(
      tester,
      [find.text('QA Panel')],
      timeout: const Duration(seconds: 12),
    );
    if (!panelOk) {
      debugDumpApp();
      fail('QA Panel not opened after tapping qa_fab');
    }
  }

  Future<void> gotoHomeRoot(WidgetTester tester) async {
    final homeTab = find.byKey(Key(QaKeys.tabHome));
    if (homeTab.evaluate().isNotEmpty) {
      await tester.tap(homeTab.first);
      await tester.pump(const Duration(milliseconds: 450));
      await safeSettle(tester, maxAttempts: 80);
    }
  }

  /// ✅ 稳定返回 QA Panel：不要依赖 back button / back stack
  Future<void> ensureBackToQaPanel(WidgetTester tester) async {
    // try back 2 times
    for (int i = 0; i < 2; i++) {
      final already = find.text('QA Panel');
      if (already.evaluate().isNotEmpty) return;

      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 450));
      await safeSettle(tester, maxAttempts: 80);

      if (find.text('QA Panel').evaluate().isNotEmpty) return;
    }

    // fallback: go home tab and reopen QA Panel
    await gotoHomeRoot(tester);
    await openQaPanel(tester);
  }

  /// ✅ 同样解决 FlutterError.onError 残留问题
  Future<void> runGuarded(
      WidgetTester tester,
      Future<void> Function() body,
      ) async {
    final original = FlutterError.onError;
    final List<FlutterErrorDetails> captured = [];

    FlutterError.onError = (FlutterErrorDetails details) {
      captured.add(details);
      original?.call(details);
    };

    try {
      await body();
    } finally {
      FlutterError.onError = original;
      if (captured.isNotEmpty) {
        // ignore: avoid_print
        print('❌ Captured FlutterError(s): ${captured.length}');
        for (final d in captured.take(3)) {
          // ignore: avoid_print
          print('--- FlutterError ---\n${d.exceptionAsString()}\n${d.stack ?? ''}\n');
        }
        fail('FlutterError captured during test. See logs above.');
      }
    }
  }

  testWidgets('Full App Smoke via QA Panel', (tester) async {
    await runGuarded(tester, () async {
      // 1) Cold start
      app.main();
      await tester.pump(const Duration(milliseconds: 300));
      await safeSettle(tester);

      // 2) Welcome -> Guest (best effort)
      final welcomeGuestBtn = find.byKey(Key(QaKeys.welcomeGuestBtn));
      if (welcomeGuestBtn.evaluate().isNotEmpty) {
        // ignore: avoid_print
        print('✅ WelcomeScreen: entering guest mode');
        await tester.tap(welcomeGuestBtn.first);
        await tester.pump(const Duration(milliseconds: 800));
        await safeSettle(tester);

        final continueKeyBtn = find.byKey(Key(QaKeys.welcomeContinueBtn));
        final continueTextBtn = find.text('Continue');

        final hasDialog = await waitForAny(
          tester,
          [continueKeyBtn, continueTextBtn],
          timeout: const Duration(seconds: 12),
        );

        if (hasDialog) {
          if (continueKeyBtn.evaluate().isNotEmpty) {
            await tester.tap(continueKeyBtn.first);
          } else if (continueTextBtn.evaluate().isNotEmpty) {
            await tester.tap(continueTextBtn.first);
          }
          await tester.pump(const Duration(milliseconds: 800));
          await safeSettle(tester);
        }
      }

      // 3) Open QA Panel
      await openQaPanel(tester);

      final Map<String, String?> buttonToPageRoot = {
        QaKeys.qaNavHome: QaKeys.pageHomeRoot,
        QaKeys.qaNavSearchResults: QaKeys.searchResultsRoot,
        QaKeys.qaNavCategoryProducts: QaKeys.listingGrid,
        QaKeys.qaNavProductDetail: QaKeys.listingDetailRoot,
        QaKeys.qaNavSavedList: QaKeys.savedListRoot,
        QaKeys.qaNavNotifications: QaKeys.pageNotificationsRoot,
        QaKeys.qaNavProfile: QaKeys.pageProfileRoot,
        QaKeys.qaNavRewardCenter: QaKeys.rewardCenterRulesCard,
        QaKeys.qaNavRules: QaKeys.rewardRulesTitle,
      };

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

      // 4) Navigate buttons
      for (final entry in buttonToPageRoot.entries) {
        final buttonKey = entry.key;
        final pageRootKey = entry.value;

        // ignore: avoid_print
        print('🧪 Testing button: $buttonKey -> $pageRootKey');

        final buttonFinder = find.byKey(Key(buttonKey));
        await scrollUntilVisible(tester, buttonFinder, 60);

        if (buttonFinder.evaluate().isEmpty) {
          debugDumpApp();
          fail('Button $buttonKey should exist in QA Panel');
        }

        await tester.tap(buttonFinder.first);
        await tester.pump(const Duration(milliseconds: 600));
        await safeSettle(tester, maxAttempts: 90);

        if (pageRootKey != null) {
          final ok = await waitForKey(
            tester,
            pageRootKey,
            timeout: const Duration(seconds: 18),
          );

          if (!ok) {
            debugDumpApp();
            fail('Page root key $pageRootKey should appear after tapping $buttonKey');
          }
          // ignore: avoid_print
          print('✅ Page $pageRootKey opened successfully');
        }

        // ✅ robust back to QA Panel
        await ensureBackToQaPanel(tester);
        passed++;
      }

      // 5) Standalone buttons exist
      for (final buttonKey in standaloneButtons) {
        // ignore: avoid_print
        print('🧪 Verifying standalone button: $buttonKey');

        final buttonFinder = find.byKey(Key(buttonKey));
        await scrollUntilVisible(tester, buttonFinder, 60);

        if (buttonFinder.evaluate().isEmpty) {
          debugDumpApp();
          fail('Button $buttonKey should exist in QA Panel');
        }
        passed++;
      }

      // ignore: avoid_print
      print('✅ Full App Smoke passed: $passed/$total checks');
      expect(passed, total, reason: 'All buttons should be tested');
    });
  });
}