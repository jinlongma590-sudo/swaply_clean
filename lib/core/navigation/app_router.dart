// lib/core/navigation/app_router.dart
import 'package:flutter/material.dart';
import 'package:swaply/auth/reset_password_page.dart';

import 'package:swaply/pages/main_navigation_page.dart';
import 'package:swaply/auth/welcome_screen.dart';
import 'package:swaply/auth/login_screen.dart';
import 'package:swaply/auth/register_screen.dart';
import 'package:swaply/auth/forgot_password_screen.dart';

import 'package:swaply/pages/coupon_management_page.dart';
import 'package:swaply/pages/product_detail_page.dart';
import 'package:swaply/pages/sell_form_page.dart';
import 'package:swaply/pages/offer_detail_page.dart'; // ✅ 报价详情页

// ✅ [P3 修复] 新增：补充缺失的命名路由页面
import 'package:swaply/pages/profile_page.dart';
import 'package:swaply/pages/my_listings_page.dart';
import 'package:swaply/pages/wishlist_page.dart';
import 'package:swaply/pages/saved_page.dart' as saved; // ✅ 使用别名避免冲突
import 'package:swaply/pages/category_products_page.dart';
import 'package:swaply/pages/search_results_page.dart';
import 'package:swaply/pages/notification_page.dart' as notif; // ✅ 使用别名避免冲突
import 'package:swaply/pages/seller_profile_page.dart';
import 'package:swaply/pages/account_settings_page.dart';

/// ===============================================================
/// AppRouter
/// - '/' 交由会话决定：有会话 → Home；无会话 → Welcome
/// - 统一 fade 动画
/// - 路由：/home /welcome /login /register /forgot-password
///        /sell-form /listing /offer-detail
///        /profile /my-listings /wishlist /saved /category
///        /search /notification /seller-profile /account-settings
/// ===============================================================
class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final String name = settings.name ?? '/';
    // ✅ [P0 修复] hasSession 不再在此处使用，登录状态由 AuthFlowObserver 统一处理
    // final bool hasSession = Supabase.instance.client.auth.currentSession != null;

    switch (name) {
      /* ================= 顶层入口 ================= */
      case '/':
        // ✅ [P0 修复] 始终返回 MainNavigationPage
        // 登录状态由 AuthFlowObserver 在 initialSession 事件中处理
        // 未登录用户会被 AuthFlowObserver 自动跳转到 /welcome
        return _fade(const MainNavigationPage(), '/');

      /* ================= 主导航 ================= */
      case '/home':
        return _fade(const MainNavigationPage(), '/home');

      /* ================= 认证流程 ================= */
      case '/welcome':
        return _fade(const WelcomeScreen(), '/welcome');

      case '/login':
        return _fade(const LoginScreen(), '/login');

      case '/register':
        return _fade(const RegisterScreen(), '/register');

      case '/forgot-password':
        return _fade(const ForgotPasswordScreen(), '/forgot-password');

      case '/reset-password':
        // ✅ 传递完整的arguments，让ResetPasswordPage自己提取参数
        final args = settings.arguments as Map<String, dynamic>?;
        final token = args?['token'] as String?;
        return _fade(
          ResetPasswordPage(token: token),
          '/reset-password',
          arguments: settings.arguments, // ✅ 关键：传递完整arguments
        );

      /* ================= 我的优惠券 ================= */
      case '/coupons':
        return _fade(const CouponManagementPage(), '/coupons');

      /* ================= 发布页 ================= */
      case '/sell-form':
        return _fade(const SellFormPage(), '/sell-form');

      /* ================= 商品详情 =================
       * 支持：
       *   navPush('/listing', arguments: 'productId')
       *   navPush('/listing', arguments: {'id': 'productId'})
       * ========================================== */
      case '/listing':
        {
          final args = settings.arguments;
          String productId = '';

          if (args is String) {
            productId = args;
          } else if (args is Map && args['id'] != null) {
            productId = '${args['id']}';
          }

          return _fade(
            ProductDetailPage(productId: productId),
            '/listing',
          );
        }

      /* ================= 报价详情 =================
       * 支持：
       *   navPush('/offer-detail', arguments: 'offerId')
       *   navPush('/offer-detail', arguments: {'offerId': '...'} 或 {'offer_id': '...'} 或 {'id': '...'})
       * 说明：
       *   OfferDetailPage 当前只接收 offerId，不再传 listingId（否则会报 named parameter 未定义）。
       * ========================================== */
      case '/offer-detail':
        {
          final args = settings.arguments;
          String offerId = '';

          if (args is String) {
            offerId = args;
          } else if (args is Map) {
            offerId = (args['offerId'] ?? args['offer_id'] ?? args['id'] ?? '')
                .toString();
          }

          if (offerId.isEmpty) {
            // 兜底，避免进到错误页面
            return _fade(const MainNavigationPage(), '/home');
          }

          return _fade(
            OfferDetailPage(offerId: offerId), // ✅ 仅传 offerId
            '/offer-detail',
          );
        }

      /* ================= [P3 修复] 补充缺失的命名路由 ================= */

      case '/profile':
        return _fade(const ProfilePage(), '/profile');

      case '/my-listings':
        return _fade(const MyListingsPage(), '/my-listings');

      case '/wishlist':
        return _fade(const WishlistPage(), '/wishlist');

      case '/saved':
        // ✅ 使用别名引用，避免与 main_navigation_page.dart 中的定义冲突
        return _fade(const saved.SavedPage(), '/saved');

      case '/category':
        {
          final args = settings.arguments as Map<String, dynamic>?;
          // ✅ CategoryProductsPage 需要 categoryId 和 categoryName 参数
          final categoryId = args?['categoryId'] as String? ??
              args?['category_id'] as String? ??
              '';
          final categoryName = args?['categoryName'] as String? ??
              args?['category_name'] as String? ??
              '';
          return _fade(
            CategoryProductsPage(
                categoryId: categoryId, categoryName: categoryName),
            '/category',
          );
        }

      case '/search':
        {
          final args = settings.arguments as Map<String, dynamic>?;
          // ✅ SearchResultsPage 需要 keyword 参数
          final keyword =
              args?['keyword'] as String? ?? args?['query'] as String? ?? '';
          return _fade(SearchResultsPage(keyword: keyword), '/search');
        }

      case '/notification':
        // ✅ 使用别名引用，避免与 main_navigation_page.dart 中的定义冲突
        return _fade(const notif.NotificationPage(), '/notification');

      case '/seller-profile':
        {
          final args = settings.arguments as Map<String, dynamic>?;
          final sellerId = args?['seller_id'] as String? ??
              args?['sellerId'] as String? ??
              '';
          // ✅ 实际类名是 SellerProfileViewPage
          return _fade(
              SellerProfileViewPage(sellerId: sellerId), '/seller-profile');
        }

      case '/account-settings':
        return _fade(const AccountSettingsPage(), '/account-settings');

      /* ================= Fallback ================= */
      default:
        return _fade(const MainNavigationPage(), '/home');
    }
  }

  // 统一 fade 动画
  // ✅ 修复：添加 arguments 参数，确保 RouteSettings 能传递参数给目标页面
  //    目标页面可通过 ModalRoute.of(context)?.settings.arguments 获取参数
  static PageRoute _fade(Widget page, String name, {Object? arguments}) {
    return PageRouteBuilder(
      settings: RouteSettings(name: name, arguments: arguments),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    );
  }
}
