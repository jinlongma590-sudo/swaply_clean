import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest('Minimal test - verify Patrol works', (PatrolIntegrationTester $) async {
    // 最简单的测试：启动应用，检查 Scaffold 是否存在
    await $.pumpAndSettle();
    
    // 使用 Patrol 的查找语法
    final scaffoldFinder = find.byType(Scaffold);
    expect($(scaffoldFinder).exists, isTrue);
  });
}