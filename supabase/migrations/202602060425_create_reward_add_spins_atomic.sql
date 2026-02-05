-- =========================================
-- P0: 原子加/减 spins（并发安全）
-- =========================================
create or replace function public.reward_add_spins_atomic(
  p_user uuid,
  p_campaign text,
  p_delta integer,
  p_reason text default null,
  p_request_id text default null
)
returns table(spins_balance bigint)
language plpgsql
security definer
as $$
declare
  v_spins bigint;
begin
  -- 确保有 state 行
  insert into public.user_reward_state (
    user_id,
    campaign_code,
    spins_balance,
    qualified_listings_count,
    airtime_points,
    created_at,
    updated_at
  )
  values (
    p_user,
    p_campaign,
    0,
    0,
    0,
    now(),
    now()
  )
  on conflict (user_id, campaign_code) do nothing;

  -- DB 内原子更新：spins_balance = spins_balance + delta
  update public.user_reward_state
  set
    spins_balance = greatest(0, coalesce(spins_balance,0) + p_delta),
    updated_at = now()
  where
    user_id = p_user
    and campaign_code = p_campaign
  returning public.user_reward_state.spins_balance into v_spins;

  if v_spins is null then
    raise exception 'reward_add_spins_atomic failed user=% campaign=%', p_user, p_campaign;
  end if;

  spins_balance := v_spins;
  return next;
end;
$$;

-- 权限（edge function 用 service_role 不受限；给 authenticated 只是方便测试）
grant execute on function public.reward_add_spins_atomic(uuid, text, integer, text, text) to authenticated;
grant execute on function public.reward_add_spins_atomic(uuid, text, integer, text, text) to service_role;