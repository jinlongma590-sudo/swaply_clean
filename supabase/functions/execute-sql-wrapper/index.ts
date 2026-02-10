import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import postgres from "https://deno.land/x/postgres@v0.17.0/mod.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Database connection string
const databaseUrl = "postgresql://postgres:65U31TzFZEQEKxhL@rhckybselarzglkmlyqs.supabase.co:5432/postgres?sslmode=require";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Simple authentication: require a secret token
  const authHeader = req.headers.get("authorization");
  const expectedToken = Deno.env.get("EXECUTE_TOKEN") || "temp-token";
  
  if (!authHeader || authHeader !== `Bearer ${expectedToken}`) {
    return new Response(JSON.stringify({ ok: false, error: "Unauthorized" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 401,
    });
  }

  try {
    // Connect to database
    const sql = postgres(databaseUrl);
    
    // Execute the wrapper SQL
    const sqlCommands = `
CREATE OR REPLACE FUNCTION public.airtime_redeem_request(
  p_campaign text,
  p_points integer
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN public.airtime_redeem_request(p_campaign, null::text, p_points);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.airtime_redeem_request(text, integer) FROM anon, authenticated, public;
GRANT EXECUTE ON FUNCTION public.airtime_redeem_request(text, integer) TO service_role;

NOTIFY pgrst, 'reload schema';
    `;
    
    console.log("Executing SQL...");
    const result = await sql.unsafe(sqlCommands);
    console.log("SQL executed successfully");
    
    await sql.end();
    
    return new Response(JSON.stringify({ ok: true, message: "Wrapper function created and schema cache refreshed" }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (err) {
    console.error("Error executing SQL:", err);
    return new Response(JSON.stringify({ ok: false, error: err.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});