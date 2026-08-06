import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/app_navigation.dart';
import '../../widgets/keyboard_done_bar.dart';
import '../../routes/app_routes.dart';
import './widgets/feed_empty_state_widget.dart';
import './widgets/feed_top_bar_widget.dart';
import './widgets/im_good_today_orb_widget.dart';
import './widgets/daily_checkin_card_widget.dart';
import './widgets/legacy_prompt_card_widget.dart';
import './widgets/meds_reminder_card_widget.dart';
import './widgets/message_card_widget.dart';
import './widgets/celebrations_card_widget.dart';
import './widgets/nest_avatar_row_widget.dart';
import '../profile_photo_picker_screen/profile_photo_picker_screen.dart';

// ── Data Models ────────────────────────────────────────────────

enum MessageType { text, photo, video, voice }

class MessageModel {
  MessageModel({
    required this.id,
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
  });

  final String id;
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

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'] as String,
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
  bool _isSenior = false;
  String _displayName = '';
  String _nestName = '';
  bool _isGoodTodaySent = false;
  bool _justCheckedIn = false; // true only briefly right after tapping, to show the "Sent!" confirmation
  bool _showMedsReminder = true;
  bool _showWelcomeToast = false;
  bool _isLoading = true;
  bool _isDarkMode = false;
  bool _hasRealPost = false; // tracks if user has made their first real post
  bool _sampleBannerDismissed = false; // tracks if user closed the sample-content explainer banner
  String _seniorName = ''; // display name of the senior in this nest (for the pinned check-in card)
  String _seniorUserId = '';
  bool _seniorCheckedInToday = false;
  DateTime? _seniorCheckinTime;
  bool _inviteCodeShared =
      true; // tracks if family owner has shared invite code
  bool _isGuest = false;
  bool _isNestOwner = false;
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

  @override
  void initState() {
    super.initState();
    _listEntranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _loadData();
  }

