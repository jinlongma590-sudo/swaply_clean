// lib/pages/account_settings_page.dart
import 'package:flutter/foundation.dart';
import 'package:swaply/router/safe_navigator.dart'; // 閴?For platform check
import 'package:flutter/material.dart';
import 'package:swaply/router/safe_navigator.dart';
import 'package:flutter/services.dart';
import 'package:swaply/router/safe_navigator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/router/safe_navigator.dart';
import 'package:swaply/services/auth_service.dart';
import 'package:swaply/router/safe_navigator.dart'; // 鉁?鏂板锛氱粺涓€璧?AuthService 鐧诲嚭
import 'package:swaply/services/auth_flow_observer.dart';
import 'package:swaply/router/safe_navigator.dart'; // 鉁?鏂板 Observer
import 'package:swaply/router/root_nav.dart';
import 'package:swaply/router/safe_navigator.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  final _pwdCtrl = TextEditingController();
  bool _ack = false;
  bool _deleting = false;

  // 閴?闂冨弶濮堥敍姘灩闂勩倖鍨氶崝鐔锋倵閻?signOut 閸欘亜鍘戠拋姝屝曢崣鎴滅濞嗏槄绱濋梼鍙夘剾閻戭參鍣告潪?闁插秴缂撶€佃壈鍤ч柌宥咁槻閻ц鍤?
  bool _logoutAfterDeletionOnce = false;

  @override
  void dispose() {
    _pwdCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit => _ack && _pwdCtrl.text.trim().isNotEmpty && !_deleting;

  // 妞ゅ爼鍎撮弰鍓ф簜闁挎瑨顕ゅΟ顏勭畽
  void _showErrorBanner(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.hideCurrentMaterialBanner();

    HapticFeedback.heavyImpact(); // 闂囧洤濮╅幓鎰仛

    messenger.showMaterialBanner(
      MaterialBanner(
        backgroundColor: Colors.red.shade600,
        leading: const Icon(Icons.error_outline, color: Colors.white),
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: const Text('Dismiss', style: TextStyle(color: Colors.white)),
          ),
        ],
        forceActionsBelow: false,
      ),
    );

    // 4 缁夋帒鎮楅懛顏勫З闂呮劘妫?
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      messenger.hideCurrentMaterialBanner();
    });
  }

  // 閹存劕濮涢幓鎰仛閿涘牆绨抽柈?Snackbar閿?
  void _showSuccessSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentMaterialBanner();
    messenger.showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text('Account deleted.')),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // 閴?绾喛顓诲鍦崶閿涙俺绶崗?DELETE 閹靛秷鍏樼紒褏鐢?
  Future<bool> _finalConfirm() async {
    final ctrl = TextEditingController();
    bool canConfirm = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text(
              'Type DELETE to confirm',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'DELETE',
              ),
              onChanged: (v) {
                setState(() {
                  canConfirm = v.trim().toUpperCase() == 'DELETE';
                });
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(fontSize: 16)),
              ),
              ElevatedButton(
                onPressed: canConfirm ? () => Navigator.pop(ctx, true) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Confirm'),
              ),
            ],
          ),
        );
      },
    );

    // 娑撳秵澧滈崝?dispose閿涘矂浼╅崗宥堢箖濞撯剝婀￠弬顓♀枅瀹曗晜绨?
    return ok ?? false;
  }

  Future<void> _deleteAccount() async {
    if (!_canSubmit) return;
    if (!await _finalConfirm()) return;

    setState(() => _deleting = true);
    final client = Supabase.instance.client;

    try {
      final res = await client.functions.invoke(
        'delete_account',
        body: {
          'confirm': true,
          'password': _pwdCtrl.text.trim(),
          'reason': 'user_request',
        },
      );

      final data = (res.data is Map) ? (res.data as Map) : const {};
      final ok = data['ok'] == true;

      if (ok) {
        // 閴?閸忓牊褰佺粈鐚寸礉閸愬秮鈧粌褰х憴锕€褰傛稉鈧▎鈾€鈧繄娅ラ崙鐚寸礉闂呭繐鎮楅柅鈧崙鍝勫煂閺嶇櫢绱欓梼缁樻焽瑜版挸澧犳い鐢稿櫢瀵ゅ搫顕遍懛瀵告畱闁插秴顦查柅鏄忕帆閿?
        if (mounted) {
          _showSuccessSnack('Account deleted.');
        }

        if (!_logoutAfterDeletionOnce) {
          _logoutAfterDeletionOnce = true;
          try {
            // 缁熶竴浠?AuthService 鐧诲嚭锛屽苟鎵撳嵃璋冪敤鏍堬紝渚夸簬杩借釜鏉ユ簮
            debugPrint(
                '[[SIGNOUT-TRACE]] account_settings_page -> direct signOut');
            debugPrint(StackTrace.current.toString());

            // 鉁?1) 鏍囪蹇溅閬?
            AuthFlowObserver.I.markManualSignOut();
            // 鉁?2) 鎵ц鐧诲嚭
            await AuthService().signOut();
          } catch (_) {/* 闂堟瑩绮?*/}
        }

        if (!mounted) return;
        // 閸ョ偛鍩岄弽纭呯熅閻㈡唻绱欓幋鏍ㄥ瘻娴ｇ娀銆嶉惄顔芥暭娑?SafeNavigator.pushNamedAndRemoveUntil('/welcome', (_) => false)閿?
        navReplaceAll('/welcome');
        return;
      } else {
        final msg = (data['error'] ?? 'Delete failed').toString();
        throw Exception(msg);
      }
    } catch (e) {
      if (mounted) {
        final message = e.toString();
        final lower = message.toLowerCase();
        final wrongPwd = lower.contains('403') ||
            lower.contains('wrong password') ||
            lower.contains('password');
        final friendly = wrongPwd
            ? 'Password is incorrect.'
            : message.replaceFirst('Exception: ', '');
        _showErrorBanner(friendly);
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  // 閴?缂佺喍绔撮惃?AppBar 閺嬪嫬缂撻崳?(娑撳骸鍙炬禒鏍€夐棃銏ゎ棑閺嶉棿绔撮懛?
  PreferredSizeWidget _buildStandardAppBar(BuildContext context) {
    const String title = 'Account';
    final double statusBar = MediaQuery.of(context).padding.top;
    final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    const Color kBgColor = Color(0xFF2563EB);

    // Android & 閸忔湹绮獮鍐插酱閿涙碍鐖ｉ崙?AppBar
    if (!isIOS) {
      return AppBar(
        title: const Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: kBgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      );
    }

    // iOS閿?4pt 閼奉亜鐣炬稊澶婎嚤閼割亝鐖?
    const double kNavBarHeight = 44.0;
    const double kButtonSize = 32.0;
    const double kSidePadding = 16.0;
    const double kButtonSpacing = 12.0;

    final Widget iosBackButton = SizedBox(
      width: kButtonSize,
      height: kButtonSize,
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: Colors.white),
        ),
      ),
    );

    const Widget iosTitle = Expanded(
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
    );

    const Widget iosRightPlaceholder =
        SizedBox(width: kButtonSize, height: kButtonSize);

    return PreferredSize(
      preferredSize: Size.fromHeight(statusBar + kNavBarHeight),
      child: Container(
        color: kBgColor,
        padding: EdgeInsets.only(top: statusBar),
        child: SizedBox(
          height: kNavBarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kSidePadding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                iosBackButton,
                const SizedBox(width: kButtonSpacing),
                iosTitle,
                const SizedBox(width: kButtonSpacing),
                iosRightPlaceholder,
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final danger = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: _buildStandardAppBar(context),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text(
                'Security',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Password, devices (coming soon)',
                style: TextStyle(fontSize: 15, color: Colors.grey[600]),
              ),
              onTap: () {},
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: danger.withOpacity(.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: danger.withOpacity(.2)),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: danger, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Danger Zone',
                      style: TextStyle(
                        color: danger,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'This will permanently delete your profile, listings, messages, notifications, favorites, coupons and all media files. This action cannot be undone.',
                  style: TextStyle(fontSize: 15, height: 1.45),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pwdCtrl,
                  obscureText: true,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    labelText: 'Current password',
                    labelStyle: TextStyle(fontSize: 15),
                    hintText: 'Enter your password',
                    hintStyle: TextStyle(fontSize: 15),
                    border: OutlineInputBorder(),
                  ),
                ),
                CheckboxListTile(
                  value: _ack,
                  onChanged: (v) => setState(() => _ack = (v ?? false)),
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'I understand this will permanently delete my account and data.',
                    style: TextStyle(fontSize: 15, height: 1.4),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _canSubmit ? _deleteAccount : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _canSubmit ? danger : danger.withOpacity(.5),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _deleting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Delete My Account'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
