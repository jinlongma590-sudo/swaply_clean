-- Add two-parameter compatibility wrapper for airtime_redeem_request
-- This ensures both old (p_campaign, p_points) and new (p_campaign, p_phone, p_points) calls work

CREATE OR REPLACE FUNCTION public.airtime_redeem_request(
  p_campaign text,
  p_points integer
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Two-parameter fallback: phone defaults to null
  -- Could be modified to fetch default phone from user profile if needed
  RETURN public.airtime_redeem_request(p_campaign, null::text, p_points);
END;
$$;

-- Set permissions (revoke from anon/auth/public, grant to service_role)
REVOKE EXECUTE ON FUNCTION public.airtime_redeem_request(text, integer) FROM anon, authenticated, public;
GRANT EXECUTE ON FUNCTION public.airtime_redeem_request(text, integer) TO service_role;

-- Refresh PostgREST schema cache
NOTIFY pgrst, 'reload schema';