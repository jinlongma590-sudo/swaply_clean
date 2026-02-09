import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol/patrol.dart';
import 'package:swaply/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  patrolTest('Minimal test: app launches', ($) async {
    app.main();
    await $.pumpAndSettle();
    
    // Just verify something basic exists
    expect(find.byType(Scaffold), findsOneWidget);
  });
}