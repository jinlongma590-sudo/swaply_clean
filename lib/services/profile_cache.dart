import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileCache {
  ProfileCache._();
  static final ProfileCache instance = ProfileCache._();

  String? _uid;
  Map<String, dynamic>? _data;
  DateTime? _ts;

  Map<String, dynamic>? get current {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return null;
    if (_uid == uid) return _data;
    return null;
  }

  void setForCurrentUser(Map<String, dynamic> data) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    _uid = uid;
    _data = data;
    _ts = DateTime.now();
  }

  void clear() {
    _uid = null;
    _data = null;
    _ts = null;
  }
}
