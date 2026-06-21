import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
        } catch (_) {}
      }
      await _client.auth.signOut();
    } catch (_) {}
  }

  // ── Auth state stream ─────────────────────────────────────────────────────
  static Stream<AuthState> get authStateChanges =>
      _client.auth.onAuthStateChange;

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