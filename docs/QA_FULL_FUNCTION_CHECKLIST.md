# QA 全功能覆盖检查清单

即使 CI 抽风，也能通过本清单在 10 分钟内手动验证所有核心功能。

## 使用说明

1. **环境准备**：
   - 启动应用（QA_MODE=true）
   - 进入主界面（点击 "Browse as Guest"）
   - 点击右上角 QA 浮动按钮（`qa_fab`）打开 QA Panel

2. **验证方法**：
   - 按顺序点击 QA Panel 中的每个按钮
   - 检查目标页面是否成功打开
   - 检查页面根 Key 是否存在（使用 Flutter Inspector 或测试断言）
   - 在 Pass/Fail 列打勾/打叉

3. **预期结果**：
   - 每个功能点应有对应的页面根 Key
   - 页面应正常渲染，无崩溃
   - 导航应流畅，能返回 QA Panel

---

## 功能检查清单

| 序号 | 功能模块 | QA Panel 按钮 Key | 目标页面 | 预期根 Key | 验证要点 | Pass/Fail | 备注 |
|------|----------|-------------------|----------|------------|----------|-----------|------|
| 1 | **Home** | `qa_nav_home` | HomePage | `page_home_root` | 首页正常显示，有搜索框和分类网格 | □ | |
| 2 | **Search Results** | `qa_nav_search_results` | SearchResultsPage | `search_results_root` | 搜索结果显示网格，有查询参数 | □ | 使用预设关键词 "test" |
| 3 | **Category Products** | `qa_nav_category_products` | CategoryProductsPage | `listing_grid` | 分类商品列表，有分页加载 | □ | 使用分类 "vehicles" |
| 4 | **Product Detail** | `qa_nav_product_detail` | ProductDetailPage | `listing_detail_root` | 商品详情页，有图片、标题、价格 | □ | 需要 mock 商品 ID |
| 5 | **Favorite Toggle** | `qa_nav_favorite_toggle` | ProductDetailPage | `favorite_toggle` | 收藏按钮可点击，状态切换 | □ | 需在商品详情页测试 |
| 6 | **Saved List** | `qa_nav_saved_list` | SavedPage | `page_saved_root` | 收藏列表页，有空状态处理 | □ | |
| 7 | **Sell Mock Publish** | `qa_nav_sell_mock_publish` | SellPage | `page_sell_root` | 发布页，有 QA Mock 发布按钮 | □ | 点击 `qa_mock_publish_button` 应显示成功提示 |
| 8 | **Notifications** | `qa_nav_notifications` | NotificationPage | `page_notifications_root` | 通知列表页 | □ | |
| 9 | **Profile** | `qa_nav_profile` | ProfilePage | `page_profile_root` | 个人资料页，有 Reward Center 入口 | □ | 检查 `profile_reward_center_entry` |
| 10 | **Reward Center** | `qa_nav_reward_center` | RewardCenterPage | - | 奖励中心页，有规则卡片 | □ | 检查 `reward_center_rules_card` |
| 11 | **Reward Rules** | `qa_nav_rules` | RewardRulesPage | `reward_rules_title` | 规则页面，有奖池详情 | □ | |
| 12 | **Reward BottomSheet** | `qa_open_reward_bottomsheet` | RewardBottomSheet | - | 奖励弹窗，有转盘和规则按钮 | □ | 检查 `reward_rules_btn`、`reward_pool_tile` |

---

## 关键断言（自动化测试应检查）

1. **页面可达性**：每个导航按钮都能打开对应页面
2. **根 Key 存在**：每个页面都有唯一的根 Key，用于测试断言
3. **核心交互**：
   - 搜索框可输入 (`search_input`)
   - 分类网格可点击 (`category_grid`)
   - 收藏按钮可切换 (`favorite_toggle`)
   - Mock 发布可触发成功提示 (`qa_mock_publish_success`)
4. **奖励功能**：
   - 奖励弹窗可打开转盘
   - 规则页面可查看奖池详情
   - 奖励中心可查看历史记录

---

## 手动验证步骤（10 分钟流程）

1. **启动应用**：
   ```bash
   flutter run --dart-define=QA_MODE=true
   ```

2. **进入主界面**：
   - 点击 "Browse as Guest"
   - 点击对话框 "Continue"
   - 等待加载完成

3. **打开 QA Panel**：
   - 点击右上角浮动按钮（`qa_fab`）

4. **按顺序验证**（从上到下）：
   - 点击每个按钮，确认页面打开
   - 检查页面关键元素
   - 返回 QA Panel，继续下一个

5. **记录结果**：
   - 在表格中标记 Pass/Fail
   - 记录任何异常或崩溃

---

## 已知问题与待修复项

1. **Key 断裂问题**：部分 Key 常量在代码中未使用（静态审计已发现 20+ 缺失）
2. **Mock 数据依赖**：商品详情、分类页面需要 mock 数据
3. **网络依赖**：部分页面需要后端数据，测试环境需确保可用
4. **CI 稳定性**：Android 模拟器启动可能失败，需备用方案

---

## 紧急情况处理

如果 CI 完全无法运行：

1. **使用本清单手动验证**核心功能
2. **重点关注**：Home, Search, Sell, Reward（业务核心）
3. **临时绕过**：非关键功能可标记为 "暂不测试"
4. **回归测试**：修复后重新验证失败项

**最后更新**：2026-02-08  
**维护者**：OpenClaw QA 自动化系统