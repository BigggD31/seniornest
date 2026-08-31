import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_state.dart';

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
  //
  // vip_code missed that same audit (build 161 fix) -- it's set at
  // role_choice_screen before the account exists, same as the fields
  // above, then wiped here before senior/family onboarding ever reads it
  // back to actually redeem it. Redemption silently never ran: no error,
  // no row in vip_code_redemptions, no VIP badge, even though the code
  // was accepted on screen and the account correctly became a Nest Owner.
  static const List<String> _accountScopedPrefsKeys = [
    'has_onboarded', 'onboarding_complete',
    'bookmarks', 'bookmarked_items', 'dark_mode',
    'meds_reminders', 'daily_check_in',
    'notify_check_in', 'notify_messages', 'is_guest',
    'has_real_post', 'has_sent_messages',
    'has_sent_stories', 'removed_member_ids',
    'story_prompts',
    // Aug 21 2026: reverted adding user_role here -- D Von correctly
    // pushed back that this wasn't a new build-203 issue, and checking
    // git history confirmed he was right. user_role was deliberately
    // excluded from this list in an Aug 9 commit (63cf61e), for a real,
    // documented reason: it gets actively set DURING the invite-code/
    // onboarding flow, before sign-in fully completes, and wiping it
    // broke a family member's fresh onboarding (they ended up looking
    // like the nest owner mid-signup). Re-adding it would have risked
    // reintroducing that exact bug while not actually explaining what's
    // different about build 203. The real cause of the dead Answer
    // button is still being investigated.
    'cached_nest_members', 'cached_nest_members_nest_id', 'cached_nest_members_user_id',
    'cached_real_messages', 'cached_real_messages_nest_id',
    // Aug 27 2026: cached_checkin_senior_name/senior_id/nest_id were
    // caught in the "cached_checkin_* deliberately excluded" exemption
    // below too, but that reasoning only actually applies to STATUS
    // flags ("has the senior checked in today," "were meds taken") --
    // these three are IDENTITY, not status: which nest this is and who
    // the senior in it is. A stale identity value surviving a genuine
    // account switch is exactly the kind of cross-account bleed this
    // whole list exists to prevent -- confirmed via D Von's real Aug 26
    // test: a brand-new account with a brand-new empty nest (zero real
    // members yet) showed a previous test's senior's name on Safety and
    // Legacy, sourced from this exact cache. The status flags below
    // stay excluded -- their own self-correction-via-live-check
    // reasoning is still correct and unrelated to this.
    'cached_checkin_senior_name', 'cached_checkin_senior_id', 'cached_checkin_nest_id',
    // Aug 31 2026: found via Audit 1 (cross-session state sweep) --
    // "has this nest's owner shared their invite code yet" is a
    // nest-specific fact, not a device preference, and wasn't in this
    // list or self-guarded anywhere else. Without this, a brand-new
    // nest on the same device could incorrectly inherit "already
    // shared" from whichever account used this device last.
    'invite_code_shared',
    // cached_checkin_* (status only: checked_in, date, meds_taken,
    // meds_time, time) deliberately excluded -- "has the senior checked in
    // today" is a nest-level fact, not tied to who's currently viewing it.
    // Wiping it briefly showed "not checked in" right after switching
    // accounts, even though a live server re-check should correct it
    // shortly after.
    //
    // nest_name, nest_id, invite_code, and joined_via_invite were
    // PREVIOUSLY excluded from this list entirely, on the reasoning that
    // they're legitimately set mid-onboarding, before the account-switch
    // check downstream (in _navigateToHome) even runs, and wiping them
    // there would destroy a fresh signup's own just-entered values. That
    // reasoning was correct for that ONE call site, but the fix was too
    // broad: excluding them HERE meant they never got wiped for a genuine
    // switch ANYWHERE else in the app either -- which is exactly why they
    // kept independently resurfacing all night as "cross contamination" in
    // different specific screens (a fresh onboarding field pre-filled with
    // a stale nest name; a Setup screen showing a different account's real
    // invite code) even after each individual display bug was patched.
    // Each fix closed one leak; this list was the actual source feeding
    // all of them. Now included here like everything else, with the one
    // legitimate exception (a fresh signup's own in-progress values)
    // handled locally at its one real call site in _navigateToHome
    // instead, via capture-before-wipe/restore-after -- see the comment
    // there for the full explanation.
    'nest_name', 'nest_id', 'invite_code', 'joined_via_invite',
    // Aug 21 2026: found while chasing D Von's report of the pin icon
    // showing up on a member's own page -- cached_is_nest_owner was
    // missing from this list entirely. Switch from an owner account to a
    // member account on the same device (D Von's exact testing pattern),
    // and the member's session would silently inherit the PREVIOUS
    // account's cached "yes, I'm the owner" flag, since nothing ever
    // wiped it. main.dart reads this cache directly into
    // appIsNestOwnerNotifier before the real app ever builds, and
    // family_feed_screen.dart's pin permission check (_canPinPost) trusts
    // that notifier completely -- so a stale true here means a real
    // member sees and can use owner-only pin controls on their own posts,
    // not just a display glitch. cached_is_vip_member has the identical
    // gap and the identical risk (a different, non-VIP account silently
    // inheriting a previous account's paid status on the same device) --
    // found while checking for siblings of the same bug shape, fixed
    // here too rather than waiting to be reported separately.
    'cached_is_nest_owner', 'cached_is_vip_member',
    // Aug 29 2026: found during a systematic audit prompted by D Von
    // still seeing "flash of old info then correct" after switching
    // between 10+ accounts -- these four are core identity fields
    // (resolved into app-wide notifiers at cold-start in main.dart's
    // _resolveInitialRoute, gated behind the branded loading screen,
    // same correct one-time-hydration architecture already used
    // correctly for nest_name/cached_is_nest_owner/etc. above). They're
    // only ever written during onboarding or a Setup edit -- never
    // automatically re-synced from Supabase just because an
    // already-onboarded account signs back in on this device. Missing
    // from this list meant that correct architecture was occasionally
    // hydrating itself from the PREVIOUS account's leftover values.
    // Same root cause, same fix shape as every entry above.
    'display_name', 'preferred_name', 'user_name', 'relationship',
    'birthday', 'anniversary',
    // vip_code is shorter-lived (read only within the onboarding flow
    // itself, to carry a redeemed code from role_choice_screen forward
    // into account creation), but it's exactly the same bug shape as the
    // onboarding-draft bleed fixed Aug 29: a stale value from one
    // abandoned onboarding attempt surviving into a brand-new one.
    'vip_code',
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
    // Aug 21 2026: found this is the actual, precise remaining cause of
    // the 4-5s delay D Von kept seeing before the grandmother photo,
    // even after the earlier fixes to main.dart's own wait. This
    // function runs unconditionally as the very first thing on every
    // cold start, before either of those fixes even get a chance to
    // matter. getReliableUserId() below (when knownUserId isn't passed)
    // tries a real refreshSession() network call, and if that comes back
    // empty, then WAITS UP TO 5 FULL SECONDS for an auth state change
    // event that will never fire on a device that's never signed in --
    // there's no sign-in happening for it to detect. hasOnboarded is
    // already a local, instant read (no network) -- if a device has
    // never onboarded, there is definitively no session this function
    // could ever need to protect, so there's nothing to gain by calling
    // getReliableUserId() at all here. Skips straight to "nothing to
    // do," matching this function's own existing behavior for an
    // inconclusive check, just without the 5s wait to get there. Any
    // device that HAS onboarded before still goes through the exact
    // same getReliableUserId() call as before, completely unchanged --
    // this only bypasses it for a device with no prior account at all.
    if (knownUserId == null) {
      final prefs = await SharedPreferences.getInstance();
      final hasOnboarded = prefs.getBool('has_onboarded') ?? false;
      if (!hasOnboarded) return;
    }
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

    // Aug 21 2026: originally just re-synced appDarkModeNotifier here,
    // since main.dart only re-syncs notifiers at cold app launch, not at
    // an in-session sign-out/sign-in cycle (the exact scenario this whole
    // function exists for). Aug 31 2026, Pre-Ship Audit 1: that gap was
    // never actually specific to dark_mode -- every account-relevant
    // notifier had the same problem, just less visible than a theme
    // flipping. Now calls the same shared resolution function main.dart
    // uses at cold start (see resolveAppNotifiersFromPrefs in
    // app_state.dart for the full reasoning), so a warm switch gets every
    // notifier reset from the storage just wiped above -- not just the
    // one that happened to get noticed first.
    await resolveAppNotifiersFromPrefs(prefs);

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