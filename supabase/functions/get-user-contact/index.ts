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
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);
    
    // Authentication
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      throw new Error("Authorization header required");
    }
    
    const token = authHeader.replace("Bearer ", "");
    const { data: userRes, error: authErr } = await supabaseAdmin.auth.getUser(token);
    if (authErr || !userRes?.user) {
      throw new Error("Authentication failed");
    }
    const currentUser = userRes.user;
    
    const body = await req.json().catch(() => ({}));
    const targetUserId: string = body?.user_id;
    
    if (!targetUserId) {
      throw new Error("Missing user_id parameter");
    }
    
    console.log(`[get-user-contact] User ${currentUser.id} requesting contact info for ${targetUserId}`);
    
    // Query profiles table (service_role has full access)
    const { data: profile, error: queryError } = await supabaseAdmin
      .from("profiles")
      .select("id, full_name, avatar_url, phone, whatsapp")
      .eq("id", targetUserId)
      .maybeSingle();
      
    if (queryError) {
      console.error(`[get-user-contact] Query error:`, queryError);
      throw new Error(`Database error: ${queryError.message}`);
    }
    
    if (!profile) {
      throw new Error("User not found");
    }
    
    // Return contact info (phone is sensitive, but allowed for authenticated users in offer context)
    return new Response(
      JSON.stringify({
        ok: true,
        data: {
          id: profile.id,
          full_name: profile.full_name,
          avatar_url: profile.avatar_url,
          phone: profile.phone,
          whatsapp: profile.whatsapp,
        }
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
    
  } catch (err) {
    console.error("[get-user-contact] Error:", err);
    return new Response(
      JSON.stringify({ 
        ok: false, 
        error: {
          message: String((err as any)?.message ?? err),
          code: "CONTACT_ERROR"
        }
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      }
    );
  }
});