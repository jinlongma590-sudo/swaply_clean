-- ======================================================================
-- 一次性修复 airtime_redeem 全链路 (2026-02-09)
-- 目标：用户点击 Redeem Airtime 能成功兑换
-- 方案：创建 v2 函数（接受 user_id），Edge Function 调用 v2，wrapper 保持兼容
-- ======================================================================

-- 1. 如果存在旧函数，先删除（避免冲突）
DROP FUNCTION IF EXISTS public.airtime_redeem_request(text, integer);
DROP FUNCTION IF EXISTS public.airtime_redeem_request(text, text, integer);

-- 2. 创建核心 v2 函数：接受显式 user_id，不依赖 auth.uid()
CREATE OR REPLACE FUNCTION public.airtime_redeem_request_v2(
  p_user_id uuid,
  p_campaign text,
  p_phone text,
  p_points integer
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_current_points integer;
  v_request_id uuid;
  v_new_points integer;
BEGIN
  -- 输入验证
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Missing user_id');
  END IF;
  
  IF p_phone IS NULL OR p_phone = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Missing phone number');
  END IF;
  
  IF p_points <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Points must be positive');
  END IF;

  -- 检查 points 余额
  SELECT airtime_points INTO v_current_points
  FROM public.user_reward_state
  WHERE user_id = p_user_id AND campaign_code = p_campaign;

  IF v_current_points IS NULL THEN
    -- 用户没有奖励记录，视为 0 points
    v_current_points := 0;
  END IF;

  IF v_current_points < p_points THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Insufficient points', 'current_points', v_current_points);
  END IF;

  -- 扣减 points（原子操作）
  UPDATE public.user_reward_state
  SET 
    airtime_points = airtime_points - p_points,
    updated_at = now()
  WHERE user_id = p_user_id AND campaign_code = p_campaign
  RETURNING airtime_points INTO v_new_points;

  -- 插入兑换记录
  v_request_id := gen_random_uuid();
  INSERT INTO public.airtime_redemptions (
    id, user_id, phone, points_spent, status,
    provider_reference, amount_usd
  ) VALUES (
    v_request_id, p_user_id, p_phone, p_points, 'pending',
    'redeem_' || v_request_id, p_points / 100.0
  );

  -- 记录事件
  INSERT INTO public.reward_events (
    user_id, campaign_code, event_type,
    points_delta, request_id, ref_table, ref_id
  ) VALUES (
    p_user_id, p_campaign, 'airtime_redeem',
    -p_points, v_request_id, 'airtime_redemptions', v_request_id
  );

  RETURN jsonb_build_object(
    'ok', true,
    'request_id', v_request_id,
    'new_points', v_new_points,
    'points_spent', p_points
  );
END;
$$;

-- 3. 创建 wrapper 函数（保持旧函数名兼容）
-- 这个函数可以从 JWT 提取 user_id，然后调用 v2
-- 如果前端需要直接 RPC，这个 wrapper 可用（权限给 authenticated）
CREATE OR REPLACE FUNCTION public.airtime_redeem_request(
  p_campaign text,
  p_phone text,
  p_points integer
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  -- 从 JWT 获取用户 ID（兼容前端直调）
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Not authenticated');
  END IF;
  
  -- 调用 v2 函数
  RETURN public.airtime_redeem_request_v2(v_user_id, p_campaign, p_phone, p_points);
END;
$$;

-- 4. 创建两参 wrapper（兼容旧调用链）
CREATE OR REPLACE FUNCTION public.airtime_redeem_request(
  p_campaign text,
  p_points integer
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
  v_phone text;
BEGIN
  -- 从 JWT 获取用户 ID
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Not authenticated');
  END IF;
  
  -- 尝试从用户 profile 获取默认手机号
  -- 如果 profile 没有 phone，则返回错误
  SELECT phone INTO v_phone
  FROM public.profiles
  WHERE id = v_user_id;
  
  IF v_phone IS NULL OR v_phone = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Phone number required. Please update your profile.');
  END IF;
  
  -- 调用三参 wrapper
  RETURN public.airtime_redeem_request(p_campaign, v_phone, p_points);
END;
$$;

-- 5. 权限配置
-- v2 函数：仅允许 service_role 调用（Edge Function 专用）
REVOKE EXECUTE ON FUNCTION public.airtime_redeem_request_v2(uuid, text, text, integer) 
  FROM anon, authenticated, public;
GRANT EXECUTE ON FUNCTION public.airtime_redeem_request_v2(uuid, text, text, integer) 
  TO service_role;

-- wrapper 函数（三参）：允许 authenticated 调用（如果前端需要直调）
REVOKE EXECUTE ON FUNCTION public.airtime_redeem_request(text, text, integer) 
  FROM anon, public;
GRANT EXECUTE ON FUNCTION public.airtime_redeem_request(text, text, integer) 
  TO authenticated, service_role;

-- wrapper 函数（两参）：允许 authenticated 调用
REVOKE EXECUTE ON FUNCTION public.airtime_redeem_request(text, integer) 
  FROM anon, public;
GRANT EXECUTE ON FUNCTION public.airtime_redeem_request(text, integer) 
  TO authenticated, service_role;

-- 6. 刷新 PostgREST schema cache
NOTIFY pgrst, 'reload schema';

-- 7. 验证函数已创建
COMMENT ON FUNCTION public.airtime_redeem_request_v2(uuid, text, text, integer) IS 
  '核心兑换函数（Edge Function 专用），接受显式 user_id，不依赖 auth.uid()';
COMMENT ON FUNCTION public.airtime_redeem_request(text, text, integer) IS 
  '三参 wrapper，从 JWT 获取 user_id，供前端直调用';
COMMENT ON FUNCTION public.airtime_redeem_request(text, integer) IS 
  '两参 wrapper，从 profile 获取手机号，兼容旧调用链';