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

  /// Oct 9 2026: bumped whenever the account's switches change on the server
  /// (e.g. toggled on another device). Setup listens and re-reads them.
  static final ValueNotifier<int> settingsVersion = ValueNotifier<int>(0);

  static RealtimeChannel? _channel;
  static String? _channelKey;
  static DateTime? _homeLastSeen;
  static DateTime? _legacyLastSeen;
  static String? _nestId;
  static String? _userId;
  static bool _initialized = false;
  static bool _initializing = false;
  static int _initRetries = 0;
  static Timer? _retryTimer;
  static Timer? _debounce;
  static Timer? _periodicRefresh;
  static VoidCallback? _tabListener;
  static VoidCallback? _iconListener;
  static String _lastLogged = '';
  static const MethodChannel _badgeChannel = MethodChannel('seniornest/badge');

  /// Oct 8 2026: app-icon number = sum of the three in-app tab numbers.
  /// iOS only (no-op elsewhere; errors swallowed).
  static void _syncIconBadge() {
    if (kIsWeb) return;
    final total = homeCount.value + legacyCount.value + shareCount.value;
    _badgeChannel.invokeMethod('setBadge', total).catchError((_) {});
  }

  static Future<void> _log(String msg) async {
    try {
      final who = Supabase.instance.client.auth.currentUser?.id ?? 'none';
      await Supabase.instance.client.from('temp_debug_logs').insert({
        'tag': 'BADGE_DEBUG',
        'message': '[$who] $msg',
      });
    } catch (_) {}
  }

  /// Safe to call any number of times, from anywhere. Concurrent calls are
  /// collapsed, a different signed-in user triggers a clean re-init, and a
  /// failed start (e.g. nest not restored yet right after sign-in) retries.
  static Future<void> initialize() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    if (_initialized && _userId == uid) return;
    if (_initializing) return;
    if (_userId != null && _userId != uid) reset();
    _initializing = true;
    try {
      final ok = await _initializeInner(uid);
      if (!ok) _scheduleInitRetry();
    } catch (e) {
      debugPrint('ACTIVITY_BADGE_SERVICE init error: $e');
      _scheduleInitRetry();
    } finally {
      _initializing = false;
    }
  }

  static void _scheduleInitRetry() {
    if (_initRetries >= 6) return;
    _initRetries++;
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: 3 * _initRetries), () {
      initialize();
    });
  }

  static Future<bool> _initializeInner(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final nest = prefs.getString('nest_id');
    if (nest == null || nest.isEmpty) {
      _log('init waiting: no nest_id yet (try $_initRetries)');
      return false;
    }
    final client = Supabase.instance.client;
    await client.from('user_activity_state').upsert(
      {'user_id': uid},
      onConflict: 'user_id',
      ignoreDuplicates: true,
    );
    final row = await client
        .from('user_activity_state')
        .select('home_last_seen_at, legacy_last_seen_at')
        .eq('user_id', uid)
        .maybeSingle();
    // Pull this account's switches so a stale local copy can't hide numbers.
    await _pullSettings(uid, notify: false);
    if (client.auth.currentUser?.id != uid) return false;

    _userId = uid;
    _nestId = nest;
    if (row != null) {
      _homeLastSeen =
          DateTime.tryParse(row['home_last_seen_at'] as String? ?? '');
      _legacyLastSeen =
          DateTime.tryParse(row['legacy_last_seen_at'] as String? ?? '');
    }
    _initialized = true;
    _initRetries = 0;
    if (_iconListener == null) {
      _iconListener = _syncIconBadge;
      homeCount.addListener(_iconListener!);
      legacyCount.addListener(_iconListener!);
      shareCount.addListener(_iconListener!);
    }
    await _refreshCounts();
    _subscribeRealtime();
    _tabListener ??= () => _scheduleRefresh();
    appActiveTabNotifier.removeListener(_tabListener!);
    appActiveTabNotifier.addListener(_tabListener!);
    _periodicRefresh?.cancel();
    _periodicRefresh =
        Timer.periodic(const Duration(seconds: 60), (_) => _refreshCounts());
    _log('init ok nest=$nest');
    return true;
  }

  /// Reads the 6 account switches from the server into local prefs/notifiers.
  static Future<void> _pullSettings(String uid, {bool notify = true}) async {
    try {
      final row = await Supabase.instance.client
          .from('user_profiles')
          .select(
              'notify_messages, notify_check_in, notify_activity, show_activity_badges, meds_reminders_enabled, daily_checkin_enabled')
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return;
      bool pick(String k) => row[k] is bool ? row[k] as bool : true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notify_messages', pick('notify_messages'));
      await prefs.setBool('notify_check_in', pick('notify_check_in'));
      await prefs.setBool('notify_activity', pick('notify_activity'));
      await prefs.setBool('show_activity_badges', pick('show_activity_badges'));
      await prefs.setBool('meds_reminders', pick('meds_reminders_enabled'));
      await prefs.setBool('daily_check_in', pick('daily_checkin_enabled'));
      appMyCheckinEnabledNotifier.value = pick('daily_checkin_enabled');
      appMyMedsRemindersEnabledNotifier.value = pick('meds_reminders_enabled');
      if (notify) settingsVersion.value++;
    } catch (e) {
      debugPrint('ACTIVITY_BADGE_SERVICE pullSettings error: $e');
    }
  }

  static void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _refreshCounts());
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
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId != _userId) return;
    if (!(await badgesEnabled())) {
      homeCount.value = 0;
      legacyCount.value = 0;
      shareCount.value = 0;
      return;
    }
    // The nest can change after init (login restores it a moment later).
    final prefs = await SharedPreferences.getInstance();
    final prefNest = prefs.getString('nest_id');
    if (prefNest != null && prefNest.isNotEmpty && prefNest != _nestId) {
      _nestId = prefNest;
      _subscribeRealtime();
    }
    if (_nestId == null) return;
    final nestId = _nestId!;
    try {
      final unreadDms = await Supabase.instance.client
          .from('private_messages')
          .select('id')
          .eq('nest_id', nestId)
          .eq('recipient_id', userId)
          .isFilter('read_at', null);
      final dm = (unreadDms as List).length;
      int home = homeCount.value;
      int legacy = legacyCount.value;
      if (_homeLastSeen != null) {
        final rows = await Supabase.instance.client
            .from('feed_posts')
            .select('id')
            .eq('nest_id', nestId)
            .neq('author_id', userId)
            .gt('created_at', _homeLastSeen!.toIso8601String());
        home = (rows as List).length;
      }
      if (_legacyLastSeen != null) {
        final rows = await Supabase.instance.client
            .from('legacy_entries')
            .select('id')
            .eq('nest_id', nestId)
            .neq('user_id', userId)
            .gt('created_at', _legacyLastSeen!.toIso8601String());
        legacy = (rows as List).length;
      }
      if (Supabase.instance.client.auth.currentUser?.id != userId) return;
      shareCount.value = dm;
      homeCount.value = home;
      legacyCount.value = legacy;
      final sig = '$home/$legacy/$dm';
      if (sig != _lastLogged) {
        _lastLogged = sig;
        _log('counts home=$home legacy=$legacy dm=$dm');
      }
    } catch (e) {
      debugPrint('ACTIVITY_BADGE_SERVICE refresh error: $e');
    }
    // Always re-sync: ValueNotifier skips notifying on an unchanged value, but
    // the icon may still hold a stale number from a push received while closed.
    _syncIconBadge();
  }

  /// One channel per user+nest. Live: new posts, new legacy stories, direct
  /// messages to me, and changes to my own switches (from another device).
  static void _subscribeRealtime() {
    final nestId = _nestId;
    final uid = _userId;
    if (nestId == null || uid == null) return;
    final key = '$uid$nestId';
    if (_channel != null && _channelKey == key) return;
    final old = _channel;
    if (old != null) {
      Supabase.instance.client.removeChannel(old);
    }
    _channelKey = key;
    _channel = Supabase.instance.client
        .channel('activity_$key')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'feed_posts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'nest_id',
            value: nestId,
          ),
          callback: (payload) => _scheduleRefresh(),
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
          callback: (payload) => _scheduleRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'private_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: uid,
          ),
          callback: (payload) => _scheduleRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'user_profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: uid,
          ),
          callback: (payload) async {
            await _pullSettings(uid);
            _scheduleRefresh();
          },
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
    final ch = _channel;
    if (ch != null) {
      Supabase.instance.client.removeChannel(ch);
    }
    _channel = null;
    _channelKey = null;
    _periodicRefresh?.cancel();
    _periodicRefresh = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _debounce?.cancel();
    _debounce = null;
    if (_tabListener != null) {
      appActiveTabNotifier.removeListener(_tabListener!);
    }
    _initialized = false;
    _initializing = false;
    _initRetries = 0;
    _userId = null;
    _homeLastSeen = null;
    _legacyLastSeen = null;
    _nestId = null;
    _lastLogged = '';
    homeCount.value = 0;
    legacyCount.value = 0;
    shareCount.value = 0;
    _syncIconBadge();
  }
}
