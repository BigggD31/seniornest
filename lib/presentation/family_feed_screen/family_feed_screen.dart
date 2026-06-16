import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/app_navigation.dart';
import '../../routes/app_routes.dart';
import './widgets/feed_empty_state_widget.dart';
import './widgets/feed_top_bar_widget.dart';
import './widgets/im_good_today_orb_widget.dart';
import './widgets/legacy_prompt_card_widget.dart';
import './widgets/meds_reminder_card_widget.dart';
import './widgets/message_card_widget.dart';
import './widgets/celebrations_card_widget.dart';

// ── Data Models ────────────────────────────────────────────────

enum MessageType { text, photo, video, voice }

class MessageModel {
  MessageModel({
    required this.id,
    required this.senderName,
    required this.senderRelationship,
    required this.senderAvatarUrl,
    required this.senderAvatarLabel,
    required this.type,
    required this.content,
    required this.imageUrl,
    required this.imageSemanticLabel,
    required this.timestamp,
    required this.heartCount,
    required this.isHearted,
  });

  final String id;
  final String senderName;
  final String senderRelationship;
  final String senderAvatarUrl;
  final String senderAvatarLabel;
  final MessageType type;
  final String content;
  final String imageUrl;
  final String imageSemanticLabel;
  final DateTime timestamp;
  int heartCount;
  bool isHearted;

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'] as String,
      senderName: map['senderName'] as String,
      senderRelationship: map['senderRelationship'] as String,
      senderAvatarUrl: map['senderAvatarUrl'] as String,
      senderAvatarLabel: map['senderAvatarLabel'] as String,
      type: _messageTypeFromString(map['type'] as String),
      content: map['content'] as String,
      imageUrl: map['imageUrl'] as String,
      imageSemanticLabel: map['imageSemanticLabel'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      heartCount: map['heartCount'] as int,
      isHearted: map['isHearted'] as bool,
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
    'senderAvatarUrl': senderAvatarUrl,
    'senderAvatarLabel': senderAvatarLabel,
    'type': type.name,
    'content': content,
    'imageUrl': imageUrl,
    'imageSemanticLabel': imageSemanticLabel,
    'timestamp': timestamp.toIso8601String(),
    'heartCount': heartCount,
    'isHearted': isHearted,
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
  String _displayName = 'Eleanor';
  String _nestName = '';
  bool _isGoodTodaySent = false;
  bool _showMedsReminder = true;
  bool _showWelcomeToast = false;
  bool _isLoading = true;
  bool _isDarkMode = false;
  bool _hasRealPost = false; // tracks if user has made their first real post
  bool _inviteCodeShared =
      true; // tracks if family owner has shared invite code
  bool _isGuest = false;
  bool _isNestOwner = false;
  List<CelebrationEvent> _todayCelebrations = [];
  List<CelebrationEvent> _upcomingCelebrations = [];

  late AnimationController _listEntranceController;
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
    },
  ];

  List<MessageModel> _messages = [];
  Set<String> _bookmarkedIds = {};

  @override
  void initState() {
    super.initState();
    _listEntranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
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
    final name = prefs.getString('display_name') ?? 'Eleanor';
    final nestName = prefs.getString('nest_name') ?? '';
    final goodToday = prefs.getBool('good_today_${_todayKey()}') ?? false;
    final medsReminder = prefs.getBool('meds_reminder_${_todayKey()}') ?? true;
    final firstLoad = prefs.getBool('first_load') ?? true;
    final darkMode = prefs.getBool('dark_mode') ?? false;
    final hasRealPost = prefs.getBool('has_real_post') ?? false;
    final inviteCodeShared = prefs.getBool('invite_code_shared') ?? false;
    final isGuest = prefs.getBool('is_guest') ?? false;
    final joinedViaInvite = prefs.getBool('joined_via_invite') ?? false;

    if (firstLoad) {
      await prefs.setBool('first_load', false);
    }

    // Load celebrations
    final birthdayStr = prefs.getString('birthday');
    final anniversaryStr = prefs.getString('anniversary');
    DateTime? birthday;
    DateTime? anniversary;
    if (birthdayStr != null) {
      try {
        birthday = DateTime.parse(birthdayStr);
      } catch (_) {}
    }
    if (anniversaryStr != null) {
      try {
        anniversary = DateTime.parse(anniversaryStr);
      } catch (_) {}
    }

    final today = DateTime.now();
    final todayEvents = <CelebrationEvent>[];
    final upcomingEvents = <CelebrationEvent>[];

    void checkEvent(DateTime? date, CelebrationEventType type) {
      if (date == null) return;
      final todayDate = DateTime(today.year, today.month, today.day);
      final thisYear = DateTime(today.year, date.month, date.day);
      final nextYear = DateTime(today.year + 1, date.month, date.day);
      final candidate = thisYear.isBefore(todayDate) ? nextYear : thisYear;
      final diff = candidate.difference(todayDate).inDays;
      final displayName = prefs.getString('display_name') ?? 'You';
      final monthNames = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final dateLabel = '${monthNames[candidate.month - 1]} ${candidate.day}';
      if (diff == 0) {
        todayEvents.add(
          CelebrationEvent(
            name: displayName,
            type: type,
            dateLabel: dateLabel,
            daysUntil: 0,
          ),
        );
      } else if (diff > 0 && diff <= 30) {
        upcomingEvents.add(
          CelebrationEvent(
            name: displayName,
            type: type,
            dateLabel: dateLabel,
            daysUntil: diff,
          ),
        );
      }
    }

    checkEvent(birthday, CelebrationEventType.birthday);
    checkEvent(anniversary, CelebrationEventType.anniversary);
    upcomingEvents.sort((a, b) => a.daysUntil.compareTo(b.daysUntil));

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
      _isNestOwner = !joinedViaInvite;
      // Show demo messages until user has made their first real post
      // After first real post, show only real messages (empty state if none)
      _messages = _messageMaps.map(MessageModel.fromMap).toList(); // placeholder until Supabase loads
      _isLoading = false;
      _todayCelebrations = todayEvents;
      _upcomingCelebrations = upcomingEvents;
    });

    // Load bookmarks
    final bookmarksJson = prefs.getString('bookmarks');
    if (bookmarksJson != null) {
      try {
        final List<dynamic> list = jsonDecode(bookmarksJson) as List<dynamic>;
        setState(() {
          _bookmarkedIds = list.map((e) => e as String).toSet();
        });
      } catch (_) {}
    }

    _setupItemAnimations();
    _listEntranceController.forward();

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

    // Load real feed from Supabase
    await _loadFeedFromSupabase();
  }

  void _setupItemAnimations() {
    _itemAnimations.clear();
    for (int i = 0; i < _messages.length; i++) {
      final start = (i * 0.12).clamp(0.0, 0.7);
      final end = (start + 0.4).clamp(0.0, 1.0);
      _itemAnimations.add(
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _listEntranceController,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          ),
        ),
      );
    }
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}_${now.month}_${now.day}';
  }

  void _showWelcomeMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Welcome back, $_displayName! Your family is thinking of you 💛',
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
    // TODO: Replace with Supabase message send for production
    if (_isGoodTodaySent) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('good_today_${_todayKey()}', true);
    setState(() => _isGoodTodaySent = true);

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

  void _toggleHeart(int index) {
    // TODO: Replace with Supabase hearts update for production
    setState(() {
      final msg = _messages[index];
      if (msg.isHearted) {
        msg.isHearted = false;
        msg.heartCount--;
      } else {
        msg.isHearted = true;
        msg.heartCount++;
      }
    });
  }

  Future<void> _onRefresh() async {
    await _loadData();
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
          .select('*, user_profiles(display_name, avatar_url, relation_type)')
          .eq('nest_id', nestId)
          .order('created_at', ascending: false)
          .limit(50);

      final localName = prefs.getString('display_name') ?? '';
      final posts = response as List<dynamic>;
      final List<MessageModel> loaded = posts.map((post) {
        final profile = post['user_profiles'] as Map<String, dynamic>?;
        final authorId = post['author_id'] as String? ?? '';
        final supabaseName = profile?['display_name'] as String? ?? '';
        final senderName = supabaseName.isNotEmpty
            ? supabaseName
            : (authorId == userId && localName.isNotEmpty ? localName : 'Family');
        final avatarUrl = profile?['avatar_url'] as String? ?? '';
        final relation = profile?['relation_type'] as String? ?? 'Family';
        final type = post['post_type'] as String? ?? 'text';
        return MessageModel(
          id: post['id'] as String,
          senderName: senderName,
          senderRelationship: relation,
          senderAvatarUrl: avatarUrl,
          senderAvatarLabel: senderName,
          type: MessageModel._messageTypeFromString(type),
          content: post['content'] as String? ?? '',
          imageUrl: post['media_url'] as String? ?? '',
          imageSemanticLabel: '',
          timestamp: DateTime.parse(post['created_at'] as String),
          heartCount: 0,
          isHearted: false,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _messages = loaded.isNotEmpty ? loaded : _messageMaps.map(MessageModel.fromMap).toList();
          _hasRealPost = loaded.isNotEmpty;
        });
      }
    } catch (e) {
      debugPrint('Feed load error: $e');
    }
  }

  Future<void> _toggleBookmark(MessageModel msg) async {
    final prefs = await SharedPreferences.getInstance();
    final id = msg.id;
    final isNowBookmarked = !_bookmarkedIds.contains(id);

    setState(() {
      if (isNowBookmarked) {
        _bookmarkedIds.add(id);
      } else {
        _bookmarkedIds.remove(id);
      }
    });

    // Build full bookmarks list from prefs, update this item
    final bookmarksJson = prefs.getString('bookmarks');
    List<String> ids = [];
    if (bookmarksJson != null) {
      try {
        ids = List<String>.from(jsonDecode(bookmarksJson) as List<dynamic>);
      } catch (_) {}
    }
    if (isNowBookmarked) {
      if (!ids.contains(id)) ids.add(id);
    } else {
      ids.remove(id);
    }
    await prefs.setString('bookmarks', jsonEncode(ids));

    // Persist the full bookmark item data for Memories page
    final allItemsJson = prefs.getString('bookmarked_items') ?? '[]';
    List<dynamic> allItems = [];
    try {
      allItems = jsonDecode(allItemsJson) as List<dynamic>;
    } catch (_) {}

    if (isNowBookmarked) {
      // Determine category
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
      };
      allItems.removeWhere((e) => (e as Map<String, dynamic>)['id'] == id);
      allItems.add(item);
    } else {
      allItems.removeWhere((e) => (e as Map<String, dynamic>)['id'] == id);
    }
    await prefs.setString('bookmarked_items', jsonEncode(allItems));
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
      body: SafeArea(
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
      floatingActionButton: _isSenior
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
    if (_isLoading) {
      return _buildLoadingState();
    }

    return RefreshIndicator(
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
              offset: Offset(0, 24 * (1 - anim.value)),
              child: Opacity(opacity: anim.value, child: child),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: MessageCardWidget(
                message: _messages[index],
                isDarkMode: _isDarkMode,
                onHeart: () => _toggleHeart(index),
                isBookmarked: _bookmarkedIds.contains(_messages[index].id),
                onBookmark: () => _toggleBookmark(_messages[index]),
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
              offset: Offset(0, 24 * (1 - anim.value)),
              child: Opacity(opacity: anim.value, child: child),
            ),
            child: MessageCardWidget(
              message: _messages[index],
              isDarkMode: _isDarkMode,
              onHeart: () => _toggleHeart(index),
              isBookmarked: _bookmarkedIds.contains(_messages[index].id),
              onBookmark: () => _toggleBookmark(_messages[index]),
            ),
          );
        }, childCount: _messages.length),
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
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
