import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/app_navigation.dart';
import '../../widgets/keyboard_done_bar.dart';
import '../../widgets/collapsible_date_group_header.dart';
import '../../routes/app_routes.dart';
import './widgets/feed_empty_state_widget.dart';
import './widgets/feed_top_bar_widget.dart';
import './widgets/im_good_today_orb_widget.dart';
import './widgets/daily_checkin_card_widget.dart';
import './widgets/daily_meds_card_widget.dart';
import './widgets/legacy_prompt_card_widget.dart';
import './widgets/meds_reminder_card_widget.dart';
import './widgets/message_card_widget.dart';
import './widgets/celebrations_card_widget.dart';
import './widgets/nest_avatar_row_widget.dart';
import '../profile_photo_picker_screen/profile_photo_picker_screen.dart';
import '../../core/app_state.dart';

// ── Data Models ────────────────────────────────────────────────

enum MessageType { text, photo, video, voice }

class MessageModel {
  MessageModel({
    required this.id,
    this.authorId = '',
    required this.senderName,
    required this.senderRelationship,
    this.senderRole = 'family',
    required this.senderAvatarUrl,
    required this.senderAvatarLabel,
    this.senderAvatarJson,
    required this.type,
    required this.content,
    required this.imageUrl,
    required this.imageSemanticLabel,
    required this.timestamp,
    required this.heartCount,
    required this.isHearted,
    this.isSample = false,
    this.isRecordedVideo = false,
    this.recipientLabel = 'Everyone in the Nest',
    this.pinnedPosition,
  });

  final String id;
  // Needed to decide whether the current user can delete this post (their
  // own posts, or -- for a nest owner -- a post from someone they've
  // removed). Defaults to empty for older cached entries written before
  // this field existed; those simply won't show a delete option until the
  // cache refreshes from Supabase.
  final String authorId;
  final String senderName;
  final String senderRelationship;
  final String senderRole;
  final String senderAvatarUrl;
  final String senderAvatarLabel;
  final String? senderAvatarJson;
  final MessageType type;
  final String content;
  final String imageUrl;
  final String imageSemanticLabel;
  final DateTime timestamp;
  int heartCount;
  bool isHearted;
  final bool isSample; // true for demo/sample cards shown before real posts exist
  // Only relevant when type is video: whether this came from this app's own
  // live front-camera recording (needs the mirror correction) vs an
  // uploaded/picked video (never needs it).
  final bool isRecordedVideo;
  // Who this post is actually addressed to -- resolved from the real
  // visible_to_ids saved at send time. Previously that field was saved to
  // Supabase but never read back anywhere, so every card showed the same
  // generic default no matter who was actually selected.
  final String recipientLabel;
  // Which pin slot (1, 2, or 3) this post occupies, or null if not pinned.
  // Owner-chosen per post -- see the pin picker in message_card_widget.dart.
  // Mutable (not final) so the feed can update it in place after a pin/
  // unpin action instead of needing a full reload.
  int? pinnedPosition;

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'] as String,
      authorId: map['authorId'] as String? ?? '',
      senderName: map['senderName'] as String,
      senderRelationship: map['senderRelationship'] as String,
      senderRole: map['senderRole'] as String? ?? 'family',
      senderAvatarUrl: map['senderAvatarUrl'] as String,
      senderAvatarLabel: map['senderAvatarLabel'] as String,
      type: _messageTypeFromString(map['type'] as String),
      content: map['content'] as String,
      imageUrl: map['imageUrl'] as String,
      imageSemanticLabel: map['imageSemanticLabel'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      heartCount: map['heartCount'] as int,
      isHearted: map['isHearted'] as bool,
      isSample: map['isSample'] as bool? ?? false,
      isRecordedVideo: map['isRecordedVideo'] as bool? ?? false,
      recipientLabel: map['recipientLabel'] as String? ?? 'Everyone in the Nest',
      pinnedPosition: map['pinnedPosition'] as int?,
    );
  }

  static MessageType _messageTypeFromString(String v) {
    switch (v) {
      case 'photo':
        return MessageType.photo;
      case 'video':
        return MessageType.video;
      case 'voice':
        return MessageType.voice;
      default:
        return MessageType.text;
    }
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'authorId': authorId,
    'senderName': senderName,
    'senderRelationship': senderRelationship,
    'senderRole': senderRole,
    'senderAvatarUrl': senderAvatarUrl,
    'senderAvatarLabel': senderAvatarLabel,
    'type': type.name,
    'content': content,
    'imageUrl': imageUrl,
    'imageSemanticLabel': imageSemanticLabel,
    'timestamp': timestamp.toIso8601String(),
    'heartCount': heartCount,
    'isHearted': isHearted,
    'isSample': isSample,
    'isRecordedVideo': isRecordedVideo,
    'recipientLabel': recipientLabel,
    'pinnedPosition': pinnedPosition,
  };
}

// ── Screen ─────────────────────────────────────────────────────

class FamilyFeedScreen extends StatefulWidget {
  const FamilyFeedScreen({super.key});

  @override
  State<FamilyFeedScreen> createState() => _FamilyFeedScreenState();
}

class _FamilyFeedScreenState extends State<FamilyFeedScreen>
    with TickerProviderStateMixin {
  // TODO: Replace with Riverpod/Bloc for production — feed state, user state
  int _currentNavIndex = 0;
  bool _isSenior = appIsSeniorNotifier.value;
  String _displayName = appDisplayNameNotifier.value;
  // Seeded from the already-resolved app-wide notifier instead of an
  // empty default -- see appNestNameNotifier in app_state.dart. Once
  // someone has named their nest, this is correct on the very first
  // build, before any async work even starts, so nothing below it (the
  // "My Nest" placeholder) is ever visible, regardless of connection
  // speed.
  String _nestName = appNestNameNotifier.value;
  bool _isGoodTodaySent = appIsGoodTodaySentNotifier.value;
  bool _justCheckedIn = false; // true only briefly right after tapping, to show the "Sent!" confirmation
  bool _showMedsReminder = true;
  bool _showWelcomeToast = false;
  bool _isLoading = true;
  // Seeded from the already-resolved app-wide notifier instead of a
  // hardcoded false -- see messages_inbox_screen.dart for the full
  // explanation of the white-flash bug this fixes. This screen matters
  // most of all here, since it's Home -- the screen every tab switch
  // lands back on.
  bool _isDarkMode = appDarkModeNotifier.value;
  bool _hasRealPost = appHasRealPostNotifier.value; // tracks if user has made their first real post
  String _seniorName = appSeniorNameNotifier.value; // display name of the senior in this nest (for the pinned check-in card)
  String _seniorUserId = '';
  bool _seniorCheckedInToday = appSeniorCheckedInTodayNotifier.value;
  DateTime? _seniorCheckinTime;
  bool _seniorMedsTakenToday = appSeniorMedsTakenTodayNotifier.value;
  DateTime? _seniorMedsTakenTime;
  bool _inviteCodeShared =
      true; // tracks if family owner has shared invite code
  bool _isGuest = appIsGuestNotifier.value;
  bool _isNestOwner = appIsNestOwnerNotifier.value;
  // Author IDs of anyone removed from this nest -- used only to gate the
  // post-delete icon for the nest owner (delete a removed member's post).
  // Not critical-path, so a plain fetch after the main load is enough;
  // doesn't need the cache-first treatment the rest of this screen uses.
  Set<String> _removedMemberIds = {};
  List<CelebrationEvent> _todayCelebrations = [];
  List<CelebrationEvent> _upcomingCelebrations = [];
  List<Map<String, dynamic>> _nestMembers = []; // for avatar row (excludes current user)

  late AnimationController _listEntranceController;
  bool _hasPlayedEntranceOnce = false;

  // Every nav tap on the bottom bar uses pushReplacementNamed, which builds
  // a brand new FamilyFeedScreen + State each time -- so an ordinary
  // instance field can't remember "already animated" across visits. This
  // has to be static (lives for the whole app process) so the avatar row
  // and check-in card only ever pop in with their fade+lift once per
  // session, instead of empty-then-fade-in-and-shove-everything-down on
  // every single visit to Home, which is what read as "twitchy."
  static bool _topCardsAnimatedOnceThisSession = false;
  final List<Animation<double>> _itemAnimations = [];
  final ScrollController _scrollController = ScrollController();
  // Aug 21 2026: collapsible year/month grouping -- which groups are
  // currently collapsed, keyed 'year-2026' / 'month-2026-8'. In-memory
  // only (not persisted), so it resets to fully-expanded each fresh
  // session, matching how collapse state works elsewhere in the app
  // (e.g. Setup's expandable sections).
  final Set<String> _collapsedGroupKeys = {};

  // ── Mock Data Maps ─────────────────────────────────────────────
  static final List<Map<String, dynamic>> _messageMaps = [
    {
      'id': 'msg_001',
      'senderName': 'Sarah',
      'senderRelationship': 'Daughter',
      'senderAvatarUrl':
          'https://images.unsplash.com/photo-1707362257505-184cd67f1855',
      'senderAvatarLabel':
          'Smiling woman with brown hair in casual blue top, outdoors',
      'type': 'photo',
      'content':
          "Look at little Theo's first steps today! He kept running to the dog.",
      'imageUrl':
          'https://images.unsplash.com/photo-1707362257505-184cd67f1855',
      'imageSemanticLabel':
          'Happy toddler in striped shirt taking first steps on green grass, golden afternoon light',
      'timestamp': '2026-03-24T14:32:00.000Z',
      'heartCount': 4,
      'isHearted': true,
      'isSample': true,
    },
    {
      'id': 'msg_002',
      'senderName': 'Michael',
      'senderRelationship': 'Son',
      'senderAvatarUrl':
          'https://images.unsplash.com/photo-1735181094336-7fa757df9622',
      'senderAvatarLabel':
          'Middle-aged man with short dark hair smiling, light background',
      'type': 'text',
      'content':
          "Morning, Mom! Thinking of you today. We're coming over Sunday - I'll bring your favorite blueberry muffins.",
      'imageUrl': '',
      'imageSemanticLabel': '',
      'timestamp': '2026-03-24T09:15:00.000Z',
      'heartCount': 2,
      'isHearted': false,
      'isSample': true,
    },
    {
      'id': 'msg_003',
      'senderName': 'Priya',
      'senderRelationship': 'Granddaughter',
      'senderAvatarUrl':
          'https://img.rocket.new/generatedImages/rocket_gen_img_115ec4756-1776378820432.png',
      'senderAvatarLabel':
          'Young woman with long dark hair and bright smile, warm background',
      'type': 'voice',
      'content': 'Voice message - 0:28',
      'imageUrl': '',
      'imageSemanticLabel': '',
      'timestamp': '2026-03-23T20:44:00.000Z',
      'heartCount': 1,
      'isHearted': false,
      'isSample': true,
    },
    {
      'id': 'msg_004',
      'senderName': 'David',
      'senderRelationship': 'Grandson',
      'senderAvatarUrl':
          'https://images.unsplash.com/photo-1627646580365-35950e51cd95',
      'senderAvatarLabel':
          'Young man with curly hair and glasses smiling in casual wear',
      'type': 'photo',
      'content':
          'Scored my first goal of the season! Wish you were there, Grandma.',
      'imageUrl':
          'https://images.unsplash.com/photo-1627646580365-35950e51cd95',
      'imageSemanticLabel':
          'Soccer field at sunset with green grass and white goal posts, warm orange sky',
      'timestamp': '2026-03-23T17:10:00.000Z',
      'heartCount': 6,
      'isHearted': true,
      'isSample': true,
    },
    {
      'id': 'msg_005',
      'senderName': 'Sarah',
      'senderRelationship': 'Daughter',
      'senderAvatarUrl':
          'https://images.unsplash.com/photo-1660316496604-66f6bc1dd9ef',
      'senderAvatarLabel':
          'Smiling woman with brown hair in casual blue top, outdoors',
      'type': 'text',
      'content':
          "Don't forget to take your evening vitamins tonight, Mom! Set a reminder if you need. Love you lots.",
      'imageUrl': '',
      'imageSemanticLabel': '',
      'timestamp': '2026-03-22T19:05:00.000Z',
      'heartCount': 3,
      'isHearted': false,
      'isSample': true,
    },
  ];

  List<MessageModel> _messages = [];
  Set<String> _bookmarkedIds = {};
  // Aug 27 2026: real-time feed updates -- see initState/_subscribeToFeedRealtime.
  RealtimeChannel? _feedChannel;
  Timer? _realtimeRefreshDebounce;

  @override
  void initState() {
    super.initState();
    _listEntranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _loadData();
    _loadRemovedMemberIds();
    _subscribeToFeedRealtime();
    _checkPendingSuccessionForOwner();
  }

  // Aug 28 2026: D Von's direct ask -- the Nest Ownership section in
  // Setup works correctly, but an owner who's slowing down or getting
  // sicker might not think to go looking for it. This surfaces a request
  // right on Home, the very first screen they see, instead of leaving it
  // buried in a settings page they'd have to know to check. Deliberately
  // re-checks ownership independently here rather than trusting
  // _isNestOwner's timing, since that field updates asynchronously
  // elsewhere and this needs to be correct the moment it runs.
  Future<void> _checkPendingSuccessionForOwner() async {
    try {
      final supabase = Supabase.instance.client;
      final myUserId = supabase.auth.currentUser?.id;
      if (myUserId == null) return;
      final prefs = await SharedPreferences.getInstance();
      final nestId = prefs.getString('nest_id') ?? '';
      if (nestId.isEmpty) return;

      final nest = await supabase
          .from('nests')
          .select('created_by')
          .eq('id', nestId)
          .maybeSingle();
      if (nest?['created_by'] != myUserId) return;

      final pending = await supabase
          .from('nest_succession_requests')
          .select('id, requested_by')
          .eq('nest_id', nestId)
          .eq('status', 'pending')
          .maybeSingle();
      if (pending == null) return;

      final requesterId = pending['requested_by'] as String;
      final rp = await supabase
          .from('user_profiles')
          .select('display_name, preferred_name')
          .eq('id', requesterId)
          .maybeSingle();
      final preferred = (rp?['preferred_name'] as String?) ?? '';
      final display = (rp?['display_name'] as String?) ?? '';
      final requesterName = preferred.isNotEmpty
          ? preferred
          : (display.isNotEmpty ? display : 'A family member');

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showSuccessionRequestPopup(requesterName);
        });
      }
    } catch (e) {
      debugPrint('SUCCESSION_HOME_CHECK_ERROR: $e');
    }
  }

  void _showSuccessionRequestPopup(String requesterName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _isDarkMode ? const Color(0xFF242018) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '$requesterName wants to become Nest Owner',
          style: GoogleFonts.nunitoSans(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: _isDarkMode ? const Color(0xFFF5F0E8) : const Color(0xFF2C2417),
          ),
        ),
        content: Text(
          'You can approve or deny this in Setup. If you don\'t respond, other family members can still weigh in, and it won\'t happen without everyone being able to see it.',
          style: GoogleFonts.nunitoSans(
            fontSize: 15,
            color: _isDarkMode ? const Color(0xFFB8AC98) : const Color(0xFF6B5E4E),
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Later',
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                color: _isDarkMode ? const Color(0xFFB8AC98) : const Color(0xFF6B5E4E),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, AppRoutes.setupScreen);
            },
            child: Text(
              'View Request',
              style: GoogleFonts.nunitoSans(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF5DA399)),
            ),
          ),
        ],
      ),
    );
  }

  // Aug 27 2026: pre-ship backlog item -- new posts/edits/deletes now show
  // up live without a manual refresh. Deliberately NOT hand-patching
  // _messages incrementally per INSERT/UPDATE/DELETE event (real risk of
  // subtly diverging from the proven-correct mapping/pin-ordering/dedup
  // logic already in _loadFeedFromSupabase). Instead: any change on this
  // nest's feed_posts triggers a debounced re-run of that same,
  // already-correct fetch -- slightly more network traffic than a hand-
  // rolled patch, but far lower risk of a new, subtle feed bug. Debounced
  // 400ms so a burst of changes (e.g. someone editing then immediately
  // pinning a post) doesn't trigger several overlapping refetches.
  Future<void> _subscribeToFeedRealtime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nestId = prefs.getString('nest_id') ?? '';
      if (nestId.isEmpty || !mounted) return;

      _feedChannel = Supabase.instance.client
          .channel('feed_posts_realtime_$nestId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'feed_posts',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'nest_id',
              value: nestId,
            ),
            callback: (payload) {
              _realtimeRefreshDebounce?.cancel();
              _realtimeRefreshDebounce = Timer(const Duration(milliseconds: 400), () {
                if (mounted) _loadFeedFromSupabase();
              });
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('FEED_REALTIME: subscribe failed, feed still works via manual refresh: $e');
    }
  }

  Future<void> _loadRemovedMemberIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nestId = prefs.getString('nest_id') ?? '';
      if (nestId.isEmpty) return;
      final rows = await Supabase.instance.client
          .from('nest_removed_members')
          .select('user_id')
          .eq('nest_id', nestId);
      final ids = (rows as List<dynamic>)
          .map((r) => r['user_id'] as String?)
          .whereType<String>()
          .toSet();
      if (mounted) {
        setState(() => _removedMemberIds = ids);
      }
    } catch (e) {
      debugPrint('REMOVED_MEMBER_IDS_LOAD_ERROR: $e');
    }
  }

  // Own posts, or -- for the nest owner -- a post from someone they've
  // removed. Matches the RLS policies exactly (delete_own_post,
  // owner_delete_removed_members_post), so this only ever controls whether
  // the icon shows; RLS is still the real enforcement.
  bool _canDeletePost(MessageModel msg) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null || msg.authorId.isEmpty) return false;
    if (msg.authorId == currentUserId) return true;
    return _isNestOwner && _removedMemberIds.contains(msg.authorId);
  }

  // Nest owner's OWN posts only -- never another member's, even though the
  // actor is the owner. Matches the owner_pin_own_post RLS policy exactly,
  // same relationship this already has to _canDeletePost above (this
  // controls whether the control shows; RLS is the real enforcement).
  bool _canPinPost(MessageModel msg) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null || msg.authorId.isEmpty) return false;
    return _isNestOwner && msg.authorId == currentUserId;
  }

  // Slots (1/2/3) currently occupied by ANY of the owner's pinned posts --
  // used to build the picker's available-slots list, and to decide whether
  // to show "max 3 pinned" instead of a picker at all.
  Set<int> get _occupiedPinSlots => _messages
      .map((m) => m.pinnedPosition)
      .whereType<int>()
      .toSet();

  // Sets or changes a post's pin slot, or clears it (slot: null to unpin).
  // A single-row UPDATE is enough -- no other row is ever touched, since
  // the picker only ever offers slots that are already free (D Von's
  // explicit direction: no automatic bumping of whatever's already in a
  // slot). The partial unique index on (nest_id, pinned_position) is the
  // real backstop against two posts ending up in the same slot regardless.
  Future<void> _setPinSlot(MessageModel msg, int? slot) async {
    final previousSlot = msg.pinnedPosition;
    setState(() {
      msg.pinnedPosition = slot;
      _messages.sort(_pinnedThenRecencyComparator);
    });
    try {
      await Supabase.instance.client
          .from('feed_posts')
          .update({'pinned_position': slot})
          .eq('id', msg.id);
      await _syncPinnedPositionToCache(msg.id, slot);
    } catch (e) {
      debugPrint('SET_PIN_SLOT_ERROR: $e');
      if (mounted) {
        setState(() {
          msg.pinnedPosition = previousSlot;
          _messages.sort(_pinnedThenRecencyComparator);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't update pin -- try again.")),
        );
      }
    }
  }

  // Same ordering the Supabase query already applies server-side (pinned
  // slots first in slot order, then everything else by recency) -- needed
  // here too since _setPinSlot updates the in-memory list without a full
  // reload, matching the same cache-in-sync pattern _syncDeletedPostToCache
  // already established for deletes.
  int _pinnedThenRecencyComparator(MessageModel a, MessageModel b) {
    final aPin = a.pinnedPosition;
    final bPin = b.pinnedPosition;
    if (aPin != null && bPin != null) return aPin.compareTo(bPin);
    if (aPin != null) return -1;
    if (bPin != null) return 1;
    return b.timestamp.compareTo(a.timestamp);
  }

  Future<void> _syncPinnedPositionToCache(String messageId, int? slot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('cached_real_messages');
      if (cachedJson == null) return;
      final List<dynamic> cachedList = jsonDecode(cachedJson) as List<dynamic>;
      for (final m in cachedList) {
        final map = m as Map<String, dynamic>;
        if (map['id'] == messageId) {
          map['pinnedPosition'] = slot;
          break;
        }
      }
      await prefs.setString('cached_real_messages', jsonEncode(cachedList));
    } catch (e) {
      debugPrint('PIN_CACHE_SYNC_ERROR: $e');
    }
  }

  void _deletePost(String messageId) {
    setState(() {
      _messages.removeWhere((m) => m.id == messageId);
    });
    // The DB delete already succeeded (that's what got us here) but this
    // only updated the in-memory list -- the persisted cache_first cache
    // (cached_real_messages) still had the deleted post in it. Navigating
    // away and back re-triggers _loadData(), which reads that stale cache
    // FIRST for instant display, before the live Supabase fetch corrects
    // it -- meaning the deleted post reappeared, at least briefly, exactly
    // what D Von found (build 175, Aug 16 2026). Keep the cache in sync
    // immediately so this can't happen.
    _syncDeletedPostToCache(messageId);
  }

  Future<void> _syncDeletedPostToCache(String messageId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('cached_real_messages');
      if (cachedJson == null) return;
      final List<dynamic> cachedList = jsonDecode(cachedJson) as List<dynamic>;
      cachedList.removeWhere(
        (m) => (m as Map<String, dynamic>)['id'] == messageId,
      );
      await prefs.setString('cached_real_messages', jsonEncode(cachedList));
    } catch (e) {
      debugPrint('DELETE_POST_CACHE_SYNC_ERROR: $e');
    }
  }

  Future<void> _ensureNestId() async {
    final prefs = await SharedPreferences.getInstance();
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final existingNestId = prefs.getString('nest_id') ?? '';

    // nest_id is deliberately excluded from the account-switch wipe in
    // auth_service.dart (it's set during onboarding, before sign-in
    // completes) -- but that means a STALE nest_id left over from a
    // previously signed-in account on this device can still be sitting
    // here when a different account signs in. This function used to
    // treat ANY non-empty value as good enough and do nothing further --
    // confirmed root cause of check-in status "resetting" after switching
    // accounts and coming back same-day: every check-in read was silently
    // scoped to the WRONG nest because this early-returned without ever
    // checking whether the cached id actually belongs to this user.
    if (existingNestId.isNotEmpty) {
      try {
        final membership = await supabase
            .from('nest_members')
            .select('nest_id')
            .eq('nest_id', existingNestId)
            .eq('user_id', userId)
            .maybeSingle();
        if (membership != null) return; // still valid, nothing to do
      } catch (e) {
        print('NEST_ID VALIDATION ERROR: $e');
        // Fail open on a network error -- don't discard a possibly-correct
        // cached id just because we couldn't reach the server to confirm it.
        return;
      }
      // Cached id didn't validate -- fall through and look up the real one.
    }

    try {
      final owned = await supabase
          .from('nests')
          .select('id')
          .eq('created_by', userId)
          .maybeSingle();

      if (owned != null) {
        final nestId = owned['id'] as String;
        await prefs.setString('nest_id', nestId);
        print('NEST_ID: saved (owner) = $nestId');
        return;
      }

      // Not an owner -- this account is a family member, look up their
      // actual membership directly instead of leaving nest_id unset.
      final membership = await supabase
          .from('nest_members')
          .select('nest_id')
          .eq('user_id', userId)
          .maybeSingle();

      if (membership != null) {
        final nestId = membership['nest_id'] as String;
        await prefs.setString('nest_id', nestId);
        print('NEST_ID: saved (member) = $nestId');
      }
    } catch (e) {
      print('NEST_ID ERROR: $e');
    }
  }

  Future<void> _loadData() async {
    // Fetch and save nest_id from Supabase if not already saved
    await _ensureNestId();
    // TODO: Replace with Supabase realtime subscription for production
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? 'senior';
    final firstName = prefs.getString('display_name') ?? '';
    final preferredNameVal = prefs.getString('preferred_name') ?? '';
    final name = preferredNameVal.isNotEmpty ? preferredNameVal : firstName;
    // Nest name was previously local-storage-only, so a rename made on one
    // flow/device (e.g. senior onboarding) was invisible on every other
    // flow sharing the same nest (e.g. a family member's own device).
    // Now sourced live from Supabase, with local cache as fallback.
    String nestName = prefs.getString('nest_name') ?? '';
    // _nestName is now seeded synchronously from appNestNameNotifier at
    // field declaration (see the comment there), so it's already correct
    // from the very first build -- no early setState needed here anymore.
    try {
      final nestIdForName = prefs.getString('nest_id') ?? '';
      if (nestIdForName.isNotEmpty) {
        final nestRow = await Supabase.instance.client
            .from('nests')
            .select('name')
            .eq('id', nestIdForName)
            .maybeSingle();
        final remoteName = nestRow?['name'] as String?;
        if (remoteName != null && remoteName.isNotEmpty) {
          nestName = remoteName;
          await prefs.setString('nest_name', remoteName);
          // Keep the shared notifier in sync too, so every other screen
          // that reads it (Setup, and any future screen) picks up a real
          // rename immediately, not just this one.
          appNestNameNotifier.value = remoteName;
        }
      }
    } catch (e) {
      print('NEST_NAME_LOAD_ERROR: $e');
    }
    final goodToday = prefs.getBool('good_today_${_todayKey()}') ?? false;
    final medsReminder = prefs.getBool('meds_reminder_${_todayKey()}') ?? true;
    final firstLoad = prefs.getBool('first_load') ?? true;
    final darkMode = prefs.getBool('dark_mode') ?? false;
    final hasRealPost = prefs.getBool('has_real_post') ?? false;
    final inviteCodeShared = prefs.getBool('invite_code_shared') ?? false;
    final isGuest = prefs.getBool('is_guest') ?? false;

    if (firstLoad) {
      await prefs.setBool('first_load', false);
    }

    // Load celebrations -- nest-wide: every member's birthday/anniversary
    // (if they've set one) shows on EVERYONE's Home feed, including their
    // own, once it's within 30 days. Previously this only ever read the
    // current device's local cache, so it only ever surfaced one person's
    // dates and mislabeled them with whoever happened to be signed in on
    // this device at the time.
    final today = DateTime.now();
    final todayEvents = <CelebrationEvent>[];
    final upcomingEvents = <CelebrationEvent>[];
    final monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    void checkMemberEvent(
      DateTime? date,
      CelebrationEventType type,
      String memberName,
      String? memberAvatarJson,
    ) {
      if (date == null) return;
      final todayDate = DateTime(today.year, today.month, today.day);
      final thisYear = DateTime(today.year, date.month, date.day);
      final nextYear = DateTime(today.year + 1, date.month, date.day);
      final candidate = thisYear.isBefore(todayDate) ? nextYear : thisYear;
      final diff = candidate.difference(todayDate).inDays;
      final dateLabel = '${monthNames[candidate.month - 1]} ${candidate.day}';
      if (diff == 0) {
        todayEvents.add(
          CelebrationEvent(
            name: memberName,
            type: type,
            dateLabel: dateLabel,
            daysUntil: 0,
            avatarJson: memberAvatarJson,
          ),
        );
      } else if (diff > 0 && diff <= 30) {
        upcomingEvents.add(
          CelebrationEvent(
            name: memberName,
            type: type,
            dateLabel: dateLabel,
            daysUntil: diff,
            avatarJson: memberAvatarJson,
          ),
        );
      }
    }

    try {
      final supabase = Supabase.instance.client;
      final celebrationsNestId = prefs.getString('nest_id') ?? '';
      if (celebrationsNestId.isNotEmpty) {
        final memberRows = await supabase
            .from('nest_members')
            .select(
                'user_profiles(display_name, preferred_name, birthday, anniversary, avatar_url)')
            .eq('nest_id', celebrationsNestId);
        for (final row in (memberRows as List<dynamic>)) {
          final memberProfile = row['user_profiles'] as Map<String, dynamic>?;
          if (memberProfile == null) continue;
          final memberPreferred = memberProfile['preferred_name'] as String? ?? '';
          final memberDisplay = memberProfile['display_name'] as String? ?? '';
          final memberName = memberPreferred.isNotEmpty
              ? memberPreferred
              : (memberDisplay.isNotEmpty ? memberDisplay : 'A family member');
          final memberAvatarJson = memberProfile['avatar_url'] as String?;
          DateTime? memberBirthday;
          DateTime? memberAnniversary;
          final birthdayField = memberProfile['birthday'] as String?;
          final anniversaryField = memberProfile['anniversary'] as String?;
          if (birthdayField != null) {
            try {
              memberBirthday = DateTime.parse(birthdayField);
            } catch (_) {}
          }
          if (anniversaryField != null) {
            try {
              memberAnniversary = DateTime.parse(anniversaryField);
            } catch (_) {}
          }
          checkMemberEvent(memberBirthday, CelebrationEventType.birthday, memberName, memberAvatarJson);
          checkMemberEvent(memberAnniversary, CelebrationEventType.anniversary, memberName, memberAvatarJson);
        }
      }
    } catch (e) {
      print('CELEBRATIONS LOAD ERROR: $e');
    }

    upcomingEvents.sort((a, b) => a.daysUntil.compareTo(b.daysUntil));

    // Prefer real cached messages over generic demo placeholders — avoids
    // showing mismatched content that then flashes/swaps once the network loads.
    final _currentNestIdForCache = prefs.getString('nest_id') ?? '';
    final _cachedNestId = prefs.getString('cached_real_messages_nest_id') ?? '';
    final cachedMessagesJson = (_cachedNestId.isNotEmpty && _cachedNestId == _currentNestIdForCache)
        ? prefs.getString('cached_real_messages')
        : null;
    List<MessageModel> initialMessages;
    if (cachedMessagesJson != null && cachedMessagesJson.isNotEmpty) {
      try {
        final List<dynamic> cachedList = jsonDecode(cachedMessagesJson) as List<dynamic>;
        initialMessages = cachedList
            .map((m) => MessageModel.fromMap(m as Map<String, dynamic>))
            .toList();
      } catch (_) {
        initialMessages = hasRealPost ? [] : _messageMaps.map(MessageModel.fromMap).toList();
      }
    } else {
      initialMessages = hasRealPost ? [] : _messageMaps.map(MessageModel.fromMap).toList();
    }

    // Same cache-first pattern as messages -- avoid showing an empty
    // avatar row / check-in card on every visit while the live Supabase
    // queries are still in flight, which is what made them visibly "pop
    // in last" even with a zero-duration animation. Local prefs reads are
    // fast enough to paint alongside the rest of Home's first frame,
    // unlike a real network round-trip.
    //
    // Cache key includes the current user's own id, not just the nest --
    // the "other members" list always excludes whoever's currently
    // viewing it, so it's a genuinely different list depending on who
    // that is, even for the exact same nest. Without the user id in the
    // key, switching between accounts on the same nest/device (D Von's
    // normal testing pattern) briefly showed the PREVIOUS viewer's cached
    // list -- which could include the CURRENT viewer's own avatar, since
    // it was built to exclude someone else.
    final currentUserIdForCache = Supabase.instance.client.auth.currentUser?.id ?? '';
    final cachedMembersNestId = prefs.getString('cached_nest_members_nest_id') ?? '';
    final cachedMembersUserId = prefs.getString('cached_nest_members_user_id') ?? '';
    List<Map<String, dynamic>> initialNestMembers = [];
    if (cachedMembersNestId.isNotEmpty &&
        cachedMembersNestId == _currentNestIdForCache &&
        cachedMembersUserId.isNotEmpty &&
        cachedMembersUserId == currentUserIdForCache) {
      final cachedMembersJson = prefs.getString('cached_nest_members');
      if (cachedMembersJson != null && cachedMembersJson.isNotEmpty) {
        try {
          final List<dynamic> cachedList = jsonDecode(cachedMembersJson) as List<dynamic>;
          initialNestMembers = cachedList
              .map((m) => Map<String, dynamic>.from(m as Map))
              .toList();
        } catch (_) {}
      }
    }

    final cachedCheckinNestId = prefs.getString('cached_checkin_nest_id') ?? '';
    final cachedCheckinDate = prefs.getString('cached_checkin_date') ?? '';
    String initialSeniorUserId = '';
    String initialSeniorName = '';
    bool initialSeniorCheckedIn = false;
    DateTime? initialSeniorCheckinTime;
    bool initialSeniorMedsTaken = false;
    DateTime? initialSeniorMedsTakenTime;
    if (cachedCheckinNestId.isNotEmpty &&
        cachedCheckinNestId == _currentNestIdForCache &&
        cachedCheckinDate == _todayDateString()) {
      initialSeniorUserId = prefs.getString('cached_checkin_senior_id') ?? '';
      initialSeniorName = prefs.getString('cached_checkin_senior_name') ?? '';
      initialSeniorCheckedIn = prefs.getBool('cached_checkin_checked_in') ?? false;
      final cachedTimeStr = prefs.getString('cached_checkin_time');
      initialSeniorCheckinTime =
          cachedTimeStr != null ? DateTime.tryParse(cachedTimeStr) : null;
      initialSeniorMedsTaken = prefs.getBool('cached_checkin_meds_taken') ?? false;
      final cachedMedsTimeStr = prefs.getString('cached_checkin_meds_time');
      initialSeniorMedsTakenTime =
          cachedMedsTimeStr != null ? DateTime.tryParse(cachedMedsTimeStr) : null;
    }

    setState(() {
      _isSenior = role == 'senior';
      _displayName = name;
      _nestName = nestName;
      _isGoodTodaySent = goodToday;
      _showMedsReminder = medsReminder;
      _showWelcomeToast = firstLoad;
      _isDarkMode = darkMode;
      _hasRealPost = hasRealPost;
      _inviteCodeShared = inviteCodeShared;
      _isGuest = isGuest;
      // Aug 19 2026: this used to be reset to !joinedViaInvite here, right
      // after being correctly initialized from appIsNestOwnerNotifier.value
      // at declaration (line 181) -- appIsNestOwnerNotifier is resolved once
      // at cold start in main.dart from the best available source (a prior
      // session's confirmed value if one exists, that same joined-via-invite
      // proxy only as a genuine first-ever fallback). Overwriting it here
      // with the raw proxy on every load undid that for Home specifically,
      // silently reintroducing the "ownership must come from Supabase, not
      // a local flag" bug in exactly the screen the pin feature's owner
      // check depends on. Removed the overwrite here. Aug 25 2026 update:
      // _isNestOwner was still declared `final`, so even though the raw
      // proxy overwrite was gone, a wrong best-guess at construction time
      // could never self-correct for the rest of the screen's life --
      // exactly what caused pin icons to vanish for a confirmed real nest
      // owner (D Von's screenshots, Aug 25). Now a real mutable field,
      // corrected by a genuine live Supabase check further down (see
      // "_isNestOwner used to be declared final" below).
      _messages = initialMessages;
      _isLoading = false;
      _todayCelebrations = todayEvents;
      _upcomingCelebrations = upcomingEvents;
      if (initialNestMembers.isNotEmpty) {
        _nestMembers = initialNestMembers;
      }
      if (initialSeniorUserId.isNotEmpty) {
        _seniorUserId = initialSeniorUserId;
        _seniorName = initialSeniorName;
        _seniorCheckedInToday = initialSeniorCheckedIn;
        _seniorCheckinTime = initialSeniorCheckinTime;
        _seniorMedsTakenToday = initialSeniorMedsTaken;
        _seniorMedsTakenTime = initialSeniorMedsTakenTime;
      }
    });
    // Aug 28 2026: D Von's direct, specific report -- Home was the only
    // one of the six tabs where content didn't come in smoothly; every
    // other tab loads its whole screen instantly with no visible
    // rebuild, so the bigger tab-architecture item on the backlog isn't
    // actually needed for those. This is a narrower, real bug specific
    // to Home's very first paint: _setupItemAnimations()/.forward() used
    // to run only after a SEPARATE network round-trip further down (the
    // live nest-owner check), even though _isLoading had already flipped
    // false and the real content was already rendering right here.
    // Rendered items fall back to AlwaysStoppedAnimation(1.0) (full
    // opacity, no animation) whenever _itemAnimations is still empty --
    // so content appeared instantly, fully visible, the moment this
    // setState ran. Then, a moment later, once that unrelated network
    // call finally finished, the real animation objects were built for
    // the first time and .forward() ran on them -- snapping the same,
    // already-visible content back down and re-animating it in, which is
    // exactly what would read as "doesn't smoothly come in." Starting
    // the entrance animation here, the instant real content exists,
    // means there's only ever one entrance, not two. The nest-owner
    // check below is unrelated correctness logic and doesn't need to
    // gate this at all -- it keeps running the same as before, just no
    // longer in the way.
    _setupItemAnimations();
    _listEntranceController.forward();
    _hasPlayedEntranceOnce = true;
    // appIsSeniorNotifier is only resolved once at true cold-start/resume
    // (main.dart) -- switching accounts within one running session (sign
    // out, sign into a different account, no full app relaunch) never hit
    // that resolution point again, so the notifier stayed stuck on
    // whoever was last resolved. That's exactly why a family member could
    // briefly see the senior-only "I'm Good" button after an account
    // switch (reported by D Von, build 172). This is the fresh, correct
    // value for whoever is actually logged in right now -- write it back
    // so every other screen reading this notifier corrects immediately
    // too, not just this one.
    appIsSeniorNotifier.value = role == 'senior';
    appDisplayNameNotifier.value = name;
    if (initialSeniorUserId.isNotEmpty) {
      appSeniorNameNotifier.value = initialSeniorName;
    }

    // Aug 25 2026: _isNestOwner used to be declared `final` here -- set
    // once at construction from appIsNestOwnerNotifier.value and then
    // permanently frozen for the rest of this screen's lifetime, unlike
    // every other identity field on every other screen, all of which get
    // corrected by a live check shortly after load. If the notifier's
    // best-guess value at the moment Home first built happened to be
    // wrong, the real nest owner's own pin controls (canPin, line ~370)
    // would vanish for the whole session with no way to self-correct --
    // exactly what D Von's screenshots showed for Popy, a confirmed real
    // nest owner (Setup screen: "Popy -- Nest Owner"), whose own posts
    // showed the pinned border correctly but never the pin icon itself.
    // Unlike Setup/Safety, Home can plausibly be the very first screen a
    // brand-new nest owner ever sees, before cached_is_nest_owner has
    // ever been written (that key is only ever set by setup_screen.dart)
    // -- so this needs a genuine live check here, not just "prefer the
    // cache," since there may be no cache yet to prefer.
    try {
      final currentAuthUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentAuthUserId != null) {
        final ownedNest = await Supabase.instance.client
            .from('nests')
            .select('id')
            .eq('created_by', currentAuthUserId)
            .maybeSingle();
        final confirmedIsNestOwner = ownedNest != null;
        if (mounted) {
          setState(() => _isNestOwner = confirmedIsNestOwner);
        }
        appIsNestOwnerNotifier.value = confirmedIsNestOwner;
        await prefs.setBool('cached_is_nest_owner', confirmedIsNestOwner);
      }
    } catch (_) {
      // Network error -- leave whatever value _isNestOwner already has
      // (the notifier's best guess) rather than risk overwriting a
      // possibly-correct value with a wrong one on a failed check.
    }

    // _setupItemAnimations()/.forward() now run right after content
    // first becomes visible, above -- see the Aug 28 2026 note there.
    // Calling them again here would restart an already-playing (or
    // already-finished) animation, undoing the actual fix.

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });

    if (_showWelcomeToast && mounted) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        _showWelcomeMessage();
      }
    }

    // These four loads are independent of each other, so run them
    // concurrently. Previously they ran in sequence (bookmarks ran alone,
    // separately, before this block even started), which made the avatar
    // row (loaded last) visibly pop in after everything else.
    await Future.wait([
      _loadFeedFromSupabase(),
      _loadCheckinStatus(),
      _loadNestMembers(),
      _loadBookmarks(),
    ]);
  }

  Future<void> _loadBookmarks() async {
    try {
      final bookmarkUserId = Supabase.instance.client.auth.currentUser?.id;
      if (bookmarkUserId != null) {
        final rows = await Supabase.instance.client
            .from('user_favourites')
            .select('item_id')
            .eq('user_id', bookmarkUserId);
        if (mounted) {
          setState(() {
            _bookmarkedIds = (rows as List<dynamic>)
                .map((e) => e['item_id'] as String)
                .toSet();
          });
        }
      }
    } catch (_) {}
  }

  void _setupItemAnimations() {
    // Home shows cached/placeholder data immediately so the first paint
    // isn't blank, then quietly swaps in real Supabase data moments later
    // once _loadFeedFromSupabase() finishes. The old jitter came from
    // re-animating that swap on top of an animation that already played --
    // not from having a staggered reveal in the first place. Every other
    // screen (Favs/Legacy/Safety/Share/Setup) already uses this same
    // staggered fade + slide-up pattern; Home now matches them for its
    // one true first reveal, then updates quietly after that.
    _itemAnimations.clear();
    for (int i = 0; i < _messages.length; i++) {
      if (!_hasPlayedEntranceOnce) {
        final start = (i * 0.08).clamp(0.0, 0.7);
        final end = (start + 0.4).clamp(0.0, 1.0);
        _itemAnimations.add(
          CurvedAnimation(
            parent: _listEntranceController,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          ),
        );
      } else {
        // Real data arriving after the first reveal already played updates
        // quietly -- no replay, no re-animating cards the user has seen.
        _itemAnimations.add(const AlwaysStoppedAnimation<double>(1.0));
      }
    }
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}_${now.month}_${now.day}';
  }

  String _todayDateString() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  Future<void> _loadCheckinStatus() async {
    try {
      final supabase = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();
      final nestId = prefs.getString('nest_id') ?? '';
      if (nestId.isEmpty) return;

      // Find the senior in this nest
      final membersResponse = await supabase
          .from('nest_members')
          .select('user_id, user_profiles(display_name, preferred_name, role)')
          .eq('nest_id', nestId);
      final members = membersResponse as List<dynamic>;

      String seniorId = '';
      String seniorName = '';
      for (final m in members) {
        final profile = m['user_profiles'] as Map<String, dynamic>?;
        if (profile?['role'] == 'senior') {
          seniorId = m['user_id'] as String? ?? '';
          final preferred = profile?['preferred_name'] as String? ?? '';
          final first = profile?['display_name'] as String? ?? '';
          seniorName = preferred.isNotEmpty ? preferred : first;
          break;
        }
      }
      if (seniorId.isEmpty) return;
      if (seniorName.isEmpty) seniorName = 'Your senior';

      // Check if that senior has checked in today, and whether they've
      // logged their medications today. Two independent queries against
      // different tables with no data dependency between them, so run
      // them concurrently rather than one after the other. Meds reuses
      // the seniorId/seniorName already resolved above rather than a
      // second nest_members lookup, same table shape and RLS as
      // daily_checkins (nest members can read, each user can only insert
      // their own row).
      final results = await Future.wait([
        supabase
            .from('daily_checkins')
            .select('created_at')
            .eq('user_id', seniorId)
            .eq('checkin_date', _todayDateString())
            .maybeSingle(),
        supabase
            .from('daily_medications')
            .select('created_at')
            .eq('user_id', seniorId)
            .eq('med_date', _todayDateString())
            .maybeSingle(),
      ]);
      final checkinResponse = results[0];
      final medsResponse = results[1];

      if (mounted) {
        setState(() {
          _seniorUserId = seniorId;
          _seniorName = seniorName;
          _seniorCheckedInToday = checkinResponse != null;
          _seniorCheckinTime = checkinResponse != null
              ? DateTime.parse(checkinResponse['created_at'] as String)
              : null;
          _seniorMedsTakenToday = medsResponse != null;
          _seniorMedsTakenTime = medsResponse != null
              ? DateTime.parse(medsResponse['created_at'] as String)
              : null;
          _topCardsAnimatedOnceThisSession = true;
          // Reconcile the local-only good_today_* flag (drives the
          // floating "I'm Good" button) against this real database check
          // (drives the "You checked in today" card above) whenever this
          // is the senior's own device. These were two completely
          // separate, never-reconciled sources of truth for the same
          // fact -- one purely local, one server-verified -- so if the
          // local flag ever fell out of sync for any reason (a fresh
          // install, a cleared cache, or anything else), the card and
          // the button could permanently disagree with each other for
          // the rest of the day, showing "checked in" and the button to
          // check in again at the same time. The server record is
          // authoritative; sync the local flag to match it either way.
          if (_isSenior) {
            _isGoodTodaySent = checkinResponse != null;
          }
        });
        if (_isSenior) {
          await prefs.setBool(
            'good_today_${_todayKey()}',
            checkinResponse != null,
          );
          appIsGoodTodaySentNotifier.value = checkinResponse != null;
        }
        // Update the shared notifier so any other screen currently showing
        // this value picks it up immediately. Persistence to
        // cached_checkin_checked_in/nest_id/date already happens a few
        // lines below in the existing try block -- no need to duplicate it.
        appSeniorCheckedInTodayNotifier.value = checkinResponse != null;
        appSeniorMedsTakenTodayNotifier.value = medsResponse != null;
      }

      try {
        await prefs.setString('cached_checkin_nest_id', nestId);
        await prefs.setString('cached_checkin_date', _todayDateString());
        await prefs.setString('cached_checkin_senior_id', seniorId);
        await prefs.setString('cached_checkin_senior_name', seniorName);
        appSeniorNameNotifier.value = seniorName;
        await prefs.setBool('cached_checkin_checked_in', checkinResponse != null);
        if (checkinResponse != null) {
          await prefs.setString(
              'cached_checkin_time', checkinResponse['created_at'] as String);
        } else {
          await prefs.remove('cached_checkin_time');
        }
        await prefs.setBool('cached_checkin_meds_taken', medsResponse != null);
        if (medsResponse != null) {
          await prefs.setString(
              'cached_checkin_meds_time', medsResponse['created_at'] as String);
        } else {
          await prefs.remove('cached_checkin_meds_time');
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('CHECKIN_STATUS_LOAD_ERROR: $e');
    }
  }

  // ── Avatar row: fetch everyone else in the Nest ─────────────────────────
  // Placeholder avatars shown until real family members join — same pattern
  // as the sample banners on Home/Legacy/Favs. Disappear the moment the
  // first real member is found; real members always take full priority.
  static final List<Map<String, dynamic>> _sampleNestMembers = [
    {
      'id': 'sample_sarah',
      'name': 'Sarah',
      'avatarUrl':
          'https://images.unsplash.com/photo-1707362257505-184cd67f1855',
      'avatarLabel': 'Smiling woman with brown hair in casual blue top, outdoors',
      'role': 'family',
      'isSample': true,
    },
    {
      'id': 'sample_michael',
      'name': 'Michael',
      'avatarUrl':
          'https://images.unsplash.com/photo-1735181094336-7fa757df9622',
      'avatarLabel': 'Middle-aged man with short dark hair smiling, light background',
      'role': 'family',
      'isSample': true,
    },
    {
      'id': 'sample_priya',
      'name': 'Priya',
      'avatarUrl':
          'https://img.rocket.new/generatedImages/rocket_gen_img_115ec4756-1776378820432.png',
      'avatarLabel': 'Young woman with long dark hair and bright smile, warm background',
      'role': 'family',
      'isSample': true,
    },
    {
      'id': 'sample_david',
      'name': 'David',
      'avatarUrl':
          'https://images.unsplash.com/photo-1627646580365-35950e51cd95',
      'avatarLabel': 'Young man with curly hair and glasses smiling in casual wear',
      'role': 'family',
      'isSample': true,
    },
    {
      'id': 'sample_emma',
      'name': 'Emma',
      'avatarUrl': '',
      'avatarLabel': '',
      'role': 'family',
      'isSample': true,
    },
    {
      'id': 'sample_james',
      'name': 'James',
      'avatarUrl': '',
      'avatarLabel': '',
      'role': 'family',
      'isSample': true,
    },
  ];

  Future<void> _loadNestMembers() async {
    try {
      final supabase = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();
      final nestId = prefs.getString('nest_id') ?? '';
      final currentUserId = supabase.auth.currentUser?.id ?? '';
      if (nestId.isEmpty) return;

      final membersResponse = await supabase
          .from('nest_members')
          .select(
              'user_id, user_profiles(display_name, preferred_name, avatar_url, role)')
          .eq('nest_id', nestId);
      final rows = membersResponse as List<dynamic>;

      final loaded = <Map<String, dynamic>>[];
      for (final row in rows) {
        final userId = row['user_id'] as String? ?? '';
        if (userId.isEmpty || userId == currentUserId) continue;
        final profile = row['user_profiles'] as Map<String, dynamic>?;
        final preferred = profile?['preferred_name'] as String? ?? '';
        final display = profile?['display_name'] as String? ?? '';
        final name = preferred.isNotEmpty ? preferred : display;
        if (name.isEmpty) continue;
        loaded.add({
          'id': userId,
          'name': name,
          'avatarUrl': profile?['avatar_url'] as String? ?? '',
          'avatarLabel': '$name profile photo',
          'role': profile?['role'] as String? ?? 'family',
          'isSample': false,
        });
      }

      // Real members always fully replace samples — even just one real
      // member is enough to drop every placeholder.
      final membersToShow = loaded.isNotEmpty ? loaded : _sampleNestMembers;

      if (mounted) {
        setState(() {
          _nestMembers = membersToShow;
          _topCardsAnimatedOnceThisSession = true;
        });
      }

      try {
        final cacheUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
        await prefs.setString('cached_nest_members', jsonEncode(membersToShow));
        await prefs.setString('cached_nest_members_nest_id', nestId);
        await prefs.setString('cached_nest_members_user_id', cacheUserId);
      } catch (_) {}
    } catch (e) {
      debugPrint('NEST_MEMBERS_LOAD_ERROR: $e');
    }
  }

  void _onAvatarRowMemberTap(Map<String, dynamic> member) {
    if (member['isSample'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${member['name']} is a sample — real messaging opens once your family joins.',
          ),
          backgroundColor: const Color(0xFF5DA399),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.pushNamed(
      context,
      AppRoutes.messageThreadScreen,
      arguments: {
        'recipientId': member['id'] as String? ?? '',
        'recipientName': member['name'] as String? ?? 'Nest Member',
        'recipientAvatarUrl': member['avatarUrl'] as String?,
      },
    );
  }

  void _showWelcomeMessage() {
    if (!mounted) return;
    // _showWelcomeToast is only ever true when first_load was true at read
    // time -- i.e. this is a brand-new account's very first visit to Home,
    // not a genuine returning session. The copy previously said "Welcome
    // back" unconditionally, which is wrong for a signup that has never
    // been here before.
    final isGenuinelyFirstVisit = _showWelcomeToast;
    final greeting = isGenuinelyFirstVisit
        ? (_displayName.isNotEmpty
            ? 'Welcome to your Nest, $_displayName! 💛'
            : 'Welcome to your Nest! 💛')
        : (_displayName.isNotEmpty
            ? 'Welcome back, $_displayName! Your family is thinking of you 💛'
            : 'Welcome back! Your family is thinking of you 💛');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          greeting,
          style: GoogleFonts.nunitoSans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF5DA399),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _handleGoodToday() async {
    if (_isGoodTodaySent) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('good_today_${_todayKey()}', true);
    appIsGoodTodaySentNotifier.value = true;
    setState(() {
      _isGoodTodaySent = true;
      _justCheckedIn = true;
    });

    // Show the "Sent!" confirmation briefly, then hide the FAB until tomorrow
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) {
        setState(() => _justCheckedIn = false);
      }
    });

    try {
      final supabase = Supabase.instance.client;
      final nestId = prefs.getString('nest_id') ?? '';
      final userId = supabase.auth.currentUser?.id;
      if (nestId.isNotEmpty && userId != null) {
        await supabase.from('daily_checkins').upsert(
          {
            'nest_id': nestId,
            'user_id': userId,
            'checkin_date': _todayDateString(),
          },
          onConflict: 'user_id,checkin_date',
        );
        if (mounted) {
          await _loadCheckinStatus();
        }
      }
    } catch (e) {
      debugPrint('GOOD_TODAY_SEND_ERROR: $e');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.favorite_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                'Your family knows you\'re doing great today!',
                style: GoogleFonts.nunitoSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF5DA399),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _handleMedsTaken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('meds_reminder_${_todayKey()}', false);
    setState(() => _showMedsReminder = false);

    // Previously this was purely local -- it dismissed the reminder card
    // on this one device only, with nothing written anywhere shared and
    // nobody else in the nest ever finding out. Now saves a real record
    // (same daily_medications table/RLS shape as daily_checkins) and
    // reloads status so the pinned meds card family members see updates
    // immediately, the same way the "I'm Good" check-in already works.
    try {
      final supabase = Supabase.instance.client;
      final nestId = prefs.getString('nest_id') ?? '';
      final userId = supabase.auth.currentUser?.id;
      if (nestId.isNotEmpty && userId != null) {
        await supabase.from('daily_medications').upsert(
          {
            'nest_id': nestId,
            'user_id': userId,
            'med_date': _todayDateString(),
          },
          onConflict: 'user_id,med_date',
        );
        if (mounted) {
          await _loadCheckinStatus();
        }
      }
    } catch (e) {
      debugPrint('MEDS_TAKEN_SEND_ERROR: $e');
    }
  }

  Future<void> _toggleHeart(int index) async {
    final msg = _messages[index];
    final wasHearted = msg.isHearted;
    final prevCount = msg.heartCount;

    setState(() {
      msg.isHearted = !wasHearted;
      msg.heartCount = wasHearted ? prevCount - 1 : prevCount + 1;
    });

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      if (wasHearted) {
        await supabase
            .from('feed_hearts')
            .delete()
            .eq('feed_post_id', msg.id)
            .eq('user_id', userId);
      } else {
        await supabase.from('feed_hearts').insert({
          'feed_post_id': msg.id,
          'user_id': userId,
        });
      }
    } catch (e) {
      debugPrint('FEED HEART TOGGLE ERROR: $e');
      if (mounted) {
        setState(() {
          msg.isHearted = wasHearted;
          msg.heartCount = prevCount;
        });
      }
    }
  }

  Future<void> _onRefresh() async {
    await _loadFeedFromSupabase();
  }

  Future<void> _loadFeedFromSupabase() async {
    try {
      final supabase = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();
      final nestId = prefs.getString('nest_id') ?? '';
      final userId = supabase.auth.currentUser?.id;

      if (nestId.isEmpty || userId == null) return;

      final response = await supabase
          .from('feed_posts')
          .select('*, user_profiles(display_name, preferred_name, avatar_url, relation_type, role)')
          .eq('nest_id', nestId)
          .isFilter('parent_post_id', null)
          .isFilter('legacy_entry_id', null)
          // Pinned posts (1/2/3) float above everything else, in slot
          // order. nullsFirst: false (also the package's own default --
          // spelled out explicitly here so the intent reads clearly rather
          // than relying on an unstated default) puts unpinned posts
          // (pinned_position is null) after every pinned one, regardless
          // of the ascending sort applying to the numeric slots themselves.
          .order('pinned_position', ascending: true, nullsFirst: false)
          .order('created_at', ascending: false)
          .limit(50);

      final localPreferredName = prefs.getString('preferred_name') ?? '';
      final localFirstName = prefs.getString('display_name') ?? '';
      final localName = localPreferredName.isNotEmpty ? localPreferredName : localFirstName;
      final posts = response as List<dynamic>;
      final postIds = posts.map((p) => p['id'] as String).toList();

      Map<String, int> heartCounts = {};
      Set<String> heartedByMe = {};
      if (postIds.isNotEmpty) {
        try {
          final heartsResponse = await supabase
              .from('feed_hearts')
              .select('feed_post_id, user_id')
              .inFilter('feed_post_id', postIds);
          final hearts = heartsResponse as List<dynamic>;
          for (final h in hearts) {
            final pId = h['feed_post_id'] as String;
            heartCounts[pId] = (heartCounts[pId] ?? 0) + 1;
            if (h['user_id'] == userId) heartedByMe.add(pId);
          }
        } catch (e) {
          debugPrint('FEED HEARTS LOAD ERROR: $e');
        }
      }

      // Resolve visible_to_ids -> real names. _nestMembers excludes the
      // current user by design, so add self in separately.
      final memberNameById = <String, String>{
        for (final m in _nestMembers)
          (m['id'] as String? ?? ''): (m['name'] as String? ?? ''),
      };
      if (userId != null) {
        memberNameById[userId] = localName.isNotEmpty ? localName : 'You';
      }

      final List<MessageModel> loaded = posts.map((post) {
        final profile = post['user_profiles'] as Map<String, dynamic>?;
        final authorId = post['author_id'] as String? ?? '';        final supabasePreferredName = profile?['preferred_name'] as String? ?? '';
        final supabaseFirstName = profile?['display_name'] as String? ?? '';
        final supabaseName = supabasePreferredName.isNotEmpty
            ? supabasePreferredName
            : supabaseFirstName;
        final senderName = supabaseName.isNotEmpty
            ? supabaseName
            : (authorId == userId && localName.isNotEmpty ? localName : 'Family');
        String avatarUrl = profile?['avatar_url'] as String? ?? '';
        // The raw Supabase value is a JSON blob ({"type":"emoji"/"photo","value":...}),
        // not a usable plain URL/emoji. It must be decoded for ANY author, not just
        // the current device's own user — using it undecoded here silently breaks
        // rendering for every other person's posts.
        String? avatarJson = profile?['avatar_url'] as String?;
        if ((avatarJson == null || avatarJson.isEmpty) && authorId == userId) {
          // Fall back to local prefs only for the current user's own posts,
          // e.g. right after picking a new avatar before Supabase has synced.
          avatarJson = prefs.getString(kProfilePhotoKey);
        }
        if (avatarUrl.isEmpty && authorId == userId) {
          final profileJson = prefs.getString(kProfilePhotoKey);
          if (profileJson != null) {
            try {
              final profileData = jsonDecode(profileJson) as Map<String, dynamic>;
              avatarUrl = profileData['value'] as String? ?? '';
            } catch (_) {}
          }
        }
        final rawRelation = profile?['relation_type'] as String? ?? 'Family';
        final relation = rawRelation.isNotEmpty
            ? rawRelation[0].toUpperCase() + rawRelation.substring(1)
            : rawRelation;
        final senderRole = profile?['role'] as String? ?? 'family';
        final type = post['post_type'] as String? ?? 'text';
        final rawVisibleTo = post['visible_to_ids'];
        String recipientLabel = 'Everyone in the Nest';
        if (rawVisibleTo is List && rawVisibleTo.isNotEmpty) {
          final names = rawVisibleTo
              .map((id) => memberNameById[id as String] ?? '')
              .where((n) => n.isNotEmpty)
              .toList();
          if (names.isNotEmpty) {
            recipientLabel = names.join(', ');
          }
        }
        return MessageModel(
          id: post['id'] as String,
          authorId: authorId,
          senderName: senderName,
          senderRelationship: relation,
          senderRole: senderRole,
          senderAvatarUrl: avatarUrl,
          senderAvatarLabel: senderName,
          senderAvatarJson: avatarJson,
          type: MessageModel._messageTypeFromString(type),
          content: post['content'] as String? ?? '',
          imageUrl: post['media_url'] as String? ?? '',
          imageSemanticLabel: '',
          timestamp: DateTime.parse(post['created_at'] as String),
          heartCount: heartCounts[post['id'] as String] ?? 0,
          isHearted: heartedByMe.contains(post['id'] as String),
          isRecordedVideo: post['is_recorded_video'] as bool? ?? false,
          recipientLabel: recipientLabel,
          pinnedPosition: post['pinned_position'] as int?,
        );
      }).toList();

      if (loaded.isNotEmpty) {
        await prefs.setString(
          'cached_real_messages',
          jsonEncode(loaded.map((m) => m.toMap()).toList()),
        );
        await prefs.setString('cached_real_messages_nest_id', nestId);
        if (mounted) {
          setState(() {
            _hasRealPost = true;
            _messages = loaded;
          });
          // Wasn't previously persisted anywhere -- without this, every
          // cold launch would still guess false here regardless of history,
          // defeating the point of the notifier fix.
          appHasRealPostNotifier.value = true;
          await prefs.setBool('has_real_post', true);
          // The entrance animation already played once on first load — just
          // rebuild the per-item animations to match the new list length so
          // any additional cards render at full opacity immediately, with no
          // replay. Real data should update quietly, not restart the reveal.
          _setupItemAnimations();
        }
      }
    } catch (e) {
      debugPrint('Feed load error: $e');
    }
  }

  Future<void> _toggleBookmark(MessageModel msg) async {
    final id = msg.id;
    final isNowBookmarked = !_bookmarkedIds.contains(id);

    setState(() {
      if (isNowBookmarked) {
        _bookmarkedIds.add(id);
      } else {
        _bookmarkedIds.remove(id);
      }
    });

    // Save bookmark to Supabase
    final bookmarkUserId = Supabase.instance.client.auth.currentUser?.id;
    if (bookmarkUserId == null) return;

    if (isNowBookmarked) {
      String category;
      switch (msg.type) {
        case MessageType.photo:
          category = 'Photos';
          break;
        case MessageType.voice:
          category = 'Audio';
          break;
        case MessageType.video:
          category = 'Video';
          break;
        default:
          category = 'Text';
      }
      final item = {
        'id': id,
        'category': category,
        'senderName': msg.senderName,
        'senderRelationship': msg.senderRelationship,
        'senderRole': msg.senderRole,
        'recipientLabel': msg.recipientLabel,
        'senderAvatarUrl': msg.senderAvatarUrl,
        'senderAvatarLabel': msg.senderAvatarLabel,
        'content': msg.content,
        'imageUrl': msg.imageUrl,
        'imageSemanticLabel': msg.imageSemanticLabel,
        'timestamp': msg.timestamp.toIso8601String(),
        'sourceType': 'message',
        'media_url': msg.imageUrl,
        'entry_type': category.toLowerCase(),
      };
      try {
        await Supabase.instance.client.from('user_favourites').upsert({
          'user_id': bookmarkUserId,
          'item_id': id,
          'item_data': item,
        });
      } catch (_) {
        // Aug 21 2026: found during a general audit -- this used to fail
        // completely silently. The optimistic setState above already
        // marked this bookmarked locally; if the actual server write
        // fails, local and server state silently disagree (item shows
        // bookmarked here, isn't really saved, and won't be there next
        // time favourites loads from Supabase). Reverting the optimistic
        // update and telling the person keeps what they see honest.
        if (mounted) {
          setState(() => _bookmarkedIds.remove(id));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Couldn\'t save that -- please try again.',
                style: GoogleFonts.nunitoSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              backgroundColor: const Color(0xFFC97B4A),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } else {
      try {
        await Supabase.instance.client
            .from('user_favourites')
            .delete()
            .eq('user_id', bookmarkUserId)
            .eq('item_id', id);
      } catch (_) {
        // Same fix as above, mirrored for the unbookmark direction.
        if (mounted) {
          setState(() => _bookmarkedIds.add(id));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Couldn\'t remove that -- please try again.',
                style: GoogleFonts.nunitoSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              backgroundColor: const Color(0xFFC97B4A),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  void _onNavTap(int index) {
    if (index == 0) return; // Already on Family Feed
    setState(() => _currentNavIndex = index);
    switch (index) {
      case 1:
        Navigator.pushReplacementNamed(context, '/send-screen');
        break;
      case 2:
        Navigator.pushReplacementNamed(context, '/legacy-screen');
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/safety-screen');
        break;
      case 4:
        Navigator.pushReplacementNamed(context, '/favs-screen');
        break;
      case 5:
        Navigator.pushReplacementNamed(context, '/setup-screen');
        break;
    }
  }

  @override
  void dispose() {
    _realtimeRefreshDebounce?.cancel();
    _feedChannel?.unsubscribe();
    _listEntranceController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;

    return Scaffold(
      backgroundColor: _isDarkMode
          ? const Color(0xFF1A1612)
          : const Color(0xFFFDFDFD),
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Top bar
                FeedTopBarWidget(
                  nestName: _nestName,
                  isDarkMode: _isDarkMode,
                  onNestTap: _showNestSwitcher,
                  onNotificationTap: () {
                    Navigator.pushNamed(context, AppRoutes.notificationsScreen);
                  },
                  onProfileTap: () {},
                ),
                // Content
                Expanded(child: _buildBody(isTablet)),
              ],
            ),
          ),
          const KeyboardDoneBarOverlay(),
        ],
      ),
      floatingActionButton: (_isSenior && (!_isGoodTodaySent || _justCheckedIn))
          ? ImGoodTodayOrbWidget(
              isSent: _isGoodTodaySent,
              onTap: _handleGoodToday,
            )
          : null,
      bottomNavigationBar: AppNavigation(
        currentIndex: _currentNavIndex,
        onTap: _onNavTap,
      ),
    );
  }

  Widget _buildBody(bool isTablet) {
    // Quick fix (see tech doc for the real fix): no fade/switch animation
    // here at all. Because this screen is fully rebuilt from scratch every
    // time the user taps into Home from bottom nav, any transition here
    // was replaying on every visit, which is what caused the "double
    // flash" / jitter. Home now just appears immediately, fully formed.
    return _isLoading ? _buildLoadingState() : _buildFeedContent(isTablet);
  }

  Widget _buildFeedContent(bool isTablet) {
    return RefreshIndicator(
      key: const ValueKey('feedContent'),
      onRefresh: _onRefresh,
      color: const Color(0xFF5DA399),
      backgroundColor: const Color(0xFFFDFDFD),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 28 : 20,
              vertical: 12,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Nest avatar row — everyone in the Nest, tap to message them.
                // Wrapped in the same fade+lift language as the rest of the
                // app instead of abruptly popping into the layout once its
                // data finishes loading.
                AnimatedSwitcher(
                  duration: _topCardsAnimatedOnceThisSession
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    final curved =
                        CurvedAnimation(parent: animation, curve: Curves.easeOut);
                    return FadeTransition(
                      opacity: curved,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.03),
                          end: Offset.zero,
                        ).animate(curved),
                        child: child,
                      ),
                    );
                  },
                  child: _nestMembers.isNotEmpty
                      ? Column(
                          key: const ValueKey('avatarRowPresent'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            NestAvatarRowWidget(
                              members: _nestMembers,
                              isDarkMode: _isDarkMode,
                              onMemberTap: _onAvatarRowMemberTap,
                            ),
                            const SizedBox(height: 16),
                          ],
                        )
                      : const SizedBox.shrink(key: ValueKey('avatarRowEmpty')),
                ),
                // Pinned daily check-in status card (shown once we know who the senior is)
                AnimatedSwitcher(
                  duration: _topCardsAnimatedOnceThisSession
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    final curved =
                        CurvedAnimation(parent: animation, curve: Curves.easeOut);
                    return FadeTransition(
                      opacity: curved,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.03),
                          end: Offset.zero,
                        ).animate(curved),
                        child: child,
                      ),
                    );
                  },
                  child: _seniorUserId.isNotEmpty
                      ? Column(
                          key: const ValueKey('checkinPresent'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DailyCheckinCardWidget(
                              isDarkMode: _isDarkMode,
                              isSenior: _isSenior,
                              seniorName: _seniorName,
                              checkedIn: _seniorCheckedInToday,
                              checkinTime: _seniorCheckinTime,
                            ),
                            const SizedBox(height: 10),
                            DailyMedsCardWidget(
                              isDarkMode: _isDarkMode,
                              isSenior: _isSenior,
                              seniorName: _seniorName,
                              takenToday: _seniorMedsTakenToday,
                              takenTime: _seniorMedsTakenTime,
                            ),
                            const SizedBox(height: 14),
                          ],
                        )
                      : const SizedBox.shrink(key: ValueKey('checkinEmpty')),
                ),
                // Meds reminder (senior only). Previously this only
                // checked _showMedsReminder, never the real
                // _seniorMedsTakenToday (sourced from Supabase) -- so this
                // card's own internal _isTaken flag, which always starts
                // false on every load/re-sign-in, would show the "have you
                // taken your medications" prompt again even directly
                // underneath the confirmed "You took your medications
                // today" card above it. Now it hides once the real record
                // says today's dose is already logged, same as every other
                // confirmed-state card on this screen.
                if (_isSenior && _showMedsReminder && !_seniorMedsTakenToday) ...[
                  MedsReminderCardWidget(
                    isDarkMode: _isDarkMode,
                    onTaken: _handleMedsTaken,
                  ),
                  const SizedBox(height: 14),
                ],
                // Invite reminder (family nest owner only, if code not yet shared)
                if (!_isSenior && _isNestOwner && !_inviteCodeShared) ...[
                  _buildInviteReminderBanner(),
                  const SizedBox(height: 14),
                ],
                // Celebrations card (all users, only if events within 30 days)
                if (_todayCelebrations.isNotEmpty ||
                    _upcomingCelebrations.isNotEmpty) ...[
                  CelebrationsCardWidget(
                    isDarkMode: _isDarkMode,
                    todayEvents: _todayCelebrations,
                    upcomingEvents: _upcomingCelebrations,
                  ),
                  const SizedBox(height: 14),
                ],
                // Legacy prompt card
                if (_isSenior)
                  LegacyPromptCardWidget(
                    isDarkMode: _isDarkMode,
                    prompt:
                        'What\'s your favorite family tradition that you\'d love to pass down?',
                    isSenior: _isSenior,
                    onRespond: () {
                      Navigator.pushReplacementNamed(context, '/legacy-screen');
                    },
                  ),
                const SizedBox(height: 20),
                // Sample content explainer banner (shown once, while sample cards are visible)
                if (!_hasRealPost) ...[
                  _buildSampleContentBanner(),
                  const SizedBox(height: 14),
                ],
                // Feed header
                _buildFeedHeader(),
                const SizedBox(height: 12),
              ]),
            ),
          ),
          // Messages
          (_messages.isEmpty && _hasRealPost)
              ? SliverFillRemaining(
                  hasScrollBody: false,
                  child: FeedEmptyStateWidget(
                    isDarkMode: _isDarkMode,
                    onSend: () =>
                        Navigator.pushReplacementNamed(context, '/send-screen'),
                  ),
                )
              : isTablet
              ? _buildTabletGrid()
              : _buildPhoneList(),
          // Bottom padding for FAB + nav
          const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
        ],
      ),
    );
  }

  Widget _buildFeedHeader() {
    return Row(
      children: [
        Text(
          'From Your Family',
          style: GoogleFonts.nunitoSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _isDarkMode
                ? const Color(0xFFF5EDD8)
                : const Color(0xFF2C2417),
          ),
        ),
        const Spacer(),
        if (_messages.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF5DA399).withAlpha(31),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${_messages.length} messages',
              style: GoogleFonts.nunitoSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF5DA399),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSampleContentBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFD4AA00).withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFD4AA00).withAlpha(60),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.info_outline_rounded,
              color: Color(0xFFB8860B),
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This is what your Nest will look like. These examples disappear once your family starts posting.',
              style: GoogleFonts.nunitoSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: _isDarkMode
                    ? const Color(0xFFB8A888)
                    : const Color(0xFF6B5E4E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteReminderBanner() {
    return GestureDetector(
      onTap: () {
        Navigator.pushReplacementNamed(context, '/setup-screen');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFD4AA5E).withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFD4AA5E).withAlpha(60),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.vpn_key_rounded,
              color: Color(0xFFD4AA5E),
              size: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Share your invite code so family can join the nest',
                style: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _isDarkMode
                      ? const Color(0xFFB8A888)
                      : const Color(0xFF6B5E4E),
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Share →',
              style: GoogleFonts.nunitoSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFD4AA5E),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Aug 21 2026: collapsible year/month grouping for Home's feed.
  // Pinned messages stay exactly as they were -- ungrouped, at the top,
  // in their existing pin-slot order -- since a pinned post shouldn't
  // collapse into "August 2026" along with everything else. Only the
  // remaining, non-pinned messages get grouped. animIndex on every
  // message-carrying entry is that message's ORIGINAL index in
  // _messages, preserved through grouping so heart-toggling and the
  // entrance animation (both keyed to the original flat index) keep
  // working exactly as before -- grouping only changes what's rendered
  // and in what order, not the underlying indexing either of those
  // already depended on.
  List<_HomeListEntry> _buildHomeListEntries() {
    final entries = <_HomeListEntry>[];
    final unpinned = <MessageModel>[];
    final originalIndex = <MessageModel, int>{};
    for (int i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      originalIndex[m] = i;
      if (m.pinnedPosition != null) {
        entries.add(_HomeListEntry.message(m, i));
      } else {
        unpinned.add(m);
      }
    }
    final groups = groupByYearMonth<MessageModel>(
      unpinned,
      (m) => m.timestamp,
    );
    for (final yearGroup in groups) {
      final yearKey = 'year-${yearGroup.year}';
      final yearCount = yearGroup.months.fold<int>(
        0,
        (sum, mg) => sum + mg.items.length,
      );
      entries.add(
        _HomeListEntry.yearHeader('${yearGroup.year}', yearCount, yearKey),
      );
      if (_collapsedGroupKeys.contains(yearKey)) continue;
      for (final monthGroup in yearGroup.months) {
        final monthKey = 'month-${yearGroup.year}-${monthGroup.month}';
        entries.add(
          _HomeListEntry.monthHeader(
            kMonthNames[monthGroup.month - 1],
            monthGroup.items.length,
            monthKey,
          ),
        );
        if (_collapsedGroupKeys.contains(monthKey)) continue;
        for (final m in monthGroup.items) {
          entries.add(_HomeListEntry.message(m, originalIndex[m]!));
        }
      }
    }
    return entries;
  }

  Widget _buildPhoneList() {
    final entries = _buildHomeListEntries();
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final entry = entries[index];
          if (entry.kind == _HomeEntryKind.yearHeader ||
              entry.kind == _HomeEntryKind.monthHeader) {
            return CollapsibleGroupHeader(
              label: entry.headerLabel!,
              itemCount: entry.headerCount!,
              isCollapsed: _collapsedGroupKeys.contains(entry.groupKey),
              isDarkMode: _isDarkMode,
              isYear: entry.kind == _HomeEntryKind.yearHeader,
              onToggle: () {
                setState(() {
                  if (_collapsedGroupKeys.contains(entry.groupKey)) {
                    _collapsedGroupKeys.remove(entry.groupKey);
                  } else {
                    _collapsedGroupKeys.add(entry.groupKey!);
                  }
                });
              },
            );
          }
          final msgIndex = entry.animIndex!;
          final anim = msgIndex < _itemAnimations.length
              ? _itemAnimations[msgIndex]
              : const AlwaysStoppedAnimation(1.0);
          return AnimatedBuilder(
            animation: anim,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, 8 * (1 - anim.value)),
              child: Opacity(opacity: anim.value, child: child),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: MessageCardWidget(
                key: ValueKey(entry.message!.id),
                message: entry.message!,
                isDarkMode: _isDarkMode,
                onHeart: () => _toggleHeart(msgIndex),
                isBookmarked: _bookmarkedIds.contains(entry.message!.id),
                onBookmark: () => _toggleBookmark(entry.message!),
                senderAvatarJson: entry.message!.senderAvatarJson,
                canDelete: _canDeletePost(entry.message!),
                onDelete: () => _deletePost(entry.message!.id),
                canPin: _canPinPost(entry.message!),
                occupiedPinSlots: _occupiedPinSlots,
                onPinSlotChosen: (slot) =>
                    _setPinSlot(entry.message!, slot),
              ),
            ),
          );
        }, childCount: entries.length),
      ),
    );
  }

  Widget _buildTabletGrid() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.85,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final anim = index < _itemAnimations.length
              ? _itemAnimations[index]
              : const AlwaysStoppedAnimation(1.0);
          return AnimatedBuilder(
            animation: anim,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, 8 * (1 - anim.value)),
              child: Opacity(opacity: anim.value, child: child),
            ),
            child: MessageCardWidget(
              key: ValueKey(_messages[index].id),
              message: _messages[index],
              isDarkMode: _isDarkMode,
              onHeart: () => _toggleHeart(index),
              isBookmarked: _bookmarkedIds.contains(_messages[index].id),
              onBookmark: () => _toggleBookmark(_messages[index]),
              senderAvatarJson: _messages[index].senderAvatarJson,
              canDelete: _canDeletePost(_messages[index]),
              onDelete: () => _deletePost(_messages[index].id),
              canPin: _canPinPost(_messages[index]),
              occupiedPinSlots: _occupiedPinSlots,
              onPinSlotChosen: (slot) => _setPinSlot(_messages[index], slot),
            ),
          );
        }, childCount: _messages.length),
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      key: const ValueKey('feedLoading'),
      padding: const EdgeInsets.all(20),
      itemCount: 4,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: _buildSkeletonCard(),
      ),
    );
  }

  Widget _buildSkeletonCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Previously hardcoded to the light-mode colors only -- this had
        // no dark-mode branching at all, unlike the real feed cards it's
        // standing in for (message_card_widget.dart), which is why dark
        // mode showed light/white loading cards on Home specifically.
        // Same color pair used there for consistency.
        color: _isDarkMode ? const Color(0xFF242018) : const Color(0xFFFAF7F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isDarkMode ? const Color(0xFF3D3428) : const Color(0xFFE8E0D0),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _shimmer(44, 44, 22),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _shimmer(120, 14, 7),
                  const SizedBox(height: 6),
                  _shimmer(80, 12, 6),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _shimmer(double.infinity, 16, 8),
          const SizedBox(height: 8),
          _shimmer(200, 14, 7),
        ],
      ),
    );
  }

  Widget _shimmer(double w, double h, double r) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        // Same fix as the card background above -- was hardcoded to the
        // light tan regardless of dark mode.
        color: _isDarkMode ? const Color(0xFF3D3428) : const Color(0xFFE8E0D0),
        borderRadius: BorderRadius.circular(r),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchMyNests() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return [];
      final response = await supabase
          .from('nest_members')
          .select('nests(id, name)')
          .eq('user_id', userId);
      return (response as List<dynamic>)
          .map((row) => (row as Map<String, dynamic>)['nests'] as Map<String, dynamic>?)
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (e) {
      debugPrint('FETCH_MY_NESTS_ERROR: $e');
      return [];
    }
  }

  void _showNestSwitcher() async {
    final myNests = await _fetchMyNests();
    final prefs = await SharedPreferences.getInstance();
    final activeNestId = prefs.getString('nest_id') ?? '';
    if (!mounted) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss nest switcher',
      barrierColor: Colors.black.withAlpha(60),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, anim, secondaryAnim) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
        );
        return Stack(
          children: [
            Positioned(
              top: MediaQuery.of(ctx).padding.top + 72,
              left: 12,
              right: 12,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.3),
                  end: Offset.zero,
                ).animate(curved),
                child: FadeTransition(
                  opacity: curved,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      decoration: BoxDecoration(
                        color: _isDarkMode
                            ? const Color(0xFF242018)
                            : const Color(0xFFFDFDFD),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(40),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header row with close button
                          Row(
                            children: [
                              Text(
                                'Your Nests',
                                style: GoogleFonts.nunitoSans(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: _isDarkMode
                                      ? const Color(0xFFF5EDD8)
                                      : const Color(0xFF2C2417),
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => Navigator.pop(ctx),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: _isDarkMode
                                        ? const Color(0xFF3D3428)
                                        : const Color(0xFFF5F0E8),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: _isDarkMode
                                        ? const Color(0xFFB8A888)
                                        : const Color(0xFF6B5E4E),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Active nest shown at the top of your feed',
                            style: GoogleFonts.nunitoSans(
                              fontSize: 12,
                              color: _isDarkMode
                                  ? const Color(0xFF6B5E4E)
                                  : const Color(0xFFA8A090),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Real nest list, fetched in _showNestSwitcher
                          // before this dialog opened. Falls back to the
                          // cached name/active-only tile if the fetch came
                          // back empty (e.g. offline), so this never shows
                          // a completely blank sheet.
                          if (myNests.isEmpty)
                            _buildNestTile(_nestName, true, onTap: () => Navigator.pop(ctx))
                          else
                            ...myNests.map((nest) {
                              final nestId = nest['id'] as String?;
                              final nestNameVal = nest['name'] as String? ?? 'Unnamed Nest';
                              final isActive = nestId == activeNestId;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _buildNestTile(
                                  nestNameVal,
                                  isActive,
                                  onTap: () async {
                                    Navigator.pop(ctx);
                                    if (isActive || nestId == null) return;
                                    await prefs.setString('nest_id', nestId);
                                    await prefs.setString('nest_name', nestNameVal);
                                    appNestNameNotifier.value = nestNameVal;
                                    // Fresh instance of this same screen so
                                    // every load method re-reads the new
                                    // active nest_id from prefs, including
                                    // the realtime subscription -- safer
                                    // than hot-swapping state in place.
                                    if (mounted) {
                                      Navigator.pushReplacementNamed(
                                        context, AppRoutes.familyFeedScreen);
                                    }
                                  },
                                ),
                              );
                            }),
                          const SizedBox(height: 8),
                          _buildAddNestButton(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNestTile(String name, bool isActive, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF5DA399).withAlpha(20)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? const Color(0xFF5DA399) : const Color(0xFFE8E0D0),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF5DA399).withAlpha(30)
                    : const Color(0xFFF5F0E8),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.home_rounded,
                color: isActive
                    ? const Color(0xFF5DA399)
                    : const Color(0xFFA8A090),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 16,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                      color: isActive
                          ? const Color(0xFF5DA399)
                          : const Color(0xFF2C2417),
                    ),
                  ),
                  if (isActive)
                    Text(
                      'Currently active',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 11,
                        color: const Color(0xFF5DA399),
                      ),
                    ),
                ],
              ),
            ),
            if (isActive)
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF5DA399),
                size: 22,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddNestButton() {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        Navigator.pushNamed(context, AppRoutes.subscribeNestScreen,
          arguments: {'additionalNest': true});
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8E0D0), width: 1.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.add_rounded, color: Color(0xFF5DA399), size: 22),
            const SizedBox(width: 12),
            Text(
              'Create a new Nest',
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF5DA399),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Aug 21 2026: flattened entry type for Home's grouped feed list -- a
// single ordered list can mix real message cards with year/month header
// pills, letting one SliverList render both instead of needing separate
// slivers stitched together.
enum _HomeEntryKind { message, yearHeader, monthHeader }

class _HomeListEntry {
  _HomeListEntry.message(this.message, this.animIndex)
      : kind = _HomeEntryKind.message,
        headerLabel = null,
        headerCount = null,
        groupKey = null;

  _HomeListEntry.yearHeader(this.headerLabel, this.headerCount, this.groupKey)
      : kind = _HomeEntryKind.yearHeader,
        message = null,
        animIndex = null;

  _HomeListEntry.monthHeader(this.headerLabel, this.headerCount, this.groupKey)
      : kind = _HomeEntryKind.monthHeader,
        message = null,
        animIndex = null;

  final _HomeEntryKind kind;
  final MessageModel? message;
  final int? animIndex;
  final String? headerLabel;
  final int? headerCount;
  final String? groupKey;
}

