import 'dart:io' show Platform;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Failure-only log. Records ONLY that something failed (area + short error
/// text, capped at 300 chars) so we can see connection drops and push-token
/// problems on real devices. Never records message text, names, or media.
/// Never throws and never blocks the screen that calls it.
class ClientLog {
  static final Map<String, DateTime> _last = {};

  static void failure(String area, Object? detail) {
    // Fire and forget; at most one identical entry per 60 seconds so a
    // flapping connection can't flood the table.
    try {
      final now = DateTime.now();
      final prev = _last[area];
      if (prev != null && now.difference(prev).inSeconds < 60) return;
      _last[area] = now;

      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return;
      final text = (detail ?? '').toString();
      client.from('client_error_log').insert({
        'user_id': uid,
        'platform': Platform.isAndroid
            ? 'android'
            : (Platform.isIOS ? 'ios' : 'other'),
        'area': area,
        'detail': text.length > 300 ? text.substring(0, 300) : text,
      }).then((_) {}, onError: (_) {});
    } catch (_) {}
  }
}
