import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

class FacebookAuthService {
  // Singleton pattern
  static final FacebookAuthService instance = FacebookAuthService._internal();

  factory FacebookAuthService() {
    return instance;
  }

  FacebookAuthService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  // Your Edge Function URL
  static const String _edgeFunctionUrl =
      'https://rhckybselarzglkmlyqs.supabase.co/functions/v1/facebook-auth';

  // Your Supabase anon key (safe to expose in client code)
  static const String _anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJoY2t5YnNlbGFyemdsa21seXFzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTUwMTM0NTgsImV4cCI6MjA3MDU4OTQ1OH0.3I0T2DnNwqtzjBjEl1OqoSA2SGhv_f_2XqH2RrOCjxo';

  Future<bool> signIn() async {
    debugPrint('[FacebookAuth] 🔵 Starting Facebook native login...');

    try {
      // Step 1: Login with Facebook SDK
      final LoginResult result = await FacebookAuth.instance.login(
        permissions: ['email', 'public_profile'],
      );

      // Check if login was successful
      if (result.status != LoginStatus.success) {
        debugPrint('[FacebookAuth] ❌ Facebook login failed: ${result.status}');
        return false;
      }

      final AccessToken? accessToken = result.accessToken;
      if (accessToken == null || accessToken.token.isEmpty) {
        debugPrint('[FacebookAuth] ❌ No access token received');
        return false;
      }

      debugPrint('[FacebookAuth] ✅ Got Facebook access token');
      // Token type no longer available in this version

      // Step 2: Call Edge Function to get temporary password
      debugPrint('[FacebookAuth] 🔄 Calling Edge Function...');

      final response = await http.post(
        Uri.parse(_edgeFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_anonKey',
          'apikey': _anonKey,
        },
        body: json.encode({
          'accessToken': accessToken.token,
        }),
      );

      debugPrint('[FacebookAuth] Edge Function response: ${response.statusCode}');

      if (response.statusCode != 200) {
        final error = json.decode(response.body);
        debugPrint('[FacebookAuth] ❌ Edge Function error (${response.statusCode}): $error');
        return false;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      debugPrint('[FacebookAuth] ✅ Edge Function returned success');

      // Step 3: Extract email and password from response
      final email = data['email'] as String;
      final password = data['password'] as String;

      debugPrint('[FacebookAuth] 🔑 Got credentials for: $email');

      // Step 4: Sign in with Supabase using the email and password
      // This creates a session that is guaranteed to be compatible with the client
      debugPrint('[FacebookAuth] 🔐 Signing in with Supabase...');

      final authResponse = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (authResponse.session == null) {
        debugPrint('[FacebookAuth] ❌ Failed to create session');
        return false;
      }

      debugPrint('[FacebookAuth] ✅ Supabase session created successfully');
      debugPrint('[FacebookAuth] User: ${authResponse.user?.id}');

      return true;

    } catch (e, stackTrace) {
      debugPrint('[FacebookAuth] ❌ Error: $e');
      debugPrint('[FacebookAuth] Stack trace: $stackTrace');
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await FacebookAuth.instance.logOut();
      await _supabase.auth.signOut();
      debugPrint('[FacebookAuth] ✅ Signed out successfully');
    } catch (e) {
      debugPrint('[FacebookAuth] ❌ Sign out error: $e');
      rethrow;
    }
  }
}