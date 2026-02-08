// 最简单的 Patrol 测试，验证框架能工作
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest('verification: Patrol framework works', ($) async {
    // 最简单的测试：启动一个基础界面
    await $.pumpWidgetAndSettle(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Test')),
          body: const Center(child: Text('Hello')),
        ),
      ),
    );
    
    expect($('Test'), findsOneWidget);
    expect($('Hello'), findsOneWidget);
  });
}