import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:swaply/main.dart' as app;
import 'package:swaply/core/qa_mode.dart'; // for kQaMode

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Verify QA FAB appears when QA_MODE=true', (tester) async {
    print('🧪 QA_MODE environment value: $kQaMode');
    // Start app
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 10));
    
    print('🔍 Looking for qa_fab...');
    final qaFab = find.byKey(const Key('qa_fab'));
    
    // Dump widget tree for debugging
    debugDumpApp();
    
    if (qaFab.evaluate().isEmpty) {
      print('❌ qa_fab NOT FOUND. Possible issues:');
      print('   1. QA_MODE not set correctly (should be --dart-define=QA_MODE=true)');
      print('   2. kQaMode constant may be false');
      print('   3. FloatingActionButton not added to correct Scaffold');
      print('   4. Widget tree not fully rendered');
      
      // Look for any FloatingActionButton
      final allFab = find.byType(FloatingActionButton);
      print('   Found ${allFab.evaluate().length} FloatingActionButton(s) in total');
      
      // Look for Scaffold
      final scaffold = find.byType(Scaffold);
      print('   Found ${scaffold.evaluate().length} Scaffold(s)');
      
      fail('qa_fab not found when QA_MODE should be true');
    } else {
      print('✅ qa_fab FOUND! Count: ${qaFab.evaluate().length}');
      expect(qaFab, findsOneWidget);
      
      // Try tapping it
      print('👆 Tapping qa_fab...');
      await tester.tap(qaFab.first);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      
      // Check if QaPanelPage opened (look for its key)
      final qaPanel = find.byKey(const Key('qa_panel_page'));
      if (qaPanel.evaluate().isNotEmpty) {
        print('✅ QaPanelPage opened successfully');
      } else {
        print('⚠️ QaPanelPage may not have expected key');
      }
    }
  });
}