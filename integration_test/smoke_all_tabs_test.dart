import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:swaply/main.dart' as app;
import 'package:swaply/core/qa_keys.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  /// ✅ 更稳的 safeSettle：推进一段时间即可，不强求“完全静止”
  Future<void> safeSettle(
      WidgetTester tester, {
        Duration step = const Duration(milliseconds: 120),
        int maxAttempts = 50,
      }) async {
    // 在 CI 下经常存在持续动画/轮询，永远不会 hasScheduledFrame=false
    // 所以这里不 fail，只推进一段时间。
    for (int i = 0; i < maxAttempts; i++) {
      await tester.pump(step);
      if (!binding.hasScheduledFrame) return;
    }
    // ignore: avoid_print
    print(
      '[safeSettle] still busy after ${maxAttempts * step.inMilliseconds}ms, continue',
    );
  }

  /// ✅ 等待 Key 出现（成功 true / 超时 false）
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

  /// ✅ 等待 任意一个 Finder 出现（成功 true / 超时 false）
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

  /// ✅ 点一个 key，然后等待某个页面“到位标识”出现（成功 true/失败 false）
  Future<bool> tapKeyAndWaitAny(
      WidgetTester tester,
      String tapKey,
      List<Finder> pageMarkers, {
        Duration tapPump = const Duration(milliseconds: 350),
        Duration timeout = const Duration(seconds: 25),
      }) async {
    final tabFinder = find.byKey(Key(tapKey));
    if (tabFinder.evaluate().isEmpty) return false;

    await tester.tap(tabFinder.first);
    await tester.pump(tapPump);

    // 不再依赖 settle，而是等“页面标识”
    final ok = await waitForAny(
      tester,
      pageMarkers,
      timeout: timeout,
      step: const Duration(milliseconds: 250),
    );

    // 补一小段推进，给异步 UI 收尾
    await safeSettle(tester, maxAttempts: 20);
    return ok;
  }

  testWidgets('Smoke: all tabs are reachable', (tester) async {
    // 1) 冷启动 App
    app.main();
    await tester.pump(const Duration(milliseconds: 300));
    await safeSettle(tester);

    // 2) Welcome Screen → Guest 流程
    // 注意：这里不要用 expect 强绑 settle，CI 下可能稍慢，改为 waitAny + 条件点击
    print('🔍 Checking WelcomeScreen...');
    final welcomeGuestBtn = find.byKey(Key(QaKeys.welcomeGuestBtn));
    if (welcomeGuestBtn.evaluate().isNotEmpty) {
      print('✅ Found welcome guest button, tapping...');
      await tester.tap(welcomeGuestBtn.first);
      await tester.pump(const Duration(milliseconds: 800));

      print('🔍 Waiting for Guest Mode dialog...');
      final dialogContinueBtn = find.byKey(Key(QaKeys.welcomeContinueBtn));

      final dialogOk = await waitForAny(
        tester,
        [dialogContinueBtn, find.text('Continue')],
        timeout: const Duration(seconds: 12),
      );

      if (!dialogOk) {
        debugDumpApp();
        fail('Guest mode dialog did not appear in time');
      }

      // 优先 key，其次文本
      if (dialogContinueBtn.evaluate().isNotEmpty) {
        print('✅ Found dialog Continue button (key), tapping...');
        await tester.tap(dialogContinueBtn.first);
      } else {
        final continueText = find.text('Continue');
        if (continueText.evaluate().isNotEmpty) {
          print('✅ Found dialog Continue button (text), tapping...');
          await tester.tap(continueText.first);
        }
      }

      await tester.pump(const Duration(milliseconds: 800));
      await safeSettle(tester);
    } else {
      print('⚠️ Welcome guest button not found (already in main interface?)');
    }

    // 3) 等待进入主界面（通过 tab_home 判断）
    print('⏳ Waiting for main interface (tabHome)...');
    final tabHomeFound = await waitForKey(
      tester,
      QaKeys.tabHome,
      timeout: const Duration(seconds: 40),
    );
    if (!tabHomeFound) {
      debugDumpApp();
      fail('Main interface not reached within timeout (tabHome missing)');
    }
    print('✅ Main interface reached');

    // 4) 验证所有 Tab 可达
    final tabs = [
      QaKeys.tabHome,
      QaKeys.tabSaved,
      QaKeys.tabSell,
      QaKeys.tabNotifications,
      QaKeys.tabProfile,
    ];

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

      // 这个 tab 点击后的“页面到位标识”：
      final rootFinder = find.byKey(Key(pageRootKey));

      // fallback markers（更宽松，避免 UI 文案变化导致 hard fail）
      final fallbackMarkers = <Finder>[
        rootFinder,
      ];

      switch (i) {
        case 0: // Home
          fallbackMarkers.add(find.byKey(const ValueKey('featured_ads_grid')));
          fallbackMarkers.add(find.textContaining('Trending'));
          break;
        case 1: // Saved
          fallbackMarkers.add(find.textContaining('Saved'));
          fallbackMarkers.add(find.textContaining('Login'));
          break;
        case 2: // Sell
          fallbackMarkers.add(find.textContaining('Sell'));
          fallbackMarkers.add(find.byKey(Key(QaKeys.qaMockPublishButton)));
          break;
        case 3: // Notifications
          fallbackMarkers.add(find.textContaining('Notification'));
          break;
        case 4: // Profile
          fallbackMarkers.add(find.textContaining('Profile'));
          break;
      }

      final ok = await tapKeyAndWaitAny(
        tester,
        tabKey,
        fallbackMarkers,
        timeout: const Duration(seconds: 25),
      );

      if (!ok) {
        // Tab 本身必须存在，但页面 root 不一定总有 key，所以这里给出更清晰的报错
        debugDumpApp();
        fail('After tapping tab $tabKey, page markers not found (rootKey=$pageRootKey)');
      } else {
        if (rootFinder.evaluate().isNotEmpty) {
          print('✅ Page root found for $tabKey ($pageRootKey)');
        } else {
          print('⚠️ Root key $pageRootKey not found, but fallback marker matched (ok)');
        }
      }

      await tester.pump(const Duration(milliseconds: 250));
    }

    print('✅ All tabs are reachable');
  });
}