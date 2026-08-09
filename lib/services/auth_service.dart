import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static SupabaseClient get _client => Supabase.instance.client;

  // ── Google Web Client ID (from env) ──────────────────────────────────────
  static const String _googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );
  static const String _googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );

  // ── Session helpers ───────────────────────────────────────────────────────
  static bool get isSignedIn => _client.auth.currentUser != null;
  static User? get currentUser => _client.auth.currentUser;
  static String? get currentUserId => _client.auth.currentUser?.id;

  // ── Google Sign-In ────────────────────────────────────────────────────────
  static Future<AuthResult> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // Web: use Supabase OAuth redirect
        await _client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: 'https://seniornest6932.builtwithrocket.new',
        );
        // OAuth redirect — result handled by auth state listener
        return AuthResult.success(null);
      } else {
        // Native: use google_sign_in package
        final googleSignIn = GoogleSignIn.instance;
        await googleSignIn.initialize(
          clientId: _googleIosClientId.isNotEmpty
              ? _googleIosClientId
              : null,
          serverClientId: _googleWebClientId.isNotEmpty
              ? _googleWebClientId
              : null,
        );

        // Explicit sign-in tap: always show the account picker.
        // (attemptLightweightAuthentication silently reuses a cached
        // account with no picker — wrong for an explicit "Sign In" tap.)
        final GoogleSignInAccount? googleUser =
            await googleSignIn.authenticate();

        final googleAuth = googleUser?.authentication;
        final idToken = googleAuth?.idToken;

        if (idToken == null) {
          return AuthResult.error(
            'Google sign-in failed: no ID token received.',
          );
        }

        final response = await _client.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
        );

        return AuthResult.success(response.user);
      }
    } on AuthException catch (e) {
      return AuthResult.error(_friendlyAuthError(e.message));
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('cancel') || msg.contains('Cancel')) {
        return AuthResult.cancelled();
      }
      return AuthResult.error('Google sign-in failed. Please try again.');
    }
  }

  // ── Apple Sign-In (native — no browser redirect needed) ─────────────────

  static Future<AuthResult> signInWithApple() async {
    try {
      if (kIsWeb) {
        await _client.auth.signInWithOAuth(
          OAuthProvider.apple,
          redirectTo: 'https://seniornest6932.builtwithrocket.new',
        );
        return AuthResult.success(null);
      }

      final rawNonce = _client.auth.generateRawNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        return AuthResult.error('Apple sign-in failed: no identity token.');
      }

      final response = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      return AuthResult.success(response.user);
    } on AuthException catch (e) {
      return AuthResult.error(_friendlyAuthError(e.message));
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return AuthResult.cancelled();
      }
      return AuthResult.error('Apple sign-in failed. Please try again.');
    } catch (e) {
      return AuthResult.error('Apple sign-in failed. Please try again.');
    }
  }

  // ── Email Sign-Up ─────────────────────────────────────────────────────────
  static Future<AuthResult> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: displayName != null && displayName.isNotEmpty
            ? {'display_name': displayName}
            : null,
      );
      return AuthResult.success(response.user);
    } on AuthException catch (e) {
      return AuthResult.error(_friendlyAuthError(e.message));
    } catch (e) {
      return AuthResult.error(
        'Sign-up failed. Please check your connection and try again.',
      );
    }
  }

  // ── Email Sign-In ─────────────────────────────────────────────────────────
  static Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      return AuthResult.success(response.user);
    } on AuthException catch (e) {
      return AuthResult.error(_friendlyAuthError(e.message));
    } catch (e) {
      return AuthResult.error(
        'Sign-in failed. Please check your connection and try again.',
      );
    }
  }

  // ── Sign Out ──────────────────────────────────────────────────────────────
  static Future<void> signOut() async {
    try {
      // Sign out from Google if signed in natively
      if (!kIsWeb) {
        try {
          final googleSignIn = GoogleSignIn.instance;
          await googleSignIn.disconnect();
          debugPrint('AUTH: Google disconnect() succeeded');
        } catch (e, st) {
          debugPrint('AUTH ERROR: Google disconnect() failed: $e');
          debugPrint('AUTH ERROR stack: $st');
        }
      }
      await _client.auth.signOut();
      debugPrint('AUTH: Supabase signOut() succeeded');
    } catch (e, st) {
      debugPrint('AUTH ERROR: Supabase signOut() failed: $e');
      debugPrint('AUTH ERROR stack: $st');
    }
  }

  // ── Auth state stream ─────────────────────────────────────────────────────
  static Stream<AuthState> get authStateChanges =>
      _client.auth.onAuthStateChange;

  /// Reliably resolves the current user's ID. currentUser?.id can stay null
  /// for longer than a fixed-count retry loop can cover in some real-world
  /// timing cases -- confirmed directly via on-screen diagnostics on Aug 7
  /// 2026, where it stayed null through 3 retries with delays AND through a
  /// subsequent unrelated screen's send action minutes later. Rather than
  /// guess at another delay, this actively waits for a genuine signed-in
  /// auth state event as the last resort, which is the actual signal that
  /// the session is ready -- not an assumption about how long that takes.
  static Future<String?> getReliableUserId({Duration timeout = const Duration(seconds: 5)}) async {
    final immediate = _client.auth.currentUser?.id;
    if (immediate != null) return immediate;

    try {
      final refreshed = await _client.auth.refreshSession();
      final afterRefresh = refreshed.session?.user.id ?? _client.auth.currentUser?.id;
      if (afterRefresh != null) return afterRefresh;
    } catch (e) {
      debugPrint('getReliableUserId: refreshSession threw: $e');
    }

    try {
      final event = await _client.auth.onAuthStateChange
          .firstWhere((state) => state.session?.user.id != null)
          .timeout(timeout);
      return event.session?.user.id;
    } catch (e) {
      debugPrint('getReliableUserId: waiting for auth state event failed/timed out: $e');
      return null;
    }
  }

  // Every locally-cached key that's tied to a specific account, not the
  // device -- audited Aug 8 2026 after dark_mode, user_role, and nest_name
  // were all confirmed bleeding between accounts on the same device.
  //
  // CORRECTED same day after a real regression: this list originally also
  // included nest_id, invite_code, user_role, joined_via_invite,
  // display_name, preferred_name, senior_name, relationship, nest_name,
  // birthday, and anniversary -- all of which get actively SET during the
  // invite-code/onboarding flow itself, BEFORE sign-in fully completes
  // (which is when this wipe runs). Wiping them destroyed correct,
  // freshly-set data for a brand-new account mid-onboarding, not just
  // stale data from a previous one -- a family member who'd just joined
  // via invite ended up looking like a nest owner with no invite code at
  // all. Those fields are deliberately excluded now; has_onboarded /
  // onboarding_complete staying in this list is what forces a genuinely
  // different account through onboarding fresh, which naturally and
  // correctly repopulates all of them anyway -- no separate wipe needed.
  static const List<String> _accountScopedPrefsKeys = [
    'has_onboarded', 'onboarding_complete',
    'bookmarks', 'bookmarked_items', 'dark_mode',
    'meds_reminders', 'daily_check_in',
    'notify_check_in', 'notify_messages', 'is_guest',
    'has_real_post', 'has_sent_messages',
    'has_sent_stories', 'removed_member_ids',
    'story_prompts', 'vip_code',
    'cached_nest_members', 'cached_nest_members_nest_id', 'cached_nest_members_user_id',
    'cached_real_messages', 'cached_real_messages_nest_id',
    'cached_checkin_nest_id', 'cached_checkin_date', 'cached_checkin_senior_id',
    'cached_checkin_senior_name', 'cached_checkin_checked_in', 'cached_checkin_time',
  ];

  /// Detects a genuine account switch on this device and wipes every
  /// locally cached piece of account-specific data before anything can
  /// read a stale value left over from the previous person. This is the
  /// single, centralized fix for what were previously several separate
  /// bugs sharing one root cause: local preferences with no connection to
  /// which account actually set them.
  ///
  /// Pass [knownUserId] when it's already available (e.g. straight from a
  /// sign-in callback) to skip an unnecessary re-resolution; otherwise
  /// falls back to [getReliableUserId]. Uses the reliable resolver
  /// specifically, not a raw currentUser?.id check -- a session that's
  /// still establishing (a real, confirmed race condition in this exact
  /// codebase) must never be mistaken for "a different user," which would
  /// wipe a legitimately-signed-in person's own data for no reason.
  static Future<void> clearStaleAccountDataIfUserChanged({String? knownUserId}) async {
    final currentUserId = knownUserId ?? await getReliableUserId();
    if (currentUserId == null) {
      // Can't reliably determine who's signed in right now -- do nothing
      // rather than risk wiping real data on an inconclusive check.
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final lastKnownUserId = prefs.getString('last_known_user_id');

    if (lastKnownUserId == null || lastKnownUserId.isEmpty) {
      // First time this check has ever run on this device (e.g. right
      // after this feature ships) -- just record who's signed in now,
      // don't wipe anything, since there's no actual evidence of a switch.
      await prefs.setString('last_known_user_id', currentUserId);
      return;
    }

    if (lastKnownUserId == currentUserId) {
      return;
    }

    // Confirmed genuine account switch -- wipe every account-specific key.
    for (final key in _accountScopedPrefsKeys) {
      await prefs.remove(key);
    }
    // Date-suffixed keys (good_today_2026-08-08, meds_reminder_2026-08-08,
    // etc.) need prefix matching since the exact key varies by day.
    final allKeys = prefs.getKeys().toList();
    for (final key in allKeys) {
      if (key.startsWith('good_today_') || key.startsWith('meds_reminder_')) {
        await prefs.remove(key);
      }
    }

    await prefs.setString('last_known_user_id', currentUserId);
  }

  // ── Friendly error messages ───────────────────────────────────────────────
  static String _friendlyAuthError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid email or password')) {
      return 'Incorrect email or password. Please try again.';
    }
    if (lower.contains('email already registered') ||
        lower.contains('user already registered')) {
      return 'An account with this email already exists. Try signing in instead.';
    }
    if (lower.contains('password should be at least') ||
        lower.contains('password is too short')) {
      return 'Password must be at least 6 characters.';
    }
    if (lower.contains('invalid email')) {
      return 'Please enter a valid email address.';
    }
    if (lower.contains('network') || lower.contains('connection')) {
      return 'Network error. Please check your connection and try again.';
    }
    if (lower.contains('rate limit')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    return message.isNotEmpty
        ? message
        : 'Something went wrong. Please try again.';
  }
}

// ── Result type ───────────────────────────────────────────────────────────────
class AuthResult {
  final User? user;
  final String? errorMessage;
  final bool isCancelled;

  const AuthResult._({this.user, this.errorMessage, this.isCancelled = false});

  factory AuthResult.success(User? user) => AuthResult._(user: user);
  factory AuthResult.error(String message) =>
      AuthResult._(errorMessage: message);
  factory AuthResult.cancelled() => AuthResult._(isCancelled: true);

  bool get isSuccess => errorMessage == null && !isCancelled;
}