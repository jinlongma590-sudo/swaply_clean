import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:swaply/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Debug QA FAB presence', (tester) async {
    print('🚀 Starting app...');
    app.main();
    
    // Pump a few times to let app start
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(seconds: 1));
      print('⏳ Pump ${i+1}/8');
    }
    
    print('📋 Dumping widget tree...');
    final tree = debugDumpApp();
    print('Widget tree size: ${tree.length} chars');
    
    // Look for qa_fab in tree
    if (tree.contains("'qa_fab'")) {
      print('✅ Found qa_fab key in widget tree');
      // Extract context around qa_fab
      final idx = tree.indexOf("'qa_fab'");
      final start = idx - 200;
      final end = idx + 200;
      final snippet = tree.substring(start < 0 ? 0 : start, end > tree.length ? tree.length : end);
      print('🔍 Snippet around qa_fab:');
      print(snippet);
    } else {
      print('❌ qa_fab key NOT found in widget tree');
      // Look for FloatingActionButton
      if (tree.contains('FloatingActionButton')) {
        print('⚠️ FloatingActionButton exists but without qa_fab key');
      }
    }
    
    // Look for Scaffold
    if (tree.contains('Scaffold')) {
      print('✅ Scaffold found');
    }
    
    // Force test to pass (we just want the debug output)
    expect(true, isTrue);
  });
}