  Future<void> _ensureNestId() async {
    final prefs = await SharedPreferences.getInstance();
    final existingNestId = prefs.getString('nest_id') ?? '';
    if (existingNestId.isNotEmpty) return;

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final result = await supabase
          .from('nests')
          .select('id')
          .eq('created_by', userId)
          .maybeSingle();

      if (result != null) {
        final nestId = result['id'] as String;
        await prefs.setString('nest_id', nestId);
        print('NEST_ID: saved = $nestId');
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
    final sampleBannerDismissed = prefs.getBool('sample_banner_dismissed') ?? false;
    final inviteCodeShared = prefs.getBool('invite_code_shared') ?? false;
    final isGuest = prefs.getBool('is_guest') ?? false;
    final joinedViaInvite = prefs.getBool('joined_via_invite') ?? false;

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
    final cachedMembersNestId = prefs.getString('cached_nest_members_nest_id') ?? '';
    List<Map<String, dynamic>> initialNestMembers = [];
    if (cachedMembersNestId.isNotEmpty && cachedMembersNestId == _currentNestIdForCache) {
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
    if (cachedCheckinNestId.isNotEmpty &&
        cachedCheckinNestId == _currentNestIdForCache &&
        cachedCheckinDate == _todayDateString()) {
      initialSeniorUserId = prefs.getString('cached_checkin_senior_id') ?? '';
      initialSeniorName = prefs.getString('cached_checkin_senior_name') ?? '';
      initialSeniorCheckedIn = prefs.getBool('cached_checkin_checked_in') ?? false;
      final cachedTimeStr = prefs.getString('cached_checkin_time');
      initialSeniorCheckinTime =
          cachedTimeStr != null ? DateTime.tryParse(cachedTimeStr) : null;
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
      _sampleBannerDismissed = sampleBannerDismissed;
      _inviteCodeShared = inviteCodeShared;
      _isGuest = isGuest;
      _isNestOwner = !joinedViaInvite;
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
      }
    });

    // Load bookmarks from Supabase
    try {
      final bookmarkUserId = Supabase.instance.client.auth.currentUser?.id;
      if (bookmarkUserId != null) {
        final rows = await Supabase.instance.client
            .from('user_favourites')
            .select('item_id')
            .eq('user_id', bookmarkUserId);
        setState(() {
          _bookmarkedIds = (rows as List<dynamic>)
              .map((e) => e['item_id'] as String)
              .toSet();
        });
      }
    } catch (_) {}

    _setupItemAnimations();
    _listEntranceController.forward();
    _hasPlayedEntranceOnce = true;

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

    // These three loads are independent of each other, so run them
    // concurrently. Previously they ran in sequence, which made the avatar
    // row (loaded last) visibly pop in after everything else.
    await Future.wait([
      _loadFeedFromSupabase(),
      _loadCheckinStatus(),
      _loadNestMembers(),
    ]);
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

      // Check if that senior has checked in today
      final checkinResponse = await supabase
          .from('daily_checkins')
          .select('created_at')
          .eq('user_id', seniorId)
          .eq('checkin_date', _todayDateString())
          .maybeSingle();

      if (mounted) {
        setState(() {
          _seniorUserId = seniorId;
          _seniorName = seniorName;
          _seniorCheckedInToday = checkinResponse != null;
          _seniorCheckinTime = checkinResponse != null
              ? DateTime.parse(checkinResponse['created_at'] as String)
              : null;
          _topCardsAnimatedOnceThisSession = true;
        });
      }

      try {
        await prefs.setString('cached_checkin_nest_id', nestId);
        await prefs.setString('cached_checkin_date', _todayDateString());
        await prefs.setString('cached_checkin_senior_id', seniorId);
        await prefs.setString('cached_checkin_senior_name', seniorName);
        await prefs.setBool('cached_checkin_checked_in', checkinResponse != null);
        if (checkinResponse != null) {
          await prefs.setString(
              'cached_checkin_time', checkinResponse['created_at'] as String);
        } else {
          await prefs.remove('cached_checkin_time');
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
        await prefs.setString('cached_nest_members', jsonEncode(membersToShow));
        await prefs.setString('cached_nest_members_nest_id', nestId);
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
    final greeting = _displayName.isNotEmpty
        ? 'Welcome back, $_displayName! Your family is thinking of you 💛'
        : 'Welcome back! Your family is thinking of you 💛';
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
          backgroundColor: const Color(0xFFD4AA00),
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
    // TODO: Replace with Supabase daily reset logic for production
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('meds_reminder_${_todayKey()}', false);
    setState(() => _showMedsReminder = false);
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
      } catch (_) {}
    } else {
      try {
        await Supabase.instance.client
            .from('user_favourites')
            .delete()
            .eq('user_id', bookmarkUserId)
            .eq('item_id', id);
      } catch (_) {}
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
                            const SizedBox(height: 14),
                          ],
                        )
                      : const SizedBox.shrink(key: ValueKey('checkinEmpty')),
                ),
                // Meds reminder (senior only)
                if (_isSenior && _showMedsReminder) ...[
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
                if (!_hasRealPost && !_sampleBannerDismissed) ...[
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

  Future<void> _dismissSampleBanner() async {
    setState(() {
      _sampleBannerDismissed = true;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sample_banner_dismissed', true);
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
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _dismissSampleBanner,
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(
                Icons.close_rounded,
                color: Color(0xFFB8860B),
                size: 16,
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

  Widget _buildPhoneList() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList(
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
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: MessageCardWidget(
                key: ValueKey(_messages[index].id),
                message: _messages[index],
                isDarkMode: _isDarkMode,
                onHeart: () => _toggleHeart(index),
                isBookmarked: _bookmarkedIds.contains(_messages[index].id),
                onBookmark: () => _toggleBookmark(_messages[index]),
                senderAvatarJson: _messages[index].senderAvatarJson,
              ),
            ),
          );
        }, childCount: _messages.length),
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
        color: const Color(0xFFFAF7F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E0D0), width: 1.5),
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
        color: const Color(0xFFE8E0D0),
        borderRadius: BorderRadius.circular(r),
      ),
    );
  }

  void _showNestSwitcher() {
    // TODO: Replace with Supabase nest list for production
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
                          // Active nest tile
                          _buildNestTile(
                            _nestName,
                            true,
                            onTap: () => Navigator.pop(ctx),
                          ),
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
        Navigator.pushNamed(context, AppRoutes.subscribeNestScreen);
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
