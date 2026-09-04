import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

/// Sep 3 2026: push notifications, first real infrastructure build.
/// Handles the DEVICE side only -- asking permission, getting this
/// device's FCM token, and keeping it saved against whichever account is
/// currently signed in. Actually SENDING a push (new message, SOS, check-in
/// reminder) happens server-side, in a Supabase Edge Function triggered by
/// those events -- this file has nothing to do with that half.
class PushService {
  /// Call this once a real signed-in session exists -- either at cold
  /// start (main.dart's _resolveInitialRoute, for an already-signed-in
  /// return visit) or right after onboarding completes
  /// (save_messages_prompt_screen.dart's _navigateToHome, for a brand
  /// new sign-in). Deliberately fire-and-forget at both call sites --
  /// this should never add latency to navigation or block anything the
  /// person is waiting on. Safe to call more than once; FCM returns the
  /// same token if nothing's changed, and the DB write is an upsert.
  static Future<void> registerDeviceToken() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final messaging = FirebaseMessaging.instance;

      // iOS requires explicit permission for push -- if the person says
      // no, FCM will simply never produce a token below, and that's
      // fine: registerDeviceToken() just quietly does nothing further.
      // The existing "Notifications" toggles on Setup are a separate,
      // in-app preference on top of this -- this permission request is
      // the OS-level gate that has to be granted first regardless of
      // what those toggles say.
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;

      await _saveToken(userId, token);

      // FCM tokens can rotate (app reinstall, OS-level refresh, etc.) --
      // this keeps the saved token current for as long as the app
      // process is alive, without needing another cold start.
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
        if (currentUserId != null) {
          _saveToken(currentUserId, newToken);
        }
      });
    } catch (e) {
      debugPrint('PUSH_SERVICE registerDeviceToken error: $e');
    }
  }

  static Future<void> _saveToken(String userId, String token) async {
    try {
      // Upsert on device_token (not user_id) -- a physical device can
      // only ever hold one live token. If this same phone previously
      // registered under a DIFFERENT account (this app's whole
      // multi-account testing pattern -- sign out, sign into someone
      // else), this correctly moves the token to whoever's signed in
      // now rather than leaving a stale row pointing at the old account.
      await Supabase.instance.client.from('device_tokens').upsert(
        {
          'user_id': userId,
          'device_token': token,
          'platform': 'ios',
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'device_token',
      );
    } catch (e) {
      debugPrint('PUSH_SERVICE saveToken error: $e');
    }
  }

  /// Call on sign-out, before the session actually clears -- removes
  /// this device's token so a signed-out phone can't keep receiving
  /// pushes meant for whoever signs in next on the same device.
  static Future<void> unregisterDeviceToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      await Supabase.instance.client
          .from('device_tokens')
          .delete()
          .eq('device_token', token);
    } catch (e) {
      debugPrint('PUSH_SERVICE unregisterDeviceToken error: $e');
    }
  }

  /// Sends a real push to every device belonging to the given users.
  /// Category matters: 'sos' always sends regardless of preference
  /// (same principle as the existing emergency SMS fallback -- a real
  /// emergency is never silently gated by a toggle); 'message' and
  /// 'check_in' respect each recipient's own notify_messages/
  /// notify_check_in preference, checked server-side in the Edge
  /// Function itself (not here -- this device has no way to know
  /// another person's preference, only their own).
  ///
  /// Fire-and-forget by design at every call site -- a push failing to
  /// send must never block or fail the action that triggered it (SOS
  /// alert, sending a message). The Edge Function itself also fails
  /// soft internally for the same reason.
  static Future<void> notify({
    required List<String> userIds,
    required String title,
    required String body,
    required String category,
    Map<String, String>? data,
  }) async {
    if (userIds.isEmpty) return;
    try {
      await Supabase.instance.client.functions.invoke(
        'send-push',
        body: {
          'user_ids': userIds,
          'title': title,
          'body': body,
          'category': category,
          if (data != null) 'data': data,
        },
      );
    } catch (e) {
      debugPrint('PUSH_SERVICE notify error: $e');
    }
  }
}
