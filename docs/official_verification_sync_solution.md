# Swaply 官方认证同步解决方案

## 问题背景

在升级用户为官方认证时，存在两个认证表数据不一致的问题：
1. **profiles表** - 用户主资料表
2. **user_verifications表** - 验证记录表

当管理员将用户升级为官方认证时，只更新了`profiles`表，导致`user_verifications`表仍保留旧的认证类型（如`"email"`），前端优先使用`user_verifications`表的数据，导致徽章显示错误。

## 已确认的问题案例

### mjl123@qq.com 用户
- **profiles表**: `verification_type="official"`, `is_official=true` ✅
- **user_verifications表**: `verification_type="email"` ❌
- **前端显示**: 绿色普通认证徽章（错误）

### Swaply James 用户
- **profiles表**: `verification_type="official"`, `is_official=true` ✅
- **user_verifications表**: `verification_type="official"` ✅
- **前端显示**: 蓝色官方认证徽章（正确）

## 解决方案A：同步更新两个表

### 1. SQL函数：单用户官方认证升级

```sql
-- 创建或替换同步更新函数
CREATE OR REPLACE FUNCTION upgrade_to_official(user_id UUID)
RETURNS VOID AS $$
BEGIN
  -- 1. 更新profiles表
  UPDATE profiles 
  SET 
    verification_type = 'official',
    is_official = true,
    is_verified = true,
    updated_at = NOW()
  WHERE id = user_id;

  -- 2. 更新user_verifications表（如果存在记录）
  UPDATE user_verifications 
  SET 
    verification_type = 'official',
    updated_at = NOW()
  WHERE user_id = user_id;

  -- 3. 如果user_verifications不存在记录，创建一条
  INSERT INTO user_verifications (user_id, verification_type, created_at, updated_at)
  SELECT 
    user_id, 
    'official', 
    NOW(), 
    NOW()
  WHERE NOT EXISTS (
    SELECT 1 FROM user_verifications WHERE user_id = user_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 2. SQL脚本：批量升级代理用户

```sql
-- 批量将所有agent.*@swaply.com用户升级为官方认证
DO $$
DECLARE
  agent_user RECORD;
BEGIN
  FOR agent_user IN 
    SELECT id, email 
    FROM profiles 
    WHERE email LIKE 'agent.%@swaply.com'
  LOOP
    -- 使用函数升级
    PERFORM upgrade_to_official(agent_user.id);
    RAISE NOTICE '升级用户: % (%)', agent_user.email, agent_user.id;
  END LOOP;
