// lib/auth/google_signin.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/services/oauth_entry.dart';

class GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onBefore;
  final VoidCallback? onAfter;

  const GoogleSignInButton({super.key, this.onBefore, this.onAfter});

  Future<void> _startGoogleOAuth(BuildContext context) async {
    onBefore?.call();
    try {
      await OAuthEntry.signIn(OAuthProvider.google);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google 登录失败：$e')),
      );
    } finally {
      onAfter?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: OAuthEntry.inFlightNotifier,
      builder: (context, inFlight, _) {
        return ElevatedButton(
          onPressed: inFlight ? null : () => _startGoogleOAuth(context),
          child: inFlight
              ? const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Text('Continue with Google'),
        );
      },
    );
  }
}
