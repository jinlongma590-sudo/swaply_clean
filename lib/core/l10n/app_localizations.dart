import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    // 你当前项目里是固定英文，如果后面做多语言再接 context
    return AppLocalizations(const Locale('en'));
  }

  // ✅ 新增：maybeOf，兼容调用方
  static AppLocalizations? maybeOf(BuildContext context) {
    return AppLocalizations.of(context);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
  _AppLocalizationsDelegate();

  // ---------- Generic / Auth ----------
  String get appTitle => 'Swaply';
  String get loginRequired => 'Login required';
  String loginRequiredMessage(String feature) => 'Please login to use $feature.';
  String get cancel => 'Cancel';
  String get login => 'Login';
  String get logout => 'Logout';
  String get createAccount => 'Create account';
  String get alreadyHaveAccount => 'Already have an account?';
  String get signUpNow => 'Sign up now';
  String get signUpToUnlock => 'Sign up to unlock the features below';
  String get verification => 'Verification';
  String get accountVerification => 'Account verification';
  String get notVerified => 'Not verified';
  String get about => 'About';
  String get settings => 'Settings';
  String get helpSupport => 'Help & Support';

  // ---------- Tabs / Common ----------
  String get home => 'Home';
  String get saved => 'Saved';
  String get sell => 'Sell';
  String get notifications => 'Notifications';
  String get profile => 'Profile';
  String get favorites => 'Favorites';
  String get rating => 'Rating';

  // ---------- Home ----------
  String get whatLookingFor => 'What are you looking for?';
  String get allZimbabwe => 'All Zimbabwe';
  String get searchPlaceholder => 'Search...';

  // Categories
  String get trending => 'Trending';
  String get vehicles => 'Vehicles';
  String get property => 'Property';
  String get beauty => 'Beauty & Personal Care';
  String get jobs => 'Jobs';
  String get babiesKids => 'Babies & Kids';
  String get services => 'Services';
  String get leisure => 'Leisure Activities';
  String get repairConst => 'Repair & Construction';
  String get furniture => 'Home, Furniture & Appliances';
  String get pets => 'Pets';
  String get electronics => 'Electronics';
  String get phones => 'Phones & Tablets';
  String get seekingWork => 'Seeking Work & CVs';
  String get fashion => 'Fashion';
  String get foodDrinks => 'Food, Agriculture & Drinks';

  // ---------- Saved ----------
  String get myFavorites => 'My Favorites';
  String get loginToSaveFavorites =>
      'Login to save your favorite items and searches.';
  String get loginNow => 'Login now';
  String get ads => 'Ads';
  String get searches => 'Searches';
  String get noFavoriteAdsYet => 'No favorite ads yet';
  String get favoritesHelp =>
      'Tap the bookmark icon on a listing to add it to Favorites.';
  String get browseItems => 'Browse items';
  String get removedFromFavorites => 'Removed from favorites';
  String get alertsEnabled => 'Alerts enabled';
  String get searchingFor => 'Searching for';
  String get savedOn => 'saved on';
  String get wishlist => 'Wishlist';
  String get noSavedSearches => 'No saved searches';

  // ---------- Sell ----------
  String get sellItem => 'Sell Item';
  String get loginToPost => 'Login to post your listings.';
  String get sellYourItems => 'Sell your items';
  String get takePhotoAndSell => 'Take a photo and sell in minutes.';
  String get postNewAd => 'Post new ad';
  String get myListings => 'My Listings';
  String get newAd => 'New Ad';
  String get noTitle => 'No title';
  String get noPrice => 'No price';
  String get views => 'views';
  String get totalViews => 'Total views';
  String get likes => 'likes';
  String get edit => 'Edit';
  String get promote => 'Promote';
  String get delete => 'Delete';
  String get editModeComingSoon => 'Edit mode is coming soon';
  String get editFeatureComingSoon => 'Edit feature is coming soon';
  String get listingDeleted => 'Listing deleted';
  String get promoteFeatureComingSoon => 'Promote feature is coming soon';
  String get activeAds => 'Active ads';
  String get navigateToSellTab => 'Navigate to Sell tab';
  String get navigateToSavedTab => 'Navigate to Saved tab';
  String get myPurchases => 'My Purchases';
  String get postListings => 'post listings';

  // ---------- Notifications ----------
  String get notificationDeleted => 'Notification deleted';
  String get loginToReceiveNotifications => 'Login to receive notifications.';
  String get markAllAsRead => 'Mark all as read';
  String get clearAll => 'Clear all';
  String get noNotifications => 'No notifications';
  String get notificationsWillAppearHere => 'Your notifications will appear here.';
  String get receiveNotifications => 'Login to receive notifications.';

  // ---------- Profile ----------
  String get guestUser => 'Guest user';
  String get browseWithoutAccount => 'Browsing without an account';
  String memberSince(String m) => 'Member since $m';
  String get editProfile => 'Edit Profile';

  // ---------- Cities ----------
  String get harare => 'Harare';
  String get bulawayo => 'Bulawayo';
  String get chitungwiza => 'Chitungwiza';
  String get mutare => 'Mutare';
  String get gweru => 'Gweru';
  String get kwekwe => 'Kwekwe';
  String get kadoma => 'Kadoma';
  String get masvingo => 'Masvingo';
  String get chinhoyi => 'Chinhoyi';
  String get chegutu => 'Chegutu';
  String get bindura => 'Bindura';
  String get marondera => 'Marondera';
  String get redcliff => 'Redcliff';

  // ---------- Variants / Typos ----------
  String get saveItems => 'Save items';
  String get saveltems => 'Save items'; // l/I 手误兼容

  // ---------- Welcome Gift (新增补齐) ----------
  String get welcomeGiftTitle => 'Welcome gift 🎁';
  String get welcomeGiftContent =>
      'You received a special welcome coupon! Enjoy using Swaply.';
  String get later => 'Later';
  String get viewCoupons => 'My Coupons';

  @override
  dynamic noSuchMethod(Invocation invocation) => '';
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(
        AppLocalizations(const Locale('en')),
      );

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