END;
$$;
```

### 3. Edge Function：通过API调用升级

创建Edge Function `upgrade-official-verification`:

```typescript
// supabase/functions/upgrade-official-verification/index.ts
import { createClient } from 'npm:@supabase/supabase-js@2.39.7'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { user_id } = await req.json()
    
    if (!user_id) {
      return new Response(
        JSON.stringify({ error: 'user_id is required' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // 1. 更新profiles表
    const { error: profileError } = await supabaseAdmin
      .from('profiles')
      .update({
        verification_type: 'official',
        is_official: true,
        is_verified: true,
        updated_at: new Date().toISOString(),
      })
      .eq('id', user_id)

    if (profileError) throw profileError

    // 2. 更新或创建user_verifications记录
    const { data: existingVerification } = await supabaseAdmin
      .from('user_verifications')
      .select('id')
      .eq('user_id', user_id)
      .maybeSingle()

    if (existingVerification) {
      // 更新现有记录
      const { error: uvError } = await supabaseAdmin
        .from('user_verifications')
        .update({
          verification_type: 'official',
          updated_at: new Date().toISOString(),
        })
        .eq('user_id', user_id)

      if (uvError) throw uvError
    } else {
      // 创建新记录
      const { error: uvError } = await supabaseAdmin
        .from('user_verifications')
        .insert({
          user_id,
          verification_type: 'official',
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })

      if (uvError) throw uvError
    }

    return new Response(
      JSON.stringify({ success: true, message: '用户已成功升级为官方认证' }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )

  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})
```

### 4. 前端调用示例

```dart
// lib/services/admin_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminService {
  final SupabaseClient _sb = Supabase.instance.client;

  /// 升级用户为官方认证
  Future<bool> upgradeToOfficial(String userId) async {
    try {
      final response = await _sb.functions.invoke(
        'upgrade-official-verification',
        body: {'user_id': userId},
      );

      return response.status == 200;
    } catch (e) {
      print('[AdminService] 升级官方认证失败: $e');
      return false;
    }
  }

  /// 批量升级代理用户
  Future<bool> batchUpgradeAgents() async {
    try {
      // 获取所有agent用户
      final { data: agents, error } = await _sb
        .from('profiles')
        .select('id, email')
        .like('email', 'agent.%@swaply.com');

      if (error != null) throw error;

      bool allSuccess = true;
      for (final agent in agents ?? []) {
        final success = await upgradeToOfficial(agent['id'] as String);
        if (!success) {
          print('[AdminService] 升级用户失败: ${agent['email']}');
          allSuccess = false;
        }
      }

      return allSuccess;
    } catch (e) {
      print('[AdminService] 批量升级失败: $e');
      return false;
    }
  }
}
```

## 操作指南

### 立即执行：修复现有不一致数据

```sql
-- 1. 查找profiles表为official但user_verifications表不是official的用户
SELECT 
  p.id,
  p.email,
  p.verification_type as profile_type,
  uv.verification_type as uv_type
FROM profiles p
LEFT JOIN user_verifications uv ON uv.user_id = p.id
WHERE p.verification_type = 'official'
  AND (uv.verification_type IS NULL OR uv.verification_type != 'official');

-- 2. 修复这些用户
DO $$
DECLARE
  user_record RECORD;
BEGIN
  FOR user_record IN 
    SELECT p.id, p.email
    FROM profiles p
    LEFT JOIN user_verifications uv ON uv.user_id = p.id
    WHERE p.verification_type = 'official'
      AND (uv.verification_type IS NULL OR uv.verification_type != 'official')
  LOOP
    -- 更新user_verifications表
    UPDATE user_verifications 
    SET verification_type = 'official', updated_at = NOW()
    WHERE user_id = user_record.id;
    
    -- 如果不存在记录，创建一条
    INSERT INTO user_verifications (user_id, verification_type, created_at, updated_at)
    SELECT user_record.id, 'official', NOW(), NOW()
    WHERE NOT EXISTS (
      SELECT 1 FROM user_verifications WHERE user_id = user_record.id
    );
    
    RAISE NOTICE '修复用户: % (%)', user_record.email, user_record.id;
  END LOOP;
END;
$$;
```

### 长期维护：添加数据库触发器

```sql
-- 创建触发器，在profiles表更新时自动同步user_verifications表
CREATE OR REPLACE FUNCTION sync_verification_to_user_verifications()
RETURNS TRIGGER AS $$
BEGIN
  -- 只有当verification_type变化时才同步
  IF (TG_OP = 'UPDATE' AND OLD.verification_type IS DISTINCT FROM NEW.verification_type) 
     OR TG_OP = 'INSERT' THEN
    
    -- 更新或插入user_verifications表
    INSERT INTO user_verifications (user_id, verification_type, created_at, updated_at)
    VALUES (NEW.id, NEW.verification_type, NOW(), NOW())
    ON CONFLICT (user_id) 
    DO UPDATE SET 
      verification_type = EXCLUDED.verification_type,
      updated_at = NOW();
      
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 为profiles表添加触发器
DROP TRIGGER IF EXISTS sync_verification_trigger ON profiles;
CREATE TRIGGER sync_verification_trigger
  AFTER INSERT OR UPDATE OF verification_type ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION sync_verification_to_user_verifications();
```

## 前端优化建议

### 1. 修改认证查询优先级

```dart
// lib/services/email_verification_service.dart
// 修改 fetchVerificationRow() 方法：

Future<Map<String, dynamic>?> fetchVerificationRow() async {
  final uid = _sb.auth.currentUser?.id;
  if (uid == null) return null;

  try {
    // 同时查询两个表，优先使用profiles表的数据
    final [profileRow, uvRow] = await Future.wait([
      _sb.from('profiles')
          .select('email, verification_type, is_verified, is_official, updated_at')
          .eq('id', uid)
          .maybeSingle(),
      _sb.from('user_verifications')
          .select('email_verified_at, verification_type, updated_at')
          .eq('user_id', uid)
          .maybeSingle(),
    ]);

    // 优先使用profiles表的verification_type
    final verificationType = 
        profileRow?['verification_type'] ?? uvRow?['verification_type'];
    
    // 其他逻辑保持不变...
  } catch (e) {
    print('[EV] fetchVerificationRow error: $e');
    return null;
  }
}
```

### 2. 添加缓存清理机制

```dart
// lib/services/profile_service.dart
/// 清除用户认证缓存
Future<void> clearVerificationCache(String userId) async {
  // 清除内存缓存
  _cache.remove(userId);
  
  // 通知其他服务
  EmailVerificationService().invalidateCache();
  
  // 更新Stream
  _updateStream(null);
}
```

## 监控与验证

### 1. 定期检查数据一致性

```sql
-- 每周运行的监控脚本
SELECT 
  COUNT(*) as total_official_users,
  SUM(CASE WHEN uv.verification_type = 'official' THEN 1 ELSE 0 END) as synced_users,
  SUM(CASE WHEN uv.verification_type IS NULL OR uv.verification_type != 'official' THEN 1 ELSE 0 END) as unsynced_users
FROM profiles p
LEFT JOIN user_verifications uv ON uv.user_id = p.id
WHERE p.verification_type = 'official';
```

### 2. 仪表板监控面板

在Admin Dashboard中添加"认证同步状态"监控面板：

```typescript
// 显示同步状态统计
const syncStats = {
  totalOfficialUsers: 0,
  syncedUsers: 0,
  unsyncedUsers: 0,
  syncRate: '0%'
}
```

## 紧急恢复流程

### 情况1：前端显示错误徽章

1. **检查步骤**：
   - 确认用户已重新登录（清除缓存）
   - 检查两个表的verification_type是否一致
   - 验证`EmailVerificationService.fetchVerificationRow()`返回的数据

2. **修复步骤**：
   - 执行单用户修复SQL
   - 清除用户App缓存
   - 重新登录验证

### 情况2：批量升级失败

1. **检查步骤**：
   - 检查Edge Function日志
   - 验证单个用户是否可以成功升级
   - 检查数据库连接和权限

2. **修复步骤**：
   - 使用SQL脚本直接批量更新
   - 分批处理（每次10个用户）
   - 记录失败的用户ID后续处理

## 总结

通过实施**方案A（同步更新两个表）**，可以确保：

1. ✅ **数据一致性**：profiles表和user_verifications表始终保持同步
2. ✅ **前端显示正确**：徽章颜色与认证级别匹配
3. ✅ **维护性高**：提供自动化脚本和监控机制
4. ✅ **可扩展性**：支持单用户和批量操作

**立即行动项**：
1. [x] 修复现有不一致用户数据
2. [ ] 部署Edge Function `upgrade-official-verification`
3. [ ] 创建数据库触发器（可选）
4. [ ] 更新Admin Dashboard添加批量升级功能
5. [ ] 添加数据一致性监控