import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Writes a confirmed Apple purchase into the `subscriptions` table so the
/// rest of the app can tell whether a person is entitled.
///
/// Oct 14 2026: first-time signup pays on the subscribe screen BEFORE the
/// account exists (creating the account is deliberately the last onboarding
/// step). With nobody signed in there was no row to write to, so the purchase
/// was silently dropped and the person was sent back to the subscribe screen
/// on their next launch. Now the purchase is held on the phone and written the
/// moment an account exists ([flushPending], called after every sign-in /
/// sign-up, before the Nest attach step, and at launch as a safety net).
class SubscriptionRecorder {
  static const String _monthlyProductId = 'com.devonmurphy.seniornest.monthly';
  static const String _yearlyProductId = 'com.devonmurphy.seniornest.yearly';
  static const String _additionalNestMonthlyProductId =
      'com.devonmurphy.seniornest.additionalnest.monthly';
  static const String _additionalNestYearlyProductId =
      'com.devonmurphy.seniornest.additionalnest.yearly';

  static const String _kProduct = 'pending_iap_product_id';
  static const String _kTxn = 'pending_iap_txn_id';
  static const String _kAtMs = 'pending_iap_at_ms';
  static const String _kRestore = 'pending_iap_is_restore';

  // A held purchase older than this is dropped rather than credited to
  // whoever happens to sign in on the device much later.
  static const Duration _pendingMaxAge = Duration(hours: 48);

  /// Records a purchase. With no signed-in account yet, holds it on the phone.
  static Future<void> record(
    String productId,
    String? transactionId, {
    String? nestId,
    bool isRestore = false,
  }) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      await _stashPending(productId, transactionId, isRestore);
      return;
    }
    await _writeRow(userId, productId, transactionId,
        nestId: nestId, isRestore: isRestore);
  }

  /// Writes a purchase held on the phone, if there is one and an account now
  /// exists. Safe to call any time; a no-op when nothing is held.
  static Future<void> flushPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final productId = prefs.getString(_kProduct);
      if (productId == null || productId.isEmpty) return;

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return; // still no account; keep holding it

      final atMs = prefs.getInt(_kAtMs) ?? 0;
      final age = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(atMs));
      if (age > _pendingMaxAge) {
        await _clearPending(prefs);
        return;
      }

      final ok = await _writeRow(
        userId,
        productId,
        prefs.getString(_kTxn),
        isRestore: prefs.getBool(_kRestore) ?? false,
      );
      if (ok) await _clearPending(prefs);
    } catch (e) {
      debugPrint('SUBSCRIPTION_FLUSH_ERROR: $e');
    }
  }

  static Future<void> _stashPending(
      String productId, String? transactionId, bool isRestore) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kProduct, productId);
      if (transactionId != null) {
        await prefs.setString(_kTxn, transactionId);
      } else {
        await prefs.remove(_kTxn);
      }
      await prefs.setInt(_kAtMs, DateTime.now().millisecondsSinceEpoch);
      await prefs.setBool(_kRestore, isRestore);
    } catch (e) {
      debugPrint('SUBSCRIPTION_STASH_ERROR: $e');
    }
  }

  static Future<void> _clearPending(SharedPreferences prefs) async {
    await prefs.remove(_kProduct);
    await prefs.remove(_kTxn);
    await prefs.remove(_kAtMs);
    await prefs.remove(_kRestore);
  }

  // Moved unchanged from subscribe_nest_screen.dart's _recordSubscription,
  // except that it now returns whether the write succeeded.
  static Future<bool> _writeRow(
    String userId,
    String productId,
    String? transactionId, {
    String? nestId,
    bool isRestore = false,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      final now = DateTime.now();
      // PROVISIONAL expiry only. The phone cannot know whether Apple started
      // a 3-day trial or charged right away, so it never guesses a long
      // window. A new purchase gets 3 days of access here; the real
      // paid-through date is written by the server when Apple reports it
      // (apple-subscription-webhook) and always wins. A later expiry already
      // on the row is never shortened, and a "restored" event never extends
      // anything. Lifetime/promo entitlements never expire.
      DateTime? expiresAt;
      String status = 'active';
      if (productId == _yearlyProductId ||
          productId == _additionalNestYearlyProductId ||
          productId == _monthlyProductId ||
          productId == _additionalNestMonthlyProductId) {
        expiresAt = now.add(const Duration(days: 3));
      } else {
        // promo / lifetime-style entitlement
        expiresAt = null;
        status = 'lifetime';
      }
      final row = {
        'user_id': userId,
        'nest_id': nestId,
        'product_id': productId,
        'status': status,
        'purchase_date': now.toIso8601String(),
        'expires_at': expiresAt?.toIso8601String(),
        'transaction_id': transactionId,
        'updated_at': now.toIso8601String(),
      };
      // Explicit check-then-write instead of upsert(onConflict: 'user_id,nest_id'):
      // Postgres unique constraints don't treat NULL = NULL, so a plain
      // upsert wouldn't reliably catch a retry/double-tap when nestId is null
      // (the first-time-signup case). Mirrors the same pattern used in the
      // redeem_vip_code() DB function for the same reason.
      var query = supabase
          .from('subscriptions')
          .select('id, expires_at, status')
          .eq('user_id', userId);
      query = nestId == null
          ? query.isFilter('nest_id', null)
          : query.eq('nest_id', nestId);
      final existing = await query.maybeSingle();
      if (existing != null) {
        // A restored purchase must never touch an existing row: the server
        // already holds Apple's real dates.
        if (isRestore) return true;
        if (existing['status'] == 'lifetime') return true;
        final existingExpiry =
            DateTime.tryParse('${existing['expires_at'] ?? ''}');
        if (existingExpiry != null &&
            expiresAt != null &&
            existingExpiry.isAfter(expiresAt)) {
          row.remove('expires_at');
        }
        await supabase
            .from('subscriptions')
            .update(row)
            .eq('id', existing['id'] as String);
      } else {
        await supabase.from('subscriptions').insert(row);
      }
      // Pull in Apple's verified dates if Apple's notification already
      // reached the server. Harmless no-op otherwise.
      try {
        await supabase.rpc('reconcile_my_subscription');
      } catch (_) {}
      return true;
    } catch (e) {
      debugPrint('SUBSCRIPTION_RECORD_ERROR: $e');
      return false;
    }
  }
}
