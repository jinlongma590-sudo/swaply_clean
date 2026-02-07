-- 步骤1: 创建 Spin 账本表
create table if not exists public.reward_spin_ledger (
  id bigserial primary key,
  created_at timestamptz not null default now(),
  user_id uuid not null,
  campaign_code text not null,
  delta integer not null,
  balance_after integer not null,
  reason text not null,
  ref text null,
  meta jsonb not null default '{}'::jsonb
);

create index if not exists idx_spin_ledger_user_campaign_time
on public.reward_spin_ledger (user_id, campaign_code, created_at desc);

-- 步骤2: 确保 user_reward_state 唯一
-- 先清理重复（保留 updated_at 最新的一条）
with ranked as (
  select ctid, user_id, campaign_code,
         row_number() over (partition by user_id, campaign_code order by updated_at desc nulls last, created_at desc nulls last) as rn
  from public.user_reward_state
)
delete from public.user_reward_state s
using ranked r
where s.ctid = r.ctid and r.rn > 1;

-- 再加唯一约束（若已存在会报错，忽略即可）
do $$
begin
  if not exists (
    select 1 from pg_indexes
    where schemaname='public' and indexname='uniq_user_reward_state_user_campaign'
  ) then
    execute 'create unique index uniq_user_reward_state_user_campaign on public.user_reward_state(user_id, campaign_code)';
  end if;
end $$;

-- 步骤3: 创建“原子加/扣 spin + 写账本”的 RPC（闭环核心）
create or replace function public.reward_spin_apply(
  p_user uuid,
  p_campaign text,
  p_delta integer,
  p_reason text,
  p_ref text default null,
  p_meta jsonb default '{}'::jsonb
)
returns table (ok boolean, spins_balance integer, ledger_id bigint)
language plpgsql
security definer
as $$
declare
  v_new integer;
  v_ledger_id bigint;
begin
  if p_delta = 0 then
    raise exception 'delta cannot be 0';
  end if;

  -- ✅ upsert 确保 state 行存在（并发安全依赖唯一索引）
  insert into public.user_reward_state (user_id, campaign_code, spins_balance, updated_at)
  values (p_user, p_campaign, 0, now())
  on conflict (user_id, campaign_code) do nothing;

  -- ✅ 原子更新：扣的时候必须余额足够（防超扣）
  if p_delta < 0 then
    update public.user_reward_state
       set spins_balance = spins_balance + p_delta,
           updated_at = now()
     where user_id = p_user
       and campaign_code = p_campaign
       and spins_balance + p_delta >= 0
    returning spins_balance into v_new;

    if v_new is null then
      return query select false, (select spins_balance from public.user_reward_state where user_id=p_user and campaign_code=p_campaign), null::bigint;
      return;
    end if;
  else
    update public.user_reward_state
       set spins_balance = spins_balance + p_delta,
           updated_at = now()
     where user_id = p_user
       and campaign_code = p_campaign
    returning spins_balance into v_new;
  end if;

  -- ✅ 写账本：记录每次变动与变动后余额
  insert into public.reward_spin_ledger(user_id, campaign_code, delta, balance_after, reason, ref, meta)
  values (p_user, p_campaign, p_delta, v_new, p_reason, p_ref, coalesce(p_meta, '{}'::jsonb))
  returning id into v_ledger_id;

  return query select true, v_new, v_ledger_id;
end;
$$;

-- ✅ 限制普通用户直接调用（只给 service_role / postgres）
revoke all on function public.reward_spin_apply(uuid, text, integer, text, text, jsonb) from public;

-- 步骤4: 创建“消费 spin” RPC
create or replace function public.reward_consume_spin_v2(
  p_user uuid,
  p_campaign text,
  p_ref text default null
)
returns table (ok boolean, spins_left integer, ledger_id bigint)
language plpgsql
security definer
as $$
begin
  return query
  select a.ok, a.spins_balance as spins_left, a.ledger_id
  from public.reward_spin_apply(p_user, p_campaign, -1, 'consume', p_ref, '{}'::jsonb) a;
end;
$$;

revoke all on function public.reward_consume_spin_v2(uuid, text, text) from public;

-- 步骤5: 创建“发放 spin” RPC
create or replace function public.reward_grant_spins_v2(
  p_user uuid,
  p_campaign text,
  p_add integer,
  p_reason text default 'grant',
  p_ref text default null
)
returns table (ok boolean, spins_balance integer, ledger_id bigint)
language plpgsql
security definer
as $$
begin
  if p_add <= 0 then
    raise exception 'p_add must be > 0';
  end if;

  return query
  select a.ok, a.spins_balance, a.ledger_id
  from public.reward_spin_apply(p_user, p_campaign, p_add, p_reason, p_ref, '{}'::jsonb) a;
end;
$$;

revoke all on function public.reward_grant_spins_v2(uuid, text, integer, text, text) from public;