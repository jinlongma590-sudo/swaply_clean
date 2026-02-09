import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:swaply/main.dart' as app;
import 'package:swaply/core/qa_keys.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  // ========= Config =========
  const step = Duration(milliseconds: 120);
  const hardStepLimit = 120;
  
  // ========= Auto Login =========
  const qaEmail = String.fromEnvironment('QA_EMAIL', defaultValue: '');
  const qaPass = String.fromEnvironment('QA_PASS', defaultValue: '');

  Future<void> ensureLoggedIn(WidgetTester tester) async {
    // Check if already logged in (home tab exists)
    final homeTabFinder = find.byKey(const Key(QaKeys.tabHome));
    if (homeTabFinder.evaluate().isNotEmpty) {
      print('✅ Already logged in');
      return;
    }

    // Try to find welcome sign in button
    final signInBtn = find.byKey(const Key(QaKeys.welcomeSignInBtn));
    if (signInBtn.evaluate().isEmpty) {
      // Try text alternative
      final signInText = find.textContaining('Sign In');
      if (signInText.evaluate().isNotEmpty) {
        await tester.tap(signInText.first);
      } else {
        throw Exception('Could not find Sign In button');
      }
    } else {
      await tester.tap(signInBtn);
    }

    await tester.pumpAndSettle(step);
    
    // Wait for login page
    final emailInput = find.byKey(const Key('login_email_input'));
    await waitForFinder(tester, emailInput, timeout: Duration(seconds: hardStepLimit * step.inSeconds ~/ 1000));

    if (qaEmail.isEmpty || qaPass.isEmpty) {
      throw Exception('QA_EMAIL or QA_PASS not provided');
    }

    // Enter credentials
    await tester.enterText(emailInput, qaEmail);
    await tester.pump(step);
    
    final passwordInput = find.byKey(const Key('login_password_input'));
    await tester.enterText(passwordInput, qaPass);
    await tester.pump(step);
    
    final submitBtn = find.byKey(const Key('login_submit_btn'));
    await tester.tap(submitBtn);
    
    // Wait for navigation to home
    await waitForFinder(tester, homeTabFinder, timeout: Duration(seconds: hardStepLimit * 2 * step.inSeconds ~/ 1000));
  }

  Future<void> waitForFinder(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 30),
    Duration step = const Duration(milliseconds: 250),
  }) async {
    final endTime = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(endTime)) {
      await tester.pump(step);
      if (finder.evaluate().isNotEmpty) return;
    }
    throw TimeoutException('waitForFinder timed out after ${timeout.inSeconds}s');
  }

  Future<void> safeTap(WidgetTester tester, String key, {String? label}) async {
    final finder = find.byKey(Key(key));
    await waitForFinder(tester, finder);
    await tester.tap(finder);
    await tester.pump(step * 3);
  }

  testWidgets('Deep Link: QA Panel buttons exist and can be tapped', (WidgetTester tester) async {
    // Start app
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Ensure logged in
    await ensureLoggedIn(tester);

    // Navigate to QA Panel via qa_fab
    final qaFab = find.byKey(const Key(QaKeys.qaFab));
    await waitForFinder(tester, qaFab);
    await tester.tap(qaFab);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify Deep Link section exists
    expect(find.text('Deep Link Testing (A1)'), findsOneWidget);

    // Verify each deep link button exists
    final deepLinkButtons = [
      QaKeys.qaDeeplinkHome,
      QaKeys.qaDeeplinkSaved,
      QaKeys.qaDeeplinkCategory,
      QaKeys.qaDeeplinkRewardCenter,
      QaKeys.qaDeeplinkListingDetail,
    ];

    for (final key in deepLinkButtons) {
      final button = find.byKey(Key(key));
      expect(button, findsOneWidget, reason: 'Deep link button $key should exist');
    }

    print('✅ All deep link buttons exist in QA Panel');
  });

  testWidgets('Deep Link: Home deep link navigation', (WidgetTester tester) async {
    // This test would require actual deep link triggering via adb
    // For now, we just verify the button exists and can be tapped
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await ensureLoggedIn(tester);

    // Navigate to QA Panel
    final qaFab = find.byKey(const Key(QaKeys.qaFab));
    await pumpUntil(tester, () => qaFab.evaluate().isNotEmpty);
    await tester.tap(qaFab);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Tap Home deep link button
    final homeDeeplinkBtn = find.byKey(const Key(QaKeys.qaDeeplinkHome));
    await tester.tap(homeDeeplinkBtn);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify snackbar appears
    expect(find.text('Deep Link: Home triggered'), findsOneWidget);
    
    print('✅ Home deep link button works (UI only)');
  });

  testWidgets('Deep Link: Saved deep link navigation', (WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await ensureLoggedIn(tester);

    // Navigate to QA Panel
    final qaFab = find.byKey(const Key(QaKeys.qaFab));
    await pumpUntil(tester, () => qaFab.evaluate().isNotEmpty);
    await tester.tap(qaFab);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Tap Saved deep link button
    final savedDeeplinkBtn = find.byKey(const Key(QaKeys.qaDeeplinkSaved));
    await tester.tap(savedDeeplinkBtn);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify snackbar appears
    expect(find.text('Deep Link: Saved triggered'), findsOneWidget);
    
    print('✅ Saved deep link button works (UI only)');
  });

  // Note: Actual deep link testing via adb would require:
  // 1. adb shell am start -a android.intent.action.VIEW -d "cc.swaply.app://home" cc.swaply.app
  // 2. Verifying the app navigates to correct page
  // This is left as future implementation for CI integration
}