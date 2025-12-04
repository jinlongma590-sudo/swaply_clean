// lib/l10n/app_localizations.dart
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  // Generic
  String get appTitle => 'Swaply';
  String get loginRequired => 'Login required';
  String loginRequiredMessage(String feature) =>
      'Please login to use $feature.';
  String get cancel => 'Cancel';
  String get login => 'Login';

  // Bottom tabs
  String get home => 'Home';
  String get saved => 'Saved';
  String get sell => 'Sell';
  String get notifications => 'Notifications';
  String get profile => 'Profile';

  // Home header
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

  // Saved
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

  // Sell
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
  String get likes => 'likes';
  String get edit => 'Edit';
  String get promote => 'Promote';
  String get delete => 'Delete';
  String get editFeatureComingSoon => 'Edit feature is coming soon';
  String get listingDeleted => 'Listing deleted';
  String get promoteFeatureComingSoon => 'Promote feature is coming soon';

  // Notifications
  String get notificationDeleted => 'Notification deleted';
  String get markAllAsRead => 'Mark all as read';
  String get clearAll => 'Clear all';
  String get noNotifications => 'No notifications';
  String get notificationsWillAppearHere =>
      'Your notifications will appear here.';

  // Profile
  String get guestUser => 'Guest user';
  String get browseWithoutAccount => 'Browsing without an account';
  String memberSince(String monthYear) => 'Member since $monthYear';
  String get helpSupport => 'Help & Support';
  String get settings => 'Settings';

  // Cities
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
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => const ['en'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return SynchronousFuture<AppLocalizations>(
        AppLocalizations(const Locale('en')));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
