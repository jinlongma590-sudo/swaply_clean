import 'package:swaply/services/oauth_entry.dart';
// lib/auth/google_signin.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// for LaunchMode

const String _kIOSRedirect = 'cc.swaply.app://login-callback';

class GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onBefore;
  final VoidCallback? onAfter;

  const GoogleSignInButton({super.key, this.onBefore, this.onAfter});

  Future<void> _startGoogleOAuth(BuildContext context) async {
    onBefore?.call();
    try {
      await OAuthEntry.signIn(
        OAuthProvider.google);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google 閻ц缍嶆径杈Е閿?e')),
      );
    } finally {
      onAfter?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => _startGoogleOAuth(context),
      child: const Text('Continue with Google'),
    );
  }
}




