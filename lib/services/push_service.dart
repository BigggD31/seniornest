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
      // Sep 12 2026: this whole function used to fail completely
      // silently at every possible step (permission denied, no token,
      // any exception) -- debugPrint only, nothing ever visible outside
      // a live Xcode console. That's how zero device tokens ever got
      // registered, on any account, on any build, without a single
      // trace anywhere. Logging every real outcome here (fire-and-forget,
      // same pattern as the existing ROLE_DEBUG entries in
      // save_messages_prompt_screen.dart) so the next test tells us
      // definitively which step is actually breaking, instead of
      // guessing from the outside again.
      await _logPushDebug(
          'permission_status=${settings.authorizationStatus} userId=$userId');
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }

      // Registered here, before the APNs wait below, rather than only
      // after a successful getToken() -- if APNs registration is slow
      // enough that the retry loop below gives up, this listener is
      // still the one thing that can pick up a token that arrives later
      // in this same app session. Also handles ordinary token rotation
      // (reinstall, OS-level refresh) for as long as the app stays open.
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
        if (currentUserId != null) {
          _saveToken(currentUserId, newToken);
        }
      });

      // Sep 14 2026: confirmed via the debug log this same instrumentation
      // caught -- both test devices got AuthorizationStatus.authorized
      // (the permission fix worked), but getToken() immediately threw
      // '[firebase_messaging/apns-token-not-set]'. This is a well-known
      // race on iOS: requestPermission() returning "authorized" only
      // means iOS has decided to allow it -- actually registering the
      // device with Apple's push service and handing this app a raw
      // APNs token happens asynchronously afterward, on iOS's own
      // schedule (usually under a second, but not guaranteed), and FCM's
      // getToken() needs that raw APNs token to exist first. Calling
      // getToken() in the very next line, with no wait, was a race we
      // were always going to lose most of the time. Poll for the APNs
      // token directly (not a fixed sleep) so this resolves as fast as
      // the OS actually allows, with a generous ceiling for a slow
      // network or first-launch registration.
      String? apnsToken = await messaging.getAPNSToken();
      var apnsAttempts = 0;
      while (apnsToken == null && apnsAttempts < 10) {
        await Future.delayed(const Duration(milliseconds: 500));
        apnsToken = await messaging.getAPNSToken();
        apnsAttempts++;
      }
      await _logPushDebug(
          'APNS token after $apnsAttempts retries: ${apnsToken == null ? 'still null' : 'present'}');
      if (apnsToken == null) {
        // Give up on this attempt -- the onTokenRefresh listener
        // registered above is still active and will catch it if APNs
        // registration completes later in this same app session.
        return;
      }

      final token = await messaging.getToken();
      await _logPushDebug(
          'getToken() returned: ${token == null ? 'null' : 'a token (len ${token.length})'}');
      if (token == null || token.isEmpty) return;

      await _saveToken(userId, token);
    } catch (e) {
      debugPrint('PUSH_SERVICE registerDeviceToken error: $e');
      await _logPushDebug('registerDeviceToken() threw: $e');
    }
  }

  static Future<void> _logPushDebug(String message) async {
    try {
      await Supabase.instance.client.from('temp_debug_logs').insert({
        'tag': 'PUSH_DEBUG',
        'message': message,
      });
    } catch (_) {}
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
      await _logPushDebug('device_tokens upsert OK for userId=$userId');
    } catch (e) {
      debugPrint('PUSH_SERVICE saveToken error: $e');
      await _logPushDebug('device_tokens upsert FAILED for userId=$userId: $e');
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
