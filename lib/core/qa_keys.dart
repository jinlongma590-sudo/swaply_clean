/// QA自动化测试专用的Key常量集中管理
/// 
/// 所有测试相关控件必须使用本类中的常量，禁止散落字符串。
/// 新增Key时：1) 这里添加常量 2) 替换代码中的字符串Key 3) 验证测试
class QaKeys {
  // ===== 全局入口 =====
  static const String qaFab = 'qa_fab';
  static const String qaPanelEntry = 'qa_panel_entry';
  
  // ===== Welcome/登录流程 =====
  static const String welcomeGuestBtn = 'welcome_guest_btn';
  static const String welcomeContinueBtn = 'welcome_continue_btn'; // 对话框中的Continue按钮
  static const String welcomeGetStartedBtn = 'welcome_get_started_btn';
  static const String welcomeSignInBtn = 'welcome_sign_in_btn';
  
  // ===== 主界面底部导航 =====
  static const String tabHome = 'tab_home';
  static const String tabSaved = 'tab_saved';
  static const String tabSell = 'tab_sell';
  static const String tabNotifications = 'tab_notifications';
  static const String tabProfile = 'tab_profile';
  
  // ===== 页面根容器（用于断言页面可达） =====
  static const String pageHomeRoot = 'page_home_root';
  static const String pageSavedRoot = 'page_saved_root';
  static const String pageSellRoot = 'page_sell_root';
  static const String pageNotificationsRoot = 'page_notifications_root';
  static const String pageProfileRoot = 'page_profile_root';
  
  // ===== Reward/奖励相关 =====
  static const String rewardRulesBtn = 'reward_rules_btn';
  static const String rewardPoolTile = 'reward_pool_tile';
  static const String rewardPoolScroll = 'reward_pool_scroll';
  static const String rewardCenterRulesCard = 'reward_center_rules_card';
  static const String rewardCenterHistory = 'reward_center_history';
  static const String rewardRulesTitle = 'reward_rules_title';
  static const String rewardRulesPoolTile = 'reward_rules_pool_tile';
  static const String rewardRulesPoolScroll = 'reward_rules_pool_scroll';
  
  // ===== QA Panel内部按钮 =====
  static const String qaNavRewardCenter = 'qa_nav_reward_center';
  static const String qaNavRules = 'qa_nav_rules';
  static const String qaOpenRewardBottomSheet = 'qa_open_reward_bottomsheet';
  static const String qaSeedPoolMock = 'qa_seed_pool_mock';
  static const String qaQuickPublish = 'qa_quick_publish';
  static const String qaSmokeOpenTabs = 'qa_smoke_open_tabs';
  static const String qaDebugLog = 'qa_debug_log';
  static const String qaRunRewardChecks = 'qa_run_reward_checks'; // 可能需要添加
  // ===== 全功能导航按钮（C1扩展） =====
  static const String qaNavHome = 'qa_nav_home';
  static const String qaNavSearchResults = 'qa_nav_search_results';
  static const String qaNavCategoryProducts = 'qa_nav_category_products';
  static const String qaNavProductDetail = 'qa_nav_product_detail';
  static const String qaNavFavoriteToggle = 'qa_nav_favorite_toggle';
  static const String qaNavSavedList = 'qa_nav_saved_list';
  static const String qaNavSellMockPublish = 'qa_nav_sell_mock_publish';
  static const String qaNavNotifications = 'qa_nav_notifications';
  static const String qaNavProfile = 'qa_nav_profile';
  
  // ===== 搜索/分类/详情页 =====
  static const String searchInput = 'search_input';
  static const String searchButton = 'search_button';
  static const String categoryGrid = 'category_grid';
  static const String categoryItem = 'category_item_'; // 前缀，需拼接索引
  static const String listingGrid = 'listing_grid';
  static const String listingItem = 'listing_item_'; // 前缀，需拼接索引
  static const String listingDetailRoot = 'listing_detail_root';
  static const String favoriteButton = 'favorite_button';
  static const String unfavoriteButton = 'unfavorite_button';
  static const String favoriteToggle = 'favorite_toggle'; // 统一收藏按钮
  
  // ===== Saved页面空态 =====
  static const String savedEmptyState = 'saved_empty_state';
  
  // ===== Sell/发布页面 =====
  static const String sellFormRoot = 'sell_form_root';
  static const String sellTitleInput = 'sell_title_input';
  static const String sellPriceInput = 'sell_price_input';
  static const String sellCategoryDropdown = 'sell_category_dropdown';
  static const String sellDescriptionInput = 'sell_description_input';
  static const String sellSubmitButton = 'sell_submit_button';
  static const String qaMockPublishButton = 'qa_mock_publish_button'; // QA_MODE下的模拟发布按钮
  static const String qaMockPublishSuccess = 'qa_mock_publish_success'; // QA Mock发布成功的SnackBar
  
  // ===== Profile/设置页面 =====
  static const String profileRewardCenterEntry = 'profile_reward_center_entry';
  static const String profileSettingsEntry = 'profile_settings_entry';
  
  // ===== 搜索结果页 =====
  static const String searchResultsRoot = 'search_results_root';
  
  // ===== Saved列表页 =====
  static const String savedListRoot = 'saved_list_root';
  
  // ===== 辅助方法：生成带索引的Key =====
  static String categoryItemKey(int index) => '$categoryItem$index';
  static String listingItemKey(int index) => '$listingItem$index';
  
  // ===== 辅助方法：生成带slug的Key =====
  static String categoryItemKeyBySlug(String slug) => '$categoryItem$slug';
}