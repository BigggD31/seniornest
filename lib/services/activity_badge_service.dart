import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_state.dart';

/// Sep 16 2026: "Show What's New" feature -- badge counts on the Home and
/// Legacy bottom-nav tabs for content that's landed since this person last
/// opened that tab, visible from anywhere in the app (not just while
/// sitting on that screen). Timestamp-based rather than a running counter
/// column: home_last_seen_at/legacy_last_seen_at live on
/// user_activity_state, and the badge count is always recomputed fresh
/// from feed_posts/legacy_entries rather than trusted to stay in sync on
/// its own. Tapping into either tab clears its count immediately -- no
/// per-item read tracking, matching D Von's call that people will see the
/// content anyway once they're on that screen.
///
/// A process-wide singleton on purpose: this app has no shared IndexedStack
/// shell (each of the six tabs is its own route -- see the deferred
/// "Bottom-nav IndexedStack architecture fix" backlog item), so nothing
/// screen-scoped could keep counting while the person is on a different
/// tab. Static ValueNotifiers survive across screens for the lifetime of
/// the app process; AppNavigation reads them via ValueListenableBuilder so
/// individual screens never need to know this service exists.
class ActivityBadgeService {
  static final ValueNotifier<int> homeCount = ValueNotifier<int>(0);
  static final ValueNotifier<int> legacyCount = ValueNotifier<int>(0);
  // Oct 8 2026: unread private (direct) messages across all conversations in
  // the current Nest. Unlike Home/Legacy this is read-state based (read_at),
  // so it stays until the messages are actually opened -- no timer.
  static final ValueNotifier<int> shareCount = ValueNotifier<int>(0);

  static RealtimeChannel? _channel;
  static DateTime? _homeLastSeen;
  static DateTime? _legacyLastSeen;
  static String? _nestId;
  static bool _initialized = false;
  static Timer? _periodicRefresh;
  static VoidCallback? _tabListener;
  static VoidCallback? _iconListener;
  static const MethodChannel _badgeChannel = MethodChannel('seniornest/badge');

  /// Oct 8 2026: app-icon number = sum of the three in-app tab numbers.
  /// iOS only (no-op elsewhere; errors swallowed).
  static void _syncIconBadge() {
    if (kIsWeb) return;
    final total = homeCount.value + legacyCount.value + shareCount.value;
    _badgeChannel.invokeMethod('setBadge', total).catchError((_) {});
  }

  /// Call once per signed-in session -- same two call sites as
  /// PushService.registerDeviceToken() (main.dart cold start,
  /// save_messages_prompt_screen.dart onboarding completion).
  /// Fire-and-forget by the same reasoning as that service: badges are a
  /// nice-to-have, never something that should add latency or block
  /// navigation.
  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final prefs = await SharedPreferences.getInstance();
      _nestId = prefs.getString('nest_id');
      if (_nestId == null || _nestId!.isEmpty) return;

      // ignoreDuplicates leaves an existing row's last-seen timestamps
      // untouched -- this only ever creates the row (defaulting both
      // timestamps to now()) the very first time a given user is seen.
      await Supabase.instance.client.from('user_activity_state').upsert(
        {'user_id': userId},
        onConflict: 'user_id',
        ignoreDuplicates: true,
      );

      final row = await Supabase.instance.client
          .from('user_activity_state')
          .select('home_last_seen_at, legacy_last_seen_at')
          .eq('user_id', userId)
          .maybeSingle();
      if (row != null) {
        _homeLastSeen =
            DateTime.tryParse(row['home_last_seen_at'] as String? ?? '');
        _legacyLastSeen =
            DateTime.tryParse(row['legacy_last_seen_at'] as String? ?? '');
      }

      _initialized = true;
      if (_iconListener == null) {
        _iconListener = _syncIconBadge;
        homeCount.addListener(_iconListener!);
        legacyCount.addListener(_iconListener!);
        shareCount.addListener(_iconListener!);
      }
      await _refreshCounts();
      _subscribeRealtime();
      // Oct 8 2026: tabs are never rebuilt (they live in one IndexedStack), so
      // counts must be re-checked on every tab switch and once a minute --
      // private messages have no live feed to trigger a refresh on their own.
      _tabListener ??= () => _refreshCounts();
      appActiveTabNotifier.removeListener(_tabListener!);
      appActiveTabNotifier.addListener(_tabListener!);
      _periodicRefresh?.cancel();
      _periodicRefresh =
          Timer.periodic(const Duration(seconds: 60), (_) => _refreshCounts());
    } catch (e) {
      debugPrint('ACTIVITY_BADGE_SERVICE init error: $e');
    }
  }

  static Future<bool> badgesEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('show_activity_badges') ?? true;
  }

  /// Called from the Setup toggle. Mirrors _togglePref's local-then-server
  /// pattern for notify_messages/notify_check_in/etc.
  static Future<void> setBadgesEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_activity_badges', value);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      try {
        await Supabase.instance.client
            .from('user_profiles')
            .update({'show_activity_badges': value}).eq('id', userId);
      } catch (e) {
        debugPrint('ACTIVITY_BADGE_SERVICE server sync error: $e');
      }
    }
    if (!value) {
      homeCount.value = 0;
      legacyCount.value = 0;
      shareCount.value = 0;
    } else {
      await _refreshCounts();
    }
  }

  /// Sep 16 2026: resilience fallback -- called from AppNavigation's own
  /// initState (every one of the 6 screens creates a fresh AppNavigation
  /// instance on arrival, since there's no shared IndexedStack shell), so
  /// counts get a real re-check on every tab visit, not solely whenever
  /// the realtime channel happens to deliver an insert event. Safe to
  /// call before initialize() has finished (or if it never runs, e.g.
  /// signed-out) -- _refreshCounts's own _initialized guard makes this a
  /// harmless no-op in that case, and initialize()'s own later call will
  /// pick it up once ready.
  static Future<void> refreshCounts() => _refreshCounts();

  static Future<void> _refreshCounts() async {
    if (!_initialized) return;
    if (!(await badgesEnabled())) {
      homeCount.value = 0;
      legacyCount.value = 0;
      shareCount.value = 0;
      return;
    }
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || _nestId == null) return;
    // Local non-null copy -- matches this codebase's existing convention
    // at every other .eq('nest_id', ...) call site (all pass a plain
    // non-nullable String, never a nullable field or an `as Object` cast).
    final nestId = _nestId!;
    try {
      final unreadDms = await Supabase.instance.client
          .from('private_messages')
          .select('id')
          .eq('nest_id', nestId)
          .eq('recipient_id', userId)
          .isFilter('read_at', null);
      shareCount.value = (unreadDms as List).length;
      if (_homeLastSeen != null) {
        final rows = await Supabase.instance.client
            .from('feed_posts')
            .select('id')
            .eq('nest_id', nestId)
            .neq('author_id', userId)
            .gt('created_at', _homeLastSeen!.toIso8601String());
        homeCount.value = (rows as List).length;
      }
      if (_legacyLastSeen != null) {
        final rows = await Supabase.instance.client
            .from('legacy_entries')
            .select('id')
            .eq('nest_id', nestId)
            .neq('user_id', userId)
            .gt('created_at', _legacyLastSeen!.toIso8601String());
        legacyCount.value = (rows as List).length;
      }
    } catch (e) {
      debugPrint('ACTIVITY_BADGE_SERVICE refresh error: $e');
    }
    // Always re-sync: ValueNotifier skips notifying on an unchanged value, but
    // the icon may still hold a stale number from a push received while closed.
    _syncIconBadge();
  }

  // Unfiltered-by-nest_id on the query itself is deliberately avoided here
  // (unlike safety_screen.dart's daily_checkins/daily_medications
  // listener) -- feed_posts and legacy_entries both have a real nest_id
  // column, so filtering the channel itself is both possible and cheaper.
  static void _subscribeRealtime() {
    // Non-null assertions safe here -- _subscribeRealtime is only ever
    // called from initialize() after the _nestId null/empty check has
    // already returned early. Written out explicitly (rather than
    // relying on Dart to promote a mutable static field across a
    // function boundary, which it won't) to avoid a nullable-value
    // analyzer error on PostgresChangeFilter's value param.
    final nestId = _nestId!;
    _channel = Supabase.instance.client
        .channel('activity_badges_realtime_$nestId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'feed_posts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'nest_id',
            value: nestId,
          ),
          callback: (payload) => _refreshCounts(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'legacy_entries',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'nest_id',
            value: nestId,
          ),
          callback: (payload) => _refreshCounts(),
        )
        .subscribe();
  }

  /// Called from family_feed_screen.dart's initState -- clears the badge
  /// the moment the person taps into Home, per D Von's call that people
  /// don't need per-item read tracking on this app.
  static Future<void> markHomeSeen() async {
    homeCount.value = 0;
    _homeLastSeen = DateTime.now().toUtc();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client.from('user_activity_state').update({
        'home_last_seen_at': _homeLastSeen!.toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', userId);
    } catch (e) {
      debugPrint('ACTIVITY_BADGE_SERVICE markHomeSeen error: $e');
    }
  }

  /// Called from legacy_screen.dart's initState. Same shape as
  /// markHomeSeen above.
  static Future<void> markLegacySeen() async {
    legacyCount.value = 0;
    _legacyLastSeen = DateTime.now().toUtc();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client.from('user_activity_state').update({
        'legacy_last_seen_at': _legacyLastSeen!.toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', userId);
    } catch (e) {
      debugPrint('ACTIVITY_BADGE_SERVICE markLegacySeen error: $e');
    }
  }

  /// Call on sign-out, same reasoning as PushService.unregisterDeviceToken
  /// -- a signed-out session shouldn't keep a live channel open or hand
  /// the next person who signs in on this device a stale prior-user's
  /// counts.
  static void reset() {
    _channel?.unsubscribe();
    _channel = null;
    _periodicRefresh?.cancel();
    _periodicRefresh = null;
    if (_tabListener != null) {
      appActiveTabNotifier.removeListener(_tabListener!);
    }
    _initialized = false;
    _homeLastSeen = null;
    _legacyLastSeen = null;
    _nestId = null;
    homeCount.value = 0;
    legacyCount.value = 0;
    shareCount.value = 0;
    _syncIconBadge();
  }
}
