// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swaply/core/app.dart'; // ✅ 从 app.dart 引入 SwaplyApp（pubspec name: swaply）

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders SwaplyApp root', (WidgetTester tester) async {
    await tester.pumpWidget(const SwaplyApp());
    // 只校验根 MaterialApp 是否渲染，避免依赖具体页面文案/按钮
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
