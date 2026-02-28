-- ============================================================================
-- Swaply 后端RPC性能优化脚本
-- 目标：解决 get_random_trending_ads 函数性能问题（当前耗时2.3-5.3秒）
-- 执行方法：复制到Supabase控制台SQL编辑器执行
-- ============================================================================

-- ============================================================================
-- 第一部分：创建关键索引（立即生效，性能提升显著）
-- ============================================================================

-- 1. pinned_ads表核心查询索引
CREATE INDEX IF NOT EXISTS idx_pinned_ads_status_active 
ON pinned_ads(status, expires_at DESC) 
WHERE status = 'active';

-- 2. 按城市和状态过滤的索引（支持按城市筛选）
CREATE INDEX IF NOT EXISTS idx_pinned_ads_city_status 
ON pinned_ads(city, status, expires_at DESC);

-- 3. 创建时间索引（支持时间范围过滤）
CREATE INDEX IF NOT EXISTS idx_pinned_ads_created_at 
ON pinned_ads(created_at DESC);

-- 4. 关联表索引（避免JOIN时的全表扫描）
CREATE INDEX IF NOT EXISTS idx_listings_id ON listings(id);
CREATE INDEX IF NOT EXISTS idx_coupons_id ON coupons(id);

-- 5. listings表常用查询字段索引（可选但推荐）
CREATE INDEX IF NOT EXISTS idx_listings_pinned_status 
ON listings(is_pinned, status) 
WHERE is_pinned = true AND status = 'active';

-- ============================================================================
-- 第二部分：RPC函数优化（替换现有函数，避免N+1查询）
-- ============================================================================

-- 首先删除现有函数（如果存在）
DROP FUNCTION IF EXISTS get_random_trending_ads(integer);

-- 创建优化后的函数
-- 核心改进：
-- 1. 一次性获取所有关联数据（避免前端N+1查询）
-- 2. 添加有效时间过滤（只返回未过期的置顶广告）
-- 3. 包含所有必要字段，前端无需额外查询
CREATE OR REPLACE FUNCTION get_random_trending_ads(limit_count integer)
RETURNS TABLE(
  -- pinned_ads表基础字段
  id uuid,
  listing_id uuid,
  user_id uuid,
  category text,
  city text,
  pinned_at timestamptz,
  pinned_until timestamptz,
  coupon_id uuid,
  status text,
  created_at timestamptz,
  updated_at timestamptz,
  expires_at timestamptz,
  type text,
  pinning_type text,
  metadata jsonb,
  note text,
  source text,
  -- listings表关联字段（避免前端额外查询）
  listing_title text,
  listing_price numeric,
  listing_images text[],
  listing_description text,
  listing_phone text,
  listing_name text,
  -- coupons表关联字段（避免前端额外查询）
  coupon_code text,
  coupon_type text,
  coupon_title text
) 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH random_active_ads AS (
    -- 步骤1：获取随机有效的置顶广告
    SELECT pa.*,
           l.title as listing_title,
           l.price as listing_price,
           -- 合并images和image_urls字段（兼容历史数据）
           CASE 
             WHEN l.images IS NOT NULL AND array_length(l.images, 1) > 0 THEN l.images
             WHEN l.image_urls IS NOT NULL AND array_length(l.image_urls, 1) > 0 THEN l.image_urls
             ELSE ARRAY[]::text[]
           END as listing_images,
           l.description as listing_description,
           l.phone as listing_phone,
           l.name as listing_name,
           c.code as coupon_code,
           c.type as coupon_type,
           c.title as coupon_title
    FROM pinned_ads pa
    -- LEFT JOIN确保即使关联数据不存在也返回pinned_ad记录
    LEFT JOIN listings l ON pa.listing_id = l.id
    LEFT JOIN coupons c ON pa.coupon_id = c.id
    WHERE pa.status = 'active'           -- 只返回活跃状态
      AND pa.expires_at > NOW()          -- 未过期的置顶
      -- 可选：限制时间范围，提高性能
      -- AND pa.created_at > NOW() - INTERVAL '30 days'
    ORDER BY RANDOM()                    -- 随机排序
    LIMIT limit_count                    -- 限制返回数量
  )
  SELECT * FROM random_active_ads;
END;
$$;

-- ============================================================================
-- 第三部分：性能验证查询（执行后验证优化效果）
-- ============================================================================

-- 1. 验证索引创建成功
SELECT 
  schemaname,
  tablename,
  indexname,
  indexdef
FROM pg_indexes 
WHERE tablename IN ('pinned_ads', 'listings', 'coupons')
  AND schemaname = 'public'
ORDER BY tablename, indexname;

-- 2. 验证函数创建成功
SELECT 
  proname as function_name,
  prosrc as function_source
FROM pg_proc 
WHERE proname = 'get_random_trending_ads';

-- 3. 性能测试：执行优化后的RPC函数（目标：<500ms）
-- 注意：首次执行可能较慢，后续执行会使用缓存
-- EXPLAIN ANALYZE 
-- SELECT * FROM get_random_trending_ads(20);

-- ============================================================================
-- 第四部分：可选性能增强方案（如果仍需优化）
-- ============================================================================

-- 方案A：添加复合索引（进一步优化特定查询）
/*
CREATE INDEX IF NOT EXISTS idx_pinned_ads_full_optimization 
ON pinned_ads(status, expires_at, created_at DESC, city)
WHERE status = 'active' AND expires_at > NOW();
*/

-- 方案B：添加统计信息更新（优化查询计划器）
/*
ANALYZE pinned_ads;
ANALYZE listings;
ANALYZE coupons;
*/

-- 方案C：创建物化视图（用于极高并发场景）
/*
CREATE MATERIALIZED VIEW mv_active_pinned_ads AS
SELECT pa.*,
       l.title as listing_title,
       l.price as listing_price,
       COALESCE(l.images, l.image_urls) as listing_images,
       c.code as coupon_code
FROM pinned_ads pa
LEFT JOIN listings l ON pa.listing_id = l.id
LEFT JOIN coupons c ON pa.coupon_id = c.id
WHERE pa.status = 'active'
  AND pa.expires_at > NOW()
WITH DATA;

CREATE UNIQUE INDEX idx_mv_active_pinned_ads_id ON mv_active_pinned_ads(id);
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_active_pinned_ads;
*/

-- ============================================================================
-- 第五部分：前端代码优化建议（配合后端优化）
-- ============================================================================

/*
前端代码优化建议（lib/services/coupon_service.dart）：

1. 移除N+1查询逻辑：
   - 删除getTrendingPinnedAds方法中的额外listing和coupon查询
   - 直接使用RPC返回的完整数据

2. 简化数据处理：
   // 优化后的前端代码示例
   final ads = await _client.rpc('get_random_trending_ads', params: {
     'limit_count': effectiveLimit,
   }) as List<dynamic>;
   
   // 直接使用返回的数据，无需额外查询
   final enrichedAds = ads.map((ad) {
     final adMap = Map<String, dynamic>.from(ad);
     // RPC已返回完整数据，直接使用
     return adMap;
   }).toList();

3. 添加查询缓存：
   - 保持现有的30秒TTL缓存
   - 添加响应时间监控日志
*/

-- ============================================================================
-- 执行说明：
-- 1. 复制整个脚本到Supabase控制台SQL编辑器
-- 2. 一次性执行或分部分执行
-- 3. 执行后验证索引和函数创建成功
-- 4. 测试RPC响应时间（目标：<500ms）
-- ============================================================================