-- Create or replace the airtime_redeem_request function
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
  v_current_points integer;
  v_request_id uuid;
BEGIN
  -- Get current user ID from JWT
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Not authenticated');
  END IF;

  -- Check points balance
  SELECT airtime_points INTO v_current_points
  FROM public.user_reward_state
  WHERE user_id = v_user_id AND campaign_code = p_campaign;

  IF v_current_points IS NULL OR v_current_points < p_points THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Insufficient points');
  END IF;

  -- Deduct points
  UPDATE public.user_reward_state
  SET airtime_points = airtime_points - p_points,
      updated_at = now()
  WHERE user_id = v_user_id AND campaign_code = p_campaign;

  -- Insert redemption record
  v_request_id := gen_random_uuid();
  INSERT INTO public.airtime_redemptions (
    id, user_id, phone, points_spent, status,
    provider_reference, amount_usd
  ) VALUES (
    v_request_id, v_user_id, p_phone, p_points, 'pending',
    'redeem_' || v_request_id, p_points / 100.0
  );

  -- Log event
  INSERT INTO public.reward_events (
    user_id, campaign_code, event_type,
    points_delta, request_id, ref_table, ref_id
  ) VALUES (
    v_user_id, p_campaign, 'airtime_redeem',
    -p_points, v_request_id, 'airtime_redemptions', v_request_id
  );

  RETURN jsonb_build_object('ok', true, 'request_id', v_request_id);
END;
$$;

-- Set permissions (revoke from anon/auth/public, grant to service_role)
REVOKE EXECUTE ON FUNCTION public.airtime_redeem_request FROM anon, authenticated, public;
GRANT EXECUTE ON FUNCTION public.airtime_redeem_request TO service_role;