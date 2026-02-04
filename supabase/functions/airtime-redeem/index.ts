import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) throw new Error("No authorization header");

    const token = authHeader.replace("Bearer ", "");
    const { data: userRes, error: authErr } = await supabase.auth.getUser(token);
    if (authErr || !userRes?.user) throw new Error("Authentication failed");
    const user = userRes.user;

    const body = await req.json().catch(() => ({}));
    const phone: string = body?.phone;
    const points: number = Number(body?.points || 0);

    console.log(`[Airtime] User ${user.id} redeeming ${points} points for ${phone}`);

    const { data: result, error: rpcError } = await supabase.rpc("airtime_redeem_request", {
      p_phone: phone,
      p_points: points,
      p_campaign: "launch_v1",
    });

    if (rpcError) throw new Error(`RPC error: ${rpcError.message}`);

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: result?.ok ? 200 : 400,
    });
  } catch (err) {
    console.error("[Airtime] Error:", err);
    return new Response(JSON.stringify({ ok: false, error: String((err as any)?.message ?? err) }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    });
  }
});
