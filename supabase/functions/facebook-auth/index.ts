// Facebook Authentication Edge Function - Returns Temporary Password
// This function creates/updates user and returns a temporary password for client to sign in

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface FacebookUserData {
  id: string
  email?: string
  name?: string
  picture?: {
    data?: {
      url?: string
    }
  }
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  try {
    console.log('🔵 [STEP 1] Facebook auth request received')

    // Get Facebook access token from request body
    const { accessToken } = await req.json()
    console.log('🔑 [STEP 1] Access token received, length:', accessToken?.length || 0)

    if (!accessToken) {
      console.error('❌ [STEP 1] No access token provided')
      return new Response(
        JSON.stringify({ error: 'Access token required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Step 1: Verify Facebook access token
    console.log('🔄 [STEP 2] Verifying with Facebook Graph API...')
    const fbUrl = `https://graph.facebook.com/me?fields=id,name,email,picture&access_token=${accessToken}`

    const fbResponse = await fetch(fbUrl)
    console.log('📊 [STEP 2] Facebook API status:', fbResponse.status)

    if (!fbResponse.ok) {
      const fbError = await fbResponse.json()
      console.error('❌ [STEP 2] Facebook API error:', JSON.stringify(fbError))
      return new Response(
        JSON.stringify({ error: 'Invalid Facebook token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const userData: FacebookUserData = await fbResponse.json()
    console.log('✅ [STEP 2] Facebook user verified')
    console.log('📧 [STEP 2] User email:', userData.email || 'NO EMAIL')

    if (!userData.email) {
      console.error('❌ [STEP 2] Email not available from Facebook')
      return new Response(
        JSON.stringify({ error: 'Email not available from Facebook' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Step 2: Initialize Supabase admin client
    console.log('🔧 [STEP 3] Initializing Supabase admin client...')
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    if (!supabaseUrl || !supabaseServiceKey) {
      console.error('❌ [STEP 3] Missing Supabase credentials')
      return new Response(
        JSON.stringify({ error: 'Server configuration error' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const adminClient = createClient(supabaseUrl, supabaseServiceKey, {
      auth: { autoRefreshToken: false, persistSession: false }
    })
    console.log('✅ [STEP 3] Admin client created')

    // Step 3: Generate temporary password (64 chars, very secure)
    const tempPassword = crypto.randomUUID() + crypto.randomUUID()
    console.log('🔑 [STEP 4] Temporary password generated, length:', tempPassword.length)

    // Step 4: Create or update user
    console.log('📝 [STEP 5] Managing user...')

    try {
      // Try to create new user
      const { data: newUser, error: createError } = await adminClient.auth.admin.createUser({
        email: userData.email,
        password: tempPassword,
        email_confirm: true,
        user_metadata: {
          full_name: userData.name || '',
          avatar_url: userData.picture?.data?.url || '',
          provider: 'facebook',
          facebook_id: userData.id
        }
      })

      if (createError) {
        console.log('⚠️ [STEP 5] User exists, updating password...')

        // Find existing user
        let userId: string | null = null
        let page = 1

        while (page <= 10) {
          const { data: usersData } = await adminClient.auth.admin.listUsers({
            page: page,
            perPage: 100
          })

          const existingUser = usersData?.users.find(u => u.email === userData.email)

          if (existingUser) {
            userId = existingUser.id
            console.log('✅ [STEP 5] Found user, ID:', userId)
            break
          }

          if (!usersData?.users || usersData.users.length < 100) break
          page++
        }

        if (!userId) {
          console.error('❌ [STEP 5] Cannot find user')
          return new Response(
            JSON.stringify({ error: 'User lookup failed' }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }

        // Update password and metadata
        await adminClient.auth.admin.updateUserById(userId, {
          password: tempPassword,
          user_metadata: {
            full_name: userData.name || '',
            avatar_url: userData.picture?.data?.url || '',
            provider: 'facebook',
            facebook_id: userData.id
          }
        })
        console.log('✅ [STEP 5] Password updated')

      } else {
        console.log('✅ [STEP 5] New user created, ID:', newUser.user!.id)
      }
    } catch (error) {
      console.error('❌ [STEP 5] User management failed:', error)
      return new Response(
        JSON.stringify({ error: 'User management failed' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log('🎉 [FINAL] Success! Returning credentials for client sign-in')

    // Return email and temporary password for client to sign in
    return new Response(
      JSON.stringify({
        email: userData.email,
        password: tempPassword,
        user: {
          name: userData.name,
          avatar_url: userData.picture?.data?.url
        }
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('💥 [ERROR] Unexpected error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})