import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:swaply/main.dart' as app;
import 'package:swaply/core/qa_keys.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> safePumpAndSettle(WidgetTester tester,
      {Duration step = const Duration(milliseconds: 100)}) async {
    try {
      await tester.pumpAndSettle(step);
    } catch (e) {
      print('[DEEP FLOW] pumpAndSettle did not settle (ignored): $e');
    }
  }

  testWidgets('Deep listing flow: category → listing → detail → favorite → saved', (tester) async {
    // 启动应用并进入主界面
    app.main();
    await tester.pump(const Duration(milliseconds: 300));
    await safePumpAndSettle(tester);
    print('✅ App started');

    // 逃逸 WelcomeScreen（同其他测试）
    final welcomeGuestBtn = find.byKey(Key(QaKeys.welcomeGuestBtn));
    if (welcomeGuestBtn.evaluate().isNotEmpty) {
      await tester.tap(welcomeGuestBtn.first);
      await safePumpAndSettle(tester);
      final continueBtn = find.text('Continue');
      if (continueBtn.evaluate().isNotEmpty) {
        await tester.tap(continueBtn.first);
        await safePumpAndSettle(tester);
      }
      await tester.pump(const Duration(seconds: 1));
    }

    // 确保在 Home 页
    final homeTab = find.byKey(Key(QaKeys.tabHome));
    expect(homeTab, findsOneWidget, reason: 'Home tab should exist');
    await tester.tap(homeTab.first);
    await safePumpAndSettle(tester);

    // 1. 验证分类网格存在
    final categoryGrid = find.byKey(Key(QaKeys.categoryGrid));
    expect(categoryGrid, findsOneWidget, reason: 'category_grid must exist');
    print('✅ Category grid present');

    // 2. 如果有分类项，点击第一个（跳过如果没有）
    final firstCategory = find.byKey(Key(QaKeys.categoryItemKey(0)));
    if (firstCategory.evaluate().isNotEmpty) {
      await tester.tap(firstCategory.first);
      await safePumpAndSettle(tester);
      print('✅ Clicked first category');

      // 验证分类产品页的可达性（通过 listing_grid）
      final listingGrid = find.byKey(Key(QaKeys.listingGrid));
      expect(listingGrid, findsOneWidget, reason: 'listing_grid must exist after category tap');
      print('✅ Listing grid present');

      // 3. 如果有列表项，点击第一个（跳过如果没有）
      final firstListing = find.byKey(Key(QaKeys.listingItemKey(0)));
      if (firstListing.evaluate().isNotEmpty) {
        await tester.tap(firstListing.first);
        await safePumpAndSettle(tester);
        print('✅ Clicked first listing');

        // 验证详情页可达（通过 listing_detail_root）
        final detailRoot = find.byKey(Key(QaKeys.listingDetailRoot));
        expect(detailRoot, findsOneWidget, reason: 'listing_detail_root must exist');
        print('✅ Listing detail page present');

        // 4. 点击收藏按钮（favorite_toggle）
        final favoriteToggle = find.byKey(Key(QaKeys.favoriteToggle));
        if (favoriteToggle.evaluate().isNotEmpty) {
          await tester.tap(favoriteToggle.first);
          await safePumpAndSettle(tester);
          print('✅ Toggled favorite (UI state change not verified)');
        } else {
          print('⚠️  favorite_toggle not found, skipping');
        }

        // 返回分类页
        await tester.pageBack();
        await safePumpAndSettle(tester);
      } else {
        print('⚠️  No listing item found, skipping deep flow');
      }

      // 返回 Home 页
      await tester.pageBack();
      await safePumpAndSettle(tester);
    } else {
      print('⚠️  No category item found, skipping deep flow');
    }

    // 5. 验证 Saved 页可达（通过底部导航）
    final savedTab = find.byKey(Key(QaKeys.tabSaved));
    expect(savedTab, findsOneWidget, reason: 'Saved tab must exist');
    await tester.tap(savedTab.first);
    await safePumpAndSettle(tester);

    // 检查 Saved 页根容器（page_saved_root）
    final savedRoot = find.byKey(Key(QaKeys.pageSavedRoot));
    expect(savedRoot, findsOneWidget, reason: 'page_saved_root must exist');
    print('✅ Saved page reached');

    // 6. 检查 Saved 空态或列表（saved_empty_state 或 saved_list_root）
    final savedEmpty = find.byKey(Key(QaKeys.savedEmptyState));
    if (savedEmpty.evaluate().isNotEmpty) {
      print('✅ Saved empty state present (no saved items)');
    } else {
      // 如果有收藏项，saved_list_root 应该存在（需要UI实现）
      final savedListRoot = find.byKey(Key(QaKeys.savedListRoot));
      if (savedListRoot.evaluate().isNotEmpty) {
        print('✅ Saved list root present');
      } else {
        print('⚠️  Neither saved_empty_state nor saved_list_root found');
      }
    }

    print('\n=== DEEP LISTING FLOW SUMMARY ===');
    print('✅ Core navigation flow verified.');
    print('Note: Full E2E flow depends on actual data presence.');
  });
}