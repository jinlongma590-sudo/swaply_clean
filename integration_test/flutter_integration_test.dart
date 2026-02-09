// Flutter 原生 integration_test（不使用 Patrol）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:swaply/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App launches and shows home page', (WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle();
    
    // Verify home page elements exist
    expect(find.byType(Scaffold), findsOneWidget);
  });
}