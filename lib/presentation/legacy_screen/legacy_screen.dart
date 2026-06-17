import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/app_navigation.dart';
import '../../widgets/share_preview_widget.dart';
import '../../widgets/fullscreen_media_viewer.dart';
import '../profile_photo_picker_screen/profile_photo_picker_screen.dart';

class LegacyScreen extends StatefulWidget {
  const LegacyScreen({super.key});

  @override
  State<LegacyScreen> createState() => _LegacyScreenState();
}

class _LegacyScreenState extends State<LegacyScreen>
    with TickerProviderStateMixin {
  int _currentNavIndex = 2;
  bool _isSenior = false;
  bool _isDarkMode = false;
  bool _isLoading = true;
  int _selectedCategory = 0;
  bool _hasSentStories = false; // hides placeholder once first story saved

  // Family-submitted story prompts (persisted via SharedPreferences)
  List<String> _submittedPrompts = [];

  late AnimationController _entranceController;
  late List<Animation<double>> _itemAnimations;

  static const List<String> _categories = [
    'All',
    'Memories',
    'Wisdom',
    'Family',
    'Life Lessons',
  ];

  static const List<Map<String, dynamic>> _mockStories = [
    {
      'id': 's1',
      'title': 'The Summer We Built the Treehouse',
      'excerpt':
          'It was 1972, and your grandfather had just bought a pile of old lumber from the neighbor\'s barn...',
      'category': 'Memories',
      'date': '2026-03-20',
      'imageUrl':
          'https://images.pexels.com/photos/1648387/pexels-photo-1648387.jpeg',
      'imageLabel':
          'Old wooden treehouse in a large oak tree, summer afternoon',
      'heartCount': 12,
      'isHearted': true,
      'isOwn': true,
    },
    {
      'id': 's2',
      'title': 'What My Mother Taught Me About Kindness',
      'excerpt':
          'She never had much, but she always had enough to share. Every Sunday she would bake extra bread...',
      'category': 'Wisdom',
      'date': '2026-03-15',
      'imageUrl': '',
      'imageLabel': '',
      'heartCount': 8,
      'isHearted': false,
      'isOwn': true,
    },
    {
      'id': 's3',
      'title': 'Our First Family Vacation',
      'excerpt':
          'We drove all the way to the coast in that old station wagon. The kids were fighting in the back seat...',
      'category': 'Family',
      'date': '2026-03-10',
      'imageUrl':
          'https://images.unsplash.com/photo-1495706399573-db6a62f0f770',
      'imageLabel':
          'Coastal road with ocean view, vintage family vacation setting',
      'heartCount': 15,
      'isHearted': true,
      'isOwn': true,
    },
    {
      'id': 's4',
      'title': 'The Lesson That Changed Everything',
      'excerpt':
          'My first boss told me something I\'ve never forgotten: "Always leave a place better than you found it."',
      'category': 'Life Lessons',
      'date': '2026-03-05',
      'imageUrl': '',
      'imageLabel': '',
      'heartCount': 6,
      'isHearted': false,
      'isOwn': true,
    },
  ];

  static const List<Map<String, String>> _prompts = [
    {
      'prompt':
          'What\'s your favorite family tradition you\'d love to pass down?',
      'icon': '🏡',
    },
    {
      'prompt':
          'Tell us about a moment when you truly felt proud of yourself or your family.',
      'icon': '⭐',
    },
    {
      'prompt':
          'What piece of wisdom do you wish someone had told you when you were young?',
      'icon': '💌',
    },
    {
      'prompt':
          'Share a memory from your childhood that still makes you smile today.',
      'icon': '🌟',
    },
    {
      'prompt':
          'What does "home" mean to you, and what made your home special?',
      'icon': '🕊️',
    },
    {
      'prompt':
          'Share a recipe, skill, or tradition that was passed down to you.',
      'icon': '🍞',
    },
    {
      'prompt':
          'Tell us about a person who shaped who you are — a parent, teacher, or friend.',
      'icon': '🤝',
    },
    {
      'prompt': 'What was the world like when you were raising your children?',
      'icon': '👨‍👩‍👧',
    },
    {
      'prompt': 'Describe a challenge you overcame that you are most proud of.',
      'icon': '💪',
    },
    {
      'prompt':
          'What simple pleasures in life have brought you the most joy over the years?',
      'icon': '☀️',
    },
  ];

  // Mock family-submitted prompts (shown in "From Your Family" section)
  static const List<Map<String, String>> _familyPrompts = [
    {
      'prompt': 'Grandma, what was your wedding day like?',
      'from': 'From Sarah',
      'icon': '💍',
    },
    {
      'prompt': 'Tell us about the neighborhood you grew up in.',
      'from': 'From Michael',
      'icon': '🏘️',
    },
  ];

  List<Map<String, dynamic>> _stories = [];

  Map<String, dynamic>? _profileData;
  String _displayName = '';

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _itemAnimations = [];
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.delayed(const Duration(milliseconds: 400));
    final profileJson = prefs.getString(kProfilePhotoKey);
    Map<String, dynamic>? profileData;
    if (profileJson != null) {
      try {
        profileData = jsonDecode(profileJson) as Map<String, dynamic>;
      } catch (_) {}
    }
    // Load persisted story prompts
    final promptsJson = prefs.getString('story_prompts');
    List<String> loadedPrompts = [];
    if (promptsJson != null) {
      try {
        loadedPrompts = List<String>.from(jsonDecode(promptsJson) as List);
      } catch (_) {}
    }
    // Load bookmark state for stories
    final bookmarksJson = prefs.getString('bookmarks');
    Set<String> bookmarkedIds = {};
    if (bookmarksJson != null) {
      try {
        bookmarkedIds = Set<String>.from(
          jsonDecode(bookmarksJson) as List<dynamic>,
        );
      } catch (_) {}
    }

    // Load real stories from Supabase BEFORE setState
    List<Map<String, dynamic>> realStories = [];
    try {
      final supabase = Supabase.instance.client;
      String? userId = supabase.auth.currentUser?.id;
      if (userId == null) userId = supabase.auth.currentSession?.user.id;
      if (userId != null) {
        final response = await supabase
            .from('legacy_entries')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false);
        final entries = response as List<dynamic>;
        realStories = entries.map((e) => <String, dynamic>{
          'id': e['id'],
          'title': e['prompt'] ?? 'My Story',
          'excerpt': e['content'] ?? '',
          'category': 'Memories',
          'date': e['created_at']?.toString().substring(0, 10) ?? '',
          'entry_type': e['entry_type'] ?? 'text',
          'media_url': e['media_url'] ?? '',
          'isBookmarked': bookmarkedIds.contains(e['id'] as String),
        }).toList();
      }
    } catch (e) {
      print('LEGACY LOAD ERROR: $e');
    }

    setState(() {
      _isSenior = (prefs.getString('user_role') ?? 'senior') == 'senior';
      _isDarkMode = prefs.getBool('dark_mode') ?? false;
      _hasSentStories = prefs.getBool('has_sent_stories') ?? false;

      // Show real stories if any exist, otherwise show mock placeholders
      _stories = realStories.isNotEmpty
          ? realStories
          : _mockStories.map((s) {
              final m = Map<String, dynamic>.from(s);
              m['isBookmarked'] = bookmarkedIds.contains(m['id'] as String);
              return m;
            }).toList();
      _submittedPrompts = loadedPrompts;
      _isLoading = false;
      _profileData = profileData;
      _displayName = prefs.getString('display_name') ?? '';
    });
    _setupAnimations();
    _entranceController.forward();
  }

  void _setupAnimations() {
    _itemAnimations.clear();
    for (int i = 0; i < _stories.length + _prompts.length + 2; i++) {
      final start = (i * 0.1).clamp(0.0, 0.7);
      final end = (start + 0.4).clamp(0.0, 1.0);
      _itemAnimations.add(
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Color get _bg =>
      _isDarkMode ? const Color(0xFF1A1612) : const Color(0xFFFDFDFD);
  Color get _surface =>
      _isDarkMode ? const Color(0xFF242018) : const Color(0xFFF5F0E8);
  Color get _cardBg =>
      _isDarkMode ? const Color(0xFF242018) : const Color(0xFFFAF7F2);
  Color get _cardBorder =>
      _isDarkMode ? const Color(0xFF3D3428) : const Color(0xFFE8E0D0);
  Color get _textPrimary =>
      _isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      _isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  List<Map<String, dynamic>> get _filteredStories {
    if (_selectedCategory == 0) return _stories;
    final cat = _categories[_selectedCategory];
    return _stories.where((s) => s['category'] == cat).toList();
  }

  void _toggleHeart(int index) {
    setState(() {
      final story = _filteredStories[index];
      final globalIndex = _stories.indexWhere((s) => s['id'] == story['id']);
      if (globalIndex >= 0) {
        final isHearted = _stories[globalIndex]['isHearted'] as bool? ?? false;
        final heartCount = _stories[globalIndex]['heartCount'] as int? ?? 0;
        if (isHearted) {
          _stories[globalIndex]['isHearted'] = false;
          _stories[globalIndex]['heartCount'] = heartCount - 1;
        } else {
          _stories[globalIndex]['isHearted'] = true;
          _stories[globalIndex]['heartCount'] = heartCount + 1;
        }
      }
    });
  }

  Future<void> _toggleStoryBookmark(Map<String, dynamic> story) async {
    final id = story['id'] as String;
    final isNowBookmarked = !(story['isBookmarked'] as bool? ?? false);
    final globalIndex = _stories.indexWhere((s) => s['id'] == id);
    if (globalIndex >= 0) {
      setState(() {
        _stories[globalIndex]['isBookmarked'] = isNowBookmarked;
      });
    }

    final prefs = await SharedPreferences.getInstance();

    // Update bookmarked IDs list
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

    // Persist full item data for Memories page
    final allItemsJson = prefs.getString('bookmarked_items') ?? '[]';
    List<dynamic> allItems = [];
    try {
      allItems = jsonDecode(allItemsJson) as List<dynamic>;
    } catch (_) {}

    if (isNowBookmarked) {
      final item = {
        'id': id,
        'category': 'Text',
        'senderName': 'Legacy Story',
        'senderRelationship': story['category'] as String? ?? 'Story',
        'senderAvatarUrl': '',
        'senderAvatarLabel': '',
        'content': '${story['title']}\n\n${story['excerpt']}',
        'imageUrl': story['imageUrl'] as String? ?? '',
        'imageSemanticLabel': story['imageLabel'] as String? ?? '',
        'timestamp': DateTime.now().toIso8601String(),
        'sourceType': 'story',
        'storyTitle': story['title'] as String? ?? '',
        'storyCategory': story['category'] as String? ?? '',
      };
      allItems.removeWhere((e) => (e as Map<String, dynamic>)['id'] == id);
      allItems.add(item);
    } else {
      allItems.removeWhere((e) => (e as Map<String, dynamic>)['id'] == id);
    }
    await prefs.setString('bookmarked_items', jsonEncode(allItems));
  }

  void _onNavTap(int index) {
    if (index == _currentNavIndex) return;
    setState(() => _currentNavIndex = index);
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/family-feed-screen');
        break;
      case 1:
        Navigator.pushReplacementNamed(context, '/send-screen');
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
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(isTablet),
            Expanded(
              child: _isLoading
                  ? _buildLoadingState()
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      color: const Color(0xFF5DA399),
                      backgroundColor: _bg,
                      child: CustomScrollView(
                        slivers: [
                          // Senior: big Write Your Story hero button
                          if (_isSenior)
                            SliverToBoxAdapter(
                              child: _buildSeniorWriteHero(isTablet),
                            ),
                          // Family: read-only banner + suggest question button
                          if (!_isSenior)
                            SliverToBoxAdapter(
                              child: _buildFamilyReadOnlyBanner(isTablet),
                            ),
                          // Family: suggest prompt button above category tabs
                          if (!_isSenior)
                            SliverToBoxAdapter(
                              child: _buildFamilySuggestButton(isTablet),
                            ),
                          SliverToBoxAdapter(
                            child: _buildCategoryChips(isTablet),
                          ),
                          SliverToBoxAdapter(
                            child: _buildStoriesWantToHear(isTablet),
                          ),
                          if (_isSenior) ...[
                            SliverToBoxAdapter(
                              child: _buildPromptSection(isTablet),
                            ),
                          ],
                          _filteredStories.isEmpty
                              ? SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: _buildEmptyState(),
                                )
                              : SliverList(
                                  delegate: SliverChildBuilderDelegate((
                                    context,
                                    index,
                                  ) {
                                    final animIndex =
                                        index +
                                        (_isSenior ? _prompts.length : 0);
                                    final anim =
                                        animIndex < _itemAnimations.length
                                        ? _itemAnimations[animIndex]
                                        : const AlwaysStoppedAnimation(1.0);
                                    return AnimatedBuilder(
                                      animation: anim,
                                      builder: (context, child) => Opacity(
                                        opacity: anim.value,
                                        child: Transform.translate(
                                          offset: Offset(
                                            0,
                                            20 * (1 - anim.value),
                                          ),
                                          child: child,
                                        ),
                                      ),
                                      child: _buildStoryCard(
                                        _filteredStories[index],
                                        index,
                                        isTablet,
                                      ),
                                    );
                                  }, childCount: _filteredStories.length),
                                ),
                          const SliverPadding(
                            padding: EdgeInsets.only(bottom: 100),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppNavigation(
        currentIndex: _currentNavIndex,
        onTap: _onNavTap,
      ),
    );
  }

  // ── Senior: Big prominent "Tell Your Story" hero ──────────────────────────
  Widget _buildSeniorWriteHero(bool isTablet) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 28 : 20,
        16,
        isTablet ? 28 : 20,
        24,
      ),
      child: GestureDetector(
        onTap: () => _showTellYourStoryOptions(),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF5DA399), Color(0xFF4A8A82)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF5DA399).withAlpha(60),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(40),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tell Your Story',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Your memories deserve to be preserved ✨',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 13,
                        color: Colors.white.withAlpha(210),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Family: read-only banner + suggest question ────────────────────────────
  Widget _buildFamilyReadOnlyBanner(bool isTablet) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 28 : 20,
        16,
        isTablet ? 28 : 20,
        0,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFD4AA00).withAlpha(18),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFD4AA00).withAlpha(70),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            const Text('📖', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Eleanor\'s Legacy Stories',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'These are her stories to treasure and share.',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 12,
                      color: _textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Family: centered "Suggest a Story Prompt" button above category tabs ───
  Widget _buildFamilySuggestButton(bool isTablet) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 28 : 20,
        12,
        isTablet ? 28 : 20,
        18,
      ),
      child: Center(
        child: GestureDetector(
          onTap: () => _showSuggestQuestionSheet(),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F4ED),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF5DA399).withAlpha(100),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF5DA399).withAlpha(55),
                  blurRadius: 14,
                  spreadRadius: 1,
                  offset: const Offset(0, 3),
                ),
                BoxShadow(
                  color: const Color(0xFF5DA399).withAlpha(25),
                  blurRadius: 28,
                  spreadRadius: 4,
                  offset: const Offset(0, 0),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lightbulb_outline_rounded,
                  color: Color(0xFF5DA399),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Suggest a Story Prompt',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF5DA399),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isTablet) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 28 : 20,
        vertical: 14,
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Legacy Stories',
                style: GoogleFonts.nunitoSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                ),
              ),
              Text(
                _isSenior
                    ? 'Your stories, preserved forever'
                    : 'Stories from your loved one',
                style: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  color: _textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          ProfileAvatarWidget(
            profileData: _profileData,
            displayName: _displayName,
            size: 40,
            borderColor: const Color(0xFF5DA399),
            borderWidth: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips(bool isTablet) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: isTablet ? 28 : 20),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedCategory == index;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF5DA399) : _surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? const Color(0xFF5DA399) : _cardBorder,
                  width: 1.5,
                ),
              ),
              child: Text(
                _categories[index],
                style: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : _textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPromptSection(bool isTablet) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 28 : 20,
        20,
        isTablet ? 28 : 20,
        12,
      ),
      child: Row(
        children: [
          Text(
            _selectedCategory == 0
                ? 'All Stories'
                : _categories[_selectedCategory],
            style: GoogleFonts.nunitoSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const Spacer(),
          Text(
            '${_filteredStories.length} stories',
            style: GoogleFonts.nunitoSans(fontSize: 13, color: _textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildStoriesWantToHear(bool isTablet) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 28 : 20,
        20,
        isTablet ? 28 : 20,
        4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💌', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                'Stories They Want to Hear',
                style: GoogleFonts.nunitoSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_submittedPrompts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _cardBorder, width: 1.5),
              ),
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF5DA399).withAlpha(20),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.question_answer_outlined,
                      color: Color(0xFF5DA399),
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No story requests yet',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'When family members request a story,\nit will appear here.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      color: _textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: _submittedPrompts.map((prompt) {
                final cardContent = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AA00).withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text('💌', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        prompt,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                          height: 1.5,
                        ),
                      ),
                    ),
                    if (_isSenior) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF5DA399).withAlpha(20),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF5DA399).withAlpha(80),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          'Answer',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF5DA399),
                          ),
                        ),
                      ),
                    ],
                  ],
                );

                if (_isSenior) {
                  return GestureDetector(
                    onTap: () => _answerPrompt(prompt),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 18,
                      ),
                      decoration: BoxDecoration(
                        color: _cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF5DA399).withAlpha(80),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF5DA399).withAlpha(18),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: cardContent,
                    ),
                  );
                } else {
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 18,
                    ),
                    decoration: BoxDecoration(
                      color: _cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _cardBorder, width: 1.5),
                    ),
                    child: cardContent,
                  );
                }
              }).toList(),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildStoryCard(Map<String, dynamic> story, int index, bool isTablet) {
    return _LegacyStoryCard(
      story: story,
      index: index,
      isTablet: isTablet,
      isDarkMode: _isDarkMode,
      isSenior: _isSenior,
      profileData: _profileData,
      displayName: _displayName,
      onHeart: () => _toggleHeart(index),
      onBookmark: () => _toggleStoryBookmark(story),
      onShare: () => SharePreviewWidget.show(
        context,
        title: story['title'] as String,
        body: story['excerpt'] as String,
        imageUrl: story['imageUrl'] as String?,
        isDarkMode: _isDarkMode,
      ),
      onTap: () => _showStoryDetail(story), //
    );
  }

  Widget _buildStoryCardContent(Map<String, dynamic> story, int index, bool isTablet) {
    final hasImage = (story['imageUrl'] as String? ?? '').isNotEmpty;
    final isHearted = story['isHearted'] as bool? ?? false;
    final heartCount = story['heartCount'] as int? ?? 0;

    return Container(
      margin: EdgeInsets.fromLTRB(
        isTablet ? 28 : 20,
        0,
        isTablet ? 28 : 20,
        14,
      ),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder, width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14.5),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showStoryDetail(story),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasImage)
                  GestureDetector(
                    onTap: () => openFullscreenImage(
                      context: context,
                      imageUrl: story['imageUrl'] as String? ?? '',
                      semanticLabel: story['imageLabel'] as String? ?? '',
                      isDarkMode: _isDarkMode,
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(14),
                      ),
                      child: Stack(
                        children: [
                          Image.network(
                            story['imageUrl'] as String? ?? '',
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            semanticLabel: story['imageLabel'] as String? ?? '',
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(120),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.fullscreen_rounded,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  SizedBox(width: 3),
                                  Text(
                                    'Tap to expand',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF5DA399).withAlpha(20),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              story['category'] as String,
                              style: GoogleFonts.nunitoSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF5DA399),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _formatDate(story['date'] as String),
                            style: GoogleFonts.nunitoSans(
                              fontSize: 12,
                              color: _textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        story['title'] as String,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      if ((story['entry_type'] as String? ?? 'text') == 'audio' &&
                          (story['media_url'] as String? ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _LegacyAudioPlayer(
                            audioUrl: story['media_url'] as String,
                            isDarkMode: _isDarkMode,
                          ),
                        )
                      else if ((story['entry_type'] as String? ?? 'text') == 'video' &&
                          (story['media_url'] as String? ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _LegacyVideoCardPlayer(
                            videoUrl: story['media_url'] as String,
                            isDarkMode: _isDarkMode,
                          ),
                        )
                      else
                        Text(
                          story['excerpt'] as String,
                          style: GoogleFonts.nunitoSans(
                            fontSize: 14,
                            color: _textSecondary,
                            height: 1.5,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          // Heart button — uses IconButton for reliable tap handling
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 36,
                                height: 36,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 36,
                                    minHeight: 36,
                                  ),
                                  icon: Icon(
                                    isHearted
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_outline_rounded,
                                    color: isHearted
                                        ? const Color(0xFFE05C5C)
                                        : _textSecondary,
                                    size: 22,
                                  ),
                                  onPressed: () => _toggleHeart(index),
                                ),
                              ),
                              Text(
                                '$heartCount',
                                style: GoogleFonts.nunitoSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isHearted
                                      ? const Color(0xFFD4AA00)
                                      : _textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          // Bookmark button
                          GestureDetector(
                            onTap: () => _toggleStoryBookmark(story),
                            child: Icon(
                              (story['isBookmarked'] as bool? ?? false)
                                  ? Icons.bookmark_rounded
                                  : Icons.bookmark_outline_rounded,
                              size: 22,
                              color: (story['isBookmarked'] as bool? ?? false)
                                  ? const Color(0xFF5DA399)
                                  : _textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Share Story button
                          GestureDetector(
                            onTap: () => SharePreviewWidget.show(
                              context,
                              title: story['title'] as String,
                              body: story['excerpt'] as String,
                              imageUrl: story['imageUrl'] as String?,
                              isDarkMode: _isDarkMode,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD4AA00).withAlpha(18),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFD4AA00).withAlpha(60),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.ios_share_rounded,
                                    size: 14,
                                    color: Color(0xFFD4AA00),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Share Story',
                                    style: GoogleFonts.nunitoSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFFD4AA00),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    final months = [
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
    return '${months[date.month - 1]} ${date.day}';
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📖', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              _hasSentStories
                  ? (_isSenior
                        ? 'No stories in this category yet'
                        : 'No stories in this category yet')
                  : (_isSenior
                        ? 'Your stories are waiting to be told ✨'
                        : 'No stories yet'),
              style: GoogleFonts.nunitoSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _hasSentStories ? _textPrimary : const Color(0xFFD4AA00),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _hasSentStories
                  ? (_isSenior
                        ? 'Tap "Tell Your Story" above to begin'
                        : 'Check back soon for new stories')
                  : (_isSenior
                        ? 'Tap "Tell Your Story" above to share your first memory with your family 🌿'
                        : 'Check back soon — your loved one\'s stories will appear here 🌿'),
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                color: _textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 3,
      itemBuilder: (context, index) => Container(
        height: 200,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  void _showTellYourStoryOptions({String? prompt}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: _TellYourStoryOptionsSheet(
          isDarkMode: _isDarkMode,
          onWriteStory: () {
            Navigator.pop(ctx);
            _showWriteStorySheet(prompt);
          },
          onRecordVoice: () {
            Navigator.pop(ctx);
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (ctx2) =>
                  _LegacyVoiceRecordSheet(
                    isDarkMode: _isDarkMode,
                    onRecordingComplete: _loadData,
                  ),
            );
          },
          onRecordVideo: () {
            Navigator.pop(ctx);
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (ctx2) =>
                  _LegacyVideoRecordSheet(
                    isDarkMode: _isDarkMode,
                    onRecordingComplete: _loadData,
                  ),
            );
          },
        ),
      ),
    );
  }

  void _showWriteStorySheet(String? prompt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) =>
          _WriteStorySheet(prompt: prompt, isDarkMode: _isDarkMode, onStorySaved: _loadData),
    );
  }

  void _showStoryDetail(Map<String, dynamic> story) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _StoryDetailSheet(
        story: story,
        isDarkMode: _isDarkMode,
        isSenior: _isSenior,
      ),
    );
  }

  void _showSuggestQuestionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SuggestQuestionSheet(
        isDarkMode: _isDarkMode,
        onPromptSubmitted: (prompt) async {
          final prefs = await SharedPreferences.getInstance();
          final updated = [prompt, ..._submittedPrompts];
          await prefs.setString('story_prompts', jsonEncode(updated));
          if (mounted) {
            setState(() {
              _submittedPrompts = updated;
            });
          }
        },
      ),
    );
  }

  void _answerPrompt(String prompt) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: _AnswerPromptSheet(
          prompt: prompt,
          isDarkMode: _isDarkMode,
          onWriteAnswer: () {
            Navigator.pop(ctx);
            _showAnswerWriteSheet(prompt);
          },
          onRecordVoice: () {
            Navigator.pop(ctx);
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (ctx2) => _LegacyVoiceRecordSheet(
                isDarkMode: _isDarkMode,
                onRecordingComplete: () => _removeAnsweredPrompt(prompt),
              ),
            );
          },
          onRecordVideo: () {
            Navigator.pop(ctx);
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (ctx2) => _LegacyVideoRecordSheet(
                isDarkMode: _isDarkMode,
                onRecordingComplete: () => _removeAnsweredPrompt(prompt),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showAnswerWriteSheet(String prompt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _WriteStorySheet(
        prompt: prompt,
        isDarkMode: _isDarkMode,
        onStorySaved: () => _removeAnsweredPrompt(prompt),
      ),
    );
  }

  Future<void> _removeAnsweredPrompt(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = _submittedPrompts.where((p) => p != prompt).toList();
    await prefs.setString('story_prompts', jsonEncode(updated));
    // Add a completed story to the stories list
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final newStory = {
      'id': 'story_${now.millisecondsSinceEpoch}',
      'title': prompt.length > 60 ? '${prompt.substring(0, 57)}...' : prompt,
      'excerpt': 'A story shared in response to a family request.',
      'category': _categorizePropmt(prompt),
      'date': dateStr,
      'imageUrl': '',
      'imageLabel': '',
      'heartCount': 0,
      'isHearted': false,
      'isOwn': true,
    };
    if (mounted) {
      setState(() {
        _submittedPrompts = updated;
        _hasSentStories = true;
      });
      // Reload stories from Supabase
      _loadData();
    }
  }

  String _categorizePropmt(String prompt) {
    final lower = prompt.toLowerCase();
    if (lower.contains('family') ||
        lower.contains('child') ||
        lower.contains('son') ||
        lower.contains('daughter') ||
        lower.contains('grandchild') ||
        lower.contains('married') ||
        lower.contains('wedding') ||
        lower.contains('vacation') ||
        lower.contains('tradition')) {
      return 'Family';
    } else if (lower.contains('wisdom') ||
        lower.contains('advice') ||
        lower.contains('lesson') ||
        lower.contains('learn') ||
        lower.contains('taught') ||
        lower.contains('teach') ||
        lower.contains('best advice') ||
        lower.contains('changed')) {
      return 'Life Lessons';
    } else if (lower.contains('childhood') ||
        lower.contains('grew up') ||
        lower.contains('young') ||
        lower.contains('memory') ||
        lower.contains('remember') ||
        lower.contains('neighborhood') ||
        lower.contains('game') ||
        lower.contains('school')) {
      return 'Memories';
    } else {
      return 'Wisdom';
    }
  }
}

// ── Tell Your Story Options Sheet ─────────────────────────────────────────────
class _TellYourStoryOptionsSheet extends StatelessWidget {
  const _TellYourStoryOptionsSheet({
    required this.isDarkMode,
    required this.onWriteStory,
    required this.onRecordVoice,
    required this.onRecordVideo,
  });
  final bool isDarkMode;
  final VoidCallback onWriteStory;
  final VoidCallback onRecordVoice;
  final VoidCallback onRecordVideo;

  Color get _bg =>
      isDarkMode ? const Color(0xFF242018) : const Color(0xFFFDFDFD);
  Color get _textPrimary =>
      isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);
  Color get _surface =>
      isDarkMode ? const Color(0xFF2E2820) : const Color(0xFFF5F0E8);
  Color get _cardBorder =>
      isDarkMode ? const Color(0xFF3D3428) : const Color(0xFFE8E0D0);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'How would you like to share?',
                style: GoogleFonts.nunitoSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose the way that feels most comfortable for you',
                style: GoogleFonts.nunitoSans(
                  fontSize: 14,
                  color: _textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              _buildOption(
                emoji: '📝',
                label: 'Write My Story',
                description: 'Type your story at your own pace',
                onTap: onWriteStory,
              ),
              const SizedBox(height: 12),
              _buildOption(
                emoji: '🎤',
                label: 'Record My Voice',
                description:
                    'Speak your story — we\'ll save it for your family',
                onTap: onRecordVoice,
              ),
              const SizedBox(height: 12),
              _buildOption(
                emoji: '📹',
                label: 'Record Video',
                description: 'Share your story face to face',
                onTap: onRecordVideo,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOption({
    required String emoji,
    required String label,
    required String description,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _cardBorder, width: 1.5),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      color: _textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: _textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Write Story Sheet (Senior only) ───────────────────────────────────────────
class _WriteStorySheet extends StatefulWidget {
  const _WriteStorySheet({
    this.prompt,
    required this.isDarkMode,
    this.onStorySaved,
  });
  final String? prompt;
  final bool isDarkMode;
  final VoidCallback? onStorySaved;

  @override
  State<_WriteStorySheet> createState() => _WriteStorySheetState();
}

class _WriteStorySheetState extends State<_WriteStorySheet> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  String _selectedCategory = 'Memories';
  bool _isSaving = false;

  static const List<String> _categories = [
    'Memories',
    'Wisdom',
    'Family',
    'Life Lessons',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.prompt != null) {
      _bodyController.text = '${widget.prompt}\n\n';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Color get _bg =>
      widget.isDarkMode ? const Color(0xFF242018) : const Color(0xFFFDFDFD);
  Color get _textPrimary =>
      widget.isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      widget.isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  Future<void> _saveStory() async {
    if (_bodyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please write your story before saving.',
            style: GoogleFonts.nunitoSans(fontSize: 14, color: Colors.white),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _isSaving = true);

    final title = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : (widget.prompt ?? 'My Story');

    try {
      final supabase = Supabase.instance.client;
      String? userId = supabase.auth.currentUser?.id;
      if (userId == null) userId = supabase.auth.currentSession?.user.id;
      final prefs = await SharedPreferences.getInstance();
      final nestId = prefs.getString('nest_id') ?? '';

      if (userId != null) {
        await supabase.from('legacy_entries').insert({
          'user_id': userId,
          'nest_id': nestId.isEmpty ? null : nestId,
          'prompt': title,
          'content': _bodyController.text.trim(),
          'entry_type': 'text',
          'is_custom': true,
        });
        await prefs.setBool('has_sent_stories', true);
        print('LEGACY: story saved successfully');
      }
    } catch (e) {
      print('LEGACY SAVE ERROR: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save error: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 8)),
        );
      }
      return;
    }

    if (mounted) {
      Navigator.pop(context);
      widget.onStorySaved?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Your story has been saved! 📖',
            style: GoogleFonts.nunitoSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF5DA399),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding =
        MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    final Color sectionBg = widget.isDarkMode
        ? const Color(0xFF2E2820)
        : const Color(0xFFF7F3EE);
    final Color sectionBorder = widget.isDarkMode
        ? const Color(0xFF3D3528)
        : const Color(0xFFE8E0D0);
    final Color labelColor = widget.isDarkMode
        ? const Color(0xFF9A8A72)
        : const Color(0xFF8A7A6A);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                Text(
                  'Write Your Story',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(
                    Icons.close_rounded,
                    color: _textSecondary,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // ── Scrollable body ─────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Section 1: Story Title ─────────────────────────────────
                  Text(
                    'Story Title',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: labelColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: sectionBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: sectionBorder, width: 1),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    child: TextField(
                      controller: _titleController,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Give your story a title…',
                        hintStyle: GoogleFonts.nunitoSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: widget.isDarkMode
                              ? const Color(0xFF6B5E4E)
                              : const Color(0xFFBBAA96),
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // ── Section 2: Category ────────────────────────────────────
                  Text(
                    'Choose a category',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: labelColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: sectionBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: sectionBorder, width: 1),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    child: Row(
                      children: _categories.map((cat) {
                        final isSelected = _selectedCategory == cat;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _selectedCategory = cat),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: EdgeInsets.only(
                                right: cat != _categories.last ? 6 : 0,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF5DA399).withAlpha(26)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF5DA399)
                                      : sectionBorder,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                cat,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.nunitoSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? const Color(0xFF5DA399)
                                      : _textSecondary,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // ── Section 3: Story Body ──────────────────────────────────
                  Text(
                    'Your Story',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: labelColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: sectionBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: sectionBorder, width: 1),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    child: TextField(
                      controller: _bodyController,
                      maxLines: null,
                      minLines: 8,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 16,
                        color: _textPrimary,
                        height: 1.7,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Begin your story here…',
                        hintStyle: GoogleFonts.nunitoSans(
                          fontSize: 16,
                          color: widget.isDarkMode
                              ? const Color(0xFF6B5E4E)
                              : const Color(0xFFA8A090),
                          height: 1.7,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Save Button ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveStory,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5DA399),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Save Story',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  }
}

// ── Answer Prompt Sheet (Senior only) ─────────────────────────────────────────
class _AnswerPromptSheet extends StatelessWidget {
  const _AnswerPromptSheet({
    required this.prompt,
    required this.isDarkMode,
    required this.onWriteAnswer,
    required this.onRecordVoice,
    required this.onRecordVideo,
  });
  final String prompt;
  final bool isDarkMode;
  final VoidCallback onWriteAnswer;
  final VoidCallback onRecordVoice;
  final VoidCallback onRecordVideo;

  Color get _bg =>
      isDarkMode ? const Color(0xFF242018) : const Color(0xFFFDFDFD);
  Color get _textPrimary =>
      isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);
  Color get _surface =>
      isDarkMode ? const Color(0xFF2E2820) : const Color(0xFFF5F0E8);
  Color get _cardBorder =>
      isDarkMode ? const Color(0xFF3D3428) : const Color(0xFFE8E0D0);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              // Prompt display
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AA00).withAlpha(15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFD4AA00).withAlpha(60),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('💌', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        prompt,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'How would you like to answer?',
                style: GoogleFonts.nunitoSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose the way that feels most comfortable for you',
                style: GoogleFonts.nunitoSans(
                  fontSize: 14,
                  color: _textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              _buildOption(
                emoji: '📝',
                label: 'Write My Answer',
                description: 'Type your story at your own pace',
                onTap: onWriteAnswer,
              ),
              const SizedBox(height: 12),
              _buildOption(
                emoji: '🎤',
                label: 'Record My Voice',
                description:
                    'Speak your answer — your family will treasure hearing your voice',
                onTap: onRecordVoice,
              ),
              const SizedBox(height: 12),
              _buildOption(
                emoji: '📹',
                label: 'Record Video',
                description: 'Share your answer face to face',
                onTap: onRecordVideo,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOption({
    required String emoji,
    required String label,
    required String description,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _cardBorder, width: 1.5),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      color: _textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: _textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Suggest Question Sheet (Family only) ──────────────────────────────────────
class _SuggestQuestionSheet extends StatefulWidget {
  const _SuggestQuestionSheet({
    required this.isDarkMode,
    required this.onPromptSubmitted,
  });
  final bool isDarkMode;
  final Future<void> Function(String prompt) onPromptSubmitted;

  @override
  State<_SuggestQuestionSheet> createState() => _SuggestQuestionSheetState();
}

class _SuggestQuestionSheetState extends State<_SuggestQuestionSheet> {
  final TextEditingController _questionController = TextEditingController();
  bool _isSending = false;

  static const List<String> _suggestions = [
    'What was your favorite childhood game?',
    'Tell us about the day you got married.',
    'What was your first job like?',
    'What\'s the best advice you ever received?',
    'Describe a moment that changed your life.',
  ];

  Color get _bg =>
      widget.isDarkMode ? const Color(0xFF242018) : const Color(0xFFFDFDFD);
  Color get _textPrimary =>
      widget.isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      widget.isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _sendSuggestion() async {
    if (_questionController.text.trim().isEmpty) return;
    setState(() => _isSending = true);
    final prompt = _questionController.text.trim();
    await widget.onPromptSubmitted(prompt);
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Your question suggestion was sent! 💛',
            style: GoogleFonts.nunitoSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF5DA399),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                Text(
                  'Suggest a Story Prompt',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(
                    Icons.close_rounded,
                    color: _textSecondary,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(
              'Ask your loved one to share a story about something special.',
              style: GoogleFonts.nunitoSans(
                fontSize: 13,
                color: _textSecondary,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick suggestions:',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._suggestions.map(
                    (s) => GestureDetector(
                      onTap: () => setState(() => _questionController.text = s),
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF5DA399).withAlpha(12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF5DA399).withAlpha(50),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          s,
                          style: GoogleFonts.nunitoSans(
                            fontSize: 13,
                            color: _textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Or write your own:',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _questionController,
                    maxLines: 3,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 15,
                      color: _textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Ask something meaningful...',
                      hintStyle: GoogleFonts.nunitoSans(
                        fontSize: 15,
                        color: widget.isDarkMode
                            ? const Color(0xFF6B5E4E)
                            : const Color(0xFFA8A090),
                      ),
                      filled: true,
                      fillColor: widget.isDarkMode
                          ? const Color(0xFF2E2820)
                          : const Color(0xFFF5F0E8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSending ? null : _sendSuggestion,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5DA399),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Send Suggestion 💛',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Story Detail Sheet ─────────────────────────────────────────────────────────
class _StoryDetailSheet extends StatelessWidget {
  const _StoryDetailSheet({
    required this.story,
    required this.isDarkMode,
    required this.isSenior,
  });
  final Map<String, dynamic> story;
  final bool isDarkMode;
  final bool isSenior;

  Color get _bg =>
      isDarkMode ? const Color(0xFF242018) : const Color(0xFFFDFDFD);
  Color get _textPrimary =>
      isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  @override
  Widget build(BuildContext context) {
    final hasImage = (story['imageUrl'] as String? ?? '').isNotEmpty;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    story['title'] as String,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => SharePreviewWidget.show(
                    context,
                    title: story['title'] as String,
                    body: story['excerpt'] as String,
                    imageUrl: story['imageUrl'] as String?,
                    isDarkMode: isDarkMode,
                  ),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4AA00).withAlpha(18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFD4AA00).withAlpha(60),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.ios_share_rounded,
                      size: 16,
                      color: Color(0xFFD4AA00),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(
                    Icons.close_rounded,
                    color: _textSecondary,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
          // Family read-only note
          if (!isSenior)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AA00).withAlpha(15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color: Color(0xFFD4AA00),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'This is Eleanor\'s story — read only',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 12,
                        color: const Color(0xFFD4AA00),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasImage)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        story['imageUrl'] as String? ?? '',
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        semanticLabel: story['imageLabel'] as String? ?? '',
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  if (hasImage) const SizedBox(height: 20),
                  if ((story['entry_type'] as String? ?? 'text') == 'audio' &&
                      (story['media_url'] as String? ?? '').isNotEmpty)
                    _LegacyAudioPlayer(
                      audioUrl: story['media_url'] as String,
                      isDarkMode: isDarkMode,
                    )
                  else if ((story['entry_type'] as String? ?? 'text') == 'video' &&
                      (story['media_url'] as String? ?? '').isNotEmpty)
                    _LegacyVideoCardPlayer(
                      videoUrl: story['media_url'] as String,
                      isDarkMode: isDarkMode,
                    )
                  else
                    Text(
                      story['excerpt'] as String? ?? '',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 16,
                        color: _textPrimary,
                        height: 1.7,
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
  }
}

// ── Legacy Voice Record Sheet ─────────────────────────────────────────────────
class _LegacyVoiceRecordSheet extends StatefulWidget {
  const _LegacyVoiceRecordSheet({
    required this.isDarkMode,
    this.onRecordingComplete,
  });
  final bool isDarkMode;
  final VoidCallback? onRecordingComplete;

  @override
  State<_LegacyVoiceRecordSheet> createState() =>
      _LegacyVoiceRecordSheetState();
}

class _LegacyVoiceRecordSheetState extends State<_LegacyVoiceRecordSheet> {
  bool _isRecording = false;
  bool _hasRecording = false;
  int _seconds = 0;
  Timer? _timer;
  bool _isPlaying = false;
  Timer? _playTimer;
  int _playPosition = 0;
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _audioFilePath;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    AudioSession.instance.then((session) async {
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker |
            AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ));
    });
  }

  Color get _bg =>
      widget.isDarkMode ? const Color(0xFF242018) : const Color(0xFFFDFDFD);
  Color get _surface =>
      widget.isDarkMode ? const Color(0xFF2E2820) : const Color(0xFFF5F0FF);
  Color get _cardBorder =>
      widget.isDarkMode ? const Color(0xFF3D3428) : const Color(0xFF9B8FD4);
  Color get _textPrimary =>
      widget.isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      widget.isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  @override
  void dispose() {
    _timer?.cancel();
    _playTimer?.cancel();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        debugPrint('Microphone permission denied');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/legacy_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      setState(() {
        _isRecording = true;
        _hasRecording = false;
        _seconds = 0;
        _isPlaying = false;
        _playPosition = 0;
        _audioFilePath = path;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
      });
    } catch (e) {
      debugPrint('Legacy start recording error: $e');
    }
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    try {
      await _audioRecorder.stop();
    } catch (e) {
      debugPrint('Legacy stop recording error: $e');
    }
    setState(() {
      _isRecording = false;
      _hasRecording = true;
    });
  }

  void _retake() {
    _playTimer?.cancel();
    setState(() {
      _isRecording = false;
      _hasRecording = false;
      _seconds = 0;
      _isPlaying = false;
      _playPosition = 0;
    });
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _audioPlayer.stop();
      _playTimer?.cancel();
      setState(() => _isPlaying = false);
    } else {
      if (_audioFilePath == null) return;
      setState(() {
        _isPlaying = true;
        _playPosition = 0;
      });
      try {
        await _audioPlayer.setFilePath(_audioFilePath!);
        await _audioPlayer.play();
        _playTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (_playPosition >= _seconds - 1) {
            t.cancel();
            _audioPlayer.stop();
            if (mounted) setState(() {
              _isPlaying = false;
              _playPosition = 0;
            });
          } else {
            if (mounted) setState(() => _playPosition++);
          }
        });
      } catch (e) {
        print('LEGACY AUDIO PLAYBACK ERROR: $e');
        setState(() => _isPlaying = false);
      }
    }
  }

  String _fmt(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  Future<void> _send() async {
    try {
      final supabase = Supabase.instance.client;
      String? userId = supabase.auth.currentUser?.id;
      if (userId == null) userId = supabase.auth.currentSession?.user.id;
      final prefs = await SharedPreferences.getInstance();
      final nestId = prefs.getString('nest_id') ?? '';

      if (userId != null && _audioFilePath != null) {
        final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await supabase.storage.from('media').upload(
          'audio/$fileName',
          File(_audioFilePath!),
          fileOptions: const FileOptions(contentType: 'audio/m4a'),
        );
        final mediaUrl = supabase.storage.from('media').getPublicUrl('audio/$fileName');
        await supabase.from('legacy_entries').insert({
          'user_id': userId,
          'nest_id': nestId.isEmpty ? null : nestId,
          'content': 'Voice story',
          'entry_type': 'audio',
          'media_url': mediaUrl,
          'is_custom': true,
        });
        await prefs.setBool('has_sent_stories', true);
      }
    } catch (e) {
      print('LEGACY AUDIO SEND ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save error: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 8)),
        );
      }
      return;
    }
    if (mounted) {
      Navigator.pop(context);
      widget.onRecordingComplete?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Voice story saved for your family! 🎙️',
            style: GoogleFonts.nunitoSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF5DA399),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: _cardBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                'Record Your Voice Story',
                style: GoogleFonts.nunitoSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(
                  Icons.close_rounded,
                  color: _textSecondary,
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Speak your story — your family will treasure hearing your voice',
              style: GoogleFonts.nunitoSans(
                fontSize: 13,
                color: _textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 28),
          if (!_hasRecording && !_isRecording) ...[
            GestureDetector(
              onTap: _startRecording,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8A0A0).withAlpha(38),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFE8A0A0).withAlpha(128),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.mic_rounded,
                  color: Color(0xFFE8A0A0),
                  size: 40,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Tap to start recording',
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'No time limit — take as long as you need',
              style: GoogleFonts.nunitoSans(
                fontSize: 12,
                color: const Color(0xFF9B8FD4),
                fontStyle: FontStyle.italic,
              ),
            ),
          ] else if (_isRecording) ...[
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: CircularProgressIndicator(
                    value: null,
                    strokeWidth: 4,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFE8A0A0),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _stopRecording,
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8A0A0).withAlpha(50),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFE8A0A0),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.stop_rounded,
                      color: Color(0xFFE05C5C),
                      size: 34,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE05C5C),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Recording  ${_fmt(_seconds)}',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFE05C5C),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Tap the stop button when done',
              style: GoogleFonts.nunitoSans(
                fontSize: 12,
                color: _textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ] else ...[
            // Preview
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: widget.isDarkMode
                    ? const Color(0xFF2E2820)
                    : const Color(0xFFFFF0F0),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFE8A0A0).withAlpha(100),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _togglePlayback,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8A0A0).withAlpha(40),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFE8A0A0),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: const Color(0xFFE05C5C),
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _isPlaying
                                ? _playPosition / (_seconds > 0 ? _seconds : 1)
                                : 0,
                            minHeight: 6,
                            backgroundColor: const Color(
                              0xFFE8A0A0,
                            ).withAlpha(40),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFFE8A0A0),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _isPlaying ? _fmt(_playPosition) : '0:00',
                              style: GoogleFonts.nunitoSans(
                                fontSize: 11,
                                color: _textSecondary,
                              ),
                            ),
                            Text(
                              _fmt(_seconds),
                              style: GoogleFonts.nunitoSans(
                                fontSize: 11,
                                color: _textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _retake,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _cardBorder, width: 1.5),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            size: 18,
                            color: _textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Retake',
                            style: GoogleFonts.nunitoSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: _isSaving ? null : () async {
                      setState(() => _isSaving = true);
                      await _send();
                      if (mounted) setState(() => _isSaving = false);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5DA399),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF5DA399).withAlpha(60),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Save Story',
                            style: GoogleFonts.nunitoSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Legacy Video Record Sheet ─────────────────────────────────────────────────
class _LegacyVideoRecordSheet extends StatefulWidget {
  const _LegacyVideoRecordSheet({
    required this.isDarkMode,
    this.onRecordingComplete,
  });
  final bool isDarkMode;
  final VoidCallback? onRecordingComplete;

  @override
  State<_LegacyVideoRecordSheet> createState() =>
      _LegacyVideoRecordSheetState();
}

class _LegacyVideoRecordSheetState extends State<_LegacyVideoRecordSheet> {
  bool _isRecording = false;
  bool _hasRecording = false;
  int _seconds = 0;
  Timer? _timer;
  bool _isSaving = false;
  CameraController? _cameraController;
  VideoPlayerController? _videoPlayerController;
  String? _videoFilePath;

  Color get _bg => widget.isDarkMode ? const Color(0xFF242018) : const Color(0xFFFDFDFD);
  Color get _cardBorder => widget.isDarkMode ? const Color(0xFF3D3428) : const Color(0xFFB0C4DE);
  Color get _textPrimary => widget.isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary => widget.isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  @override
  void dispose() {
    _timer?.cancel();
    _cameraController?.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final camera = cameras.length > 1 ? cameras[1] : cameras.first;
      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await _cameraController!.initialize();
      await _cameraController!.startVideoRecording();
      setState(() {
        _isRecording = true;
        _hasRecording = false;
        _seconds = 0;
        _videoFilePath = null;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
      });
    } catch (e) {
      debugPrint('Legacy video start error: $e');
    }
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    try {
      if (_cameraController != null && _cameraController!.value.isRecordingVideo) {
        final file = await _cameraController!.stopVideoRecording();
        _videoFilePath = file.path;
        _videoPlayerController = VideoPlayerController.file(File(file.path));
        await _videoPlayerController!.initialize();
      }
      await _cameraController?.dispose();
      _cameraController = null;
    } catch (e) {
      debugPrint('Legacy video stop error: $e');
    }
    if (mounted) {
      setState(() {
        _isRecording = false;
        _hasRecording = true;
      });
    }
  }

  void _retake() {
    _videoPlayerController?.dispose();
    _videoPlayerController = null;
    _videoFilePath = null;
    setState(() {
      _isRecording = false;
      _hasRecording = false;
      _seconds = 0;
    });
  }

  String _fmt(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  Future<void> _send() async {
    try {
      final supabase = Supabase.instance.client;
      String? userId = supabase.auth.currentUser?.id;
      if (userId == null) userId = supabase.auth.currentSession?.user.id;
      final prefs = await SharedPreferences.getInstance();
      final nestId = prefs.getString('nest_id') ?? '';
      if (userId != null && _videoFilePath != null) {
        final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.mp4';
        await supabase.storage.from('media').upload(
          'video/$fileName',
          File(_videoFilePath!),
          fileOptions: const FileOptions(contentType: 'video/mp4'),
        );
        final mediaUrl = supabase.storage.from('media').getPublicUrl('video/$fileName');
        await supabase.from('legacy_entries').insert({
          'user_id': userId,
          'nest_id': nestId.isEmpty ? null : nestId,
          'content': 'Video story',
          'entry_type': 'video',
          'media_url': mediaUrl,
          'is_custom': true,
        });
        await prefs.setBool('has_sent_stories', true);
      }
    } catch (e) {
      print('LEGACY VIDEO SEND ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save error: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 8)),
        );
      }
      return;
    }
    if (mounted) {
      widget.onRecordingComplete?.call();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Video story saved! 📹',
            style: GoogleFonts.nunitoSans(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white)),
          backgroundColor: const Color(0xFF5DA399),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: EdgeInsets.fromLTRB(24, 20, 24, 36 + bottomPadding),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4,
              decoration: BoxDecoration(color: _cardBorder, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text('Record Video Story',
              style: GoogleFonts.nunitoSans(fontSize: 20, fontWeight: FontWeight.w800, color: _textPrimary)),
            const SizedBox(height: 6),
            Text('Share your story face to face with your family',
              style: GoogleFonts.nunitoSans(fontSize: 13, color: _textSecondary),
              textAlign: TextAlign.center),
            const SizedBox(height: 24),
            // Camera preview during recording
            if (_isRecording && _cameraController != null && _cameraController!.value.isInitialized)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 380,
                  child: Stack(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: double.infinity,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.rotationY(3.14159),
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: _cameraController!.value.previewSize!.height,
                              height: _cameraController!.value.previewSize!.width,
                              child: CameraPreview(_cameraController!),
                            ),
                          ),
                        ),
                      ),
                      Positioned(top: 10, left: 12,
                        child: Row(children: [
                          Container(width: 8, height: 8,
                            decoration: const BoxDecoration(color: Color(0xFFE05C5C), shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Text('REC  ${_fmt(_seconds)}',
                            style: GoogleFonts.nunitoSans(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFFE05C5C))),
                        ])),
                    ],
                  ),
                ),
              )
            // Video playback after recording
            else if (_hasRecording && _videoPlayerController != null && _videoPlayerController!.value.isInitialized)
              GestureDetector(
                onTap: () {
                  if (_videoPlayerController!.value.isPlaying) {
                    _videoPlayerController!.pause();
                  } else {
                    _videoPlayerController!.play();
                  }
                  setState(() {});
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 380,
                    width: double.infinity,
                    color: const Color(0xFF1A1020),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: _videoPlayerController!.value.aspectRatio,
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.rotationY(3.14159),
                            child: VideoPlayer(_videoPlayerController!),
                          ),
                        ),
                        Container(
                          width: 60, height: 60,
                          decoration: BoxDecoration(
                            color: Colors.black45, shape: BoxShape.circle,
                            border: Border.all(color: Colors.white70, width: 2)),
                          child: Icon(
                            _videoPlayerController!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white, size: 32),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            // Idle state
            else
              GestureDetector(
                onTap: _startRecording,
                child: Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    color: _cardBorder.withAlpha(60),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _cardBorder, width: 1.5)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.videocam_rounded, size: 48, color: _textSecondary),
                      const SizedBox(height: 12),
                      Text('Tap to start recording',
                        style: GoogleFonts.nunitoSans(fontSize: 15, color: _textSecondary)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            if (!_isRecording && !_hasRecording) ...[
              // Empty - just idle state shown above
            ] else if (_isRecording) ...[
              GestureDetector(
                onTap: _stopRecording,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE05C5C).withAlpha(20),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE05C5C), width: 1.5)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.stop_rounded, color: Color(0xFFE05C5C), size: 18),
                    const SizedBox(width: 8),
                    Text('Stop Recording',
                      style: GoogleFonts.nunitoSans(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFFE05C5C))),
                  ]),
                ),
              ),
            ] else if (_hasRecording) ...[
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _retake,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: _bg, borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _cardBorder, width: 1.5)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.refresh_rounded, size: 18, color: _textSecondary),
                        const SizedBox(width: 6),
                        Text('Retake', style: GoogleFonts.nunitoSans(fontSize: 15, fontWeight: FontWeight.w700, color: _textSecondary)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _isSaving ? null : () async {
                      setState(() => _isSaving = true);
                      await _send();
                      if (mounted) setState(() => _isSaving = false);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5DA399),
                        borderRadius: BorderRadius.circular(14)),
                      child: _isSaving
                          ? const SizedBox(
                              height: 18, width: 18,
                              child: Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
                          : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                              const SizedBox(width: 6),
                              Text('Save Story', style: GoogleFonts.nunitoSans(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                            ]),
                    ),
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}


class _LegacyAudioPlayer extends StatefulWidget {
  const _LegacyAudioPlayer({required this.audioUrl, required this.isDarkMode});
  final String audioUrl;
  final bool isDarkMode;
  @override
  State<_LegacyAudioPlayer> createState() => _LegacyAudioPlayerState();
}

class _LegacyAudioPlayerState extends State<_LegacyAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  int _duration = 0;
  int _position = 0;

  @override
  void initState() {
    super.initState();
    _player.durationStream.listen((d) {
      if (d != null && mounted) setState(() => _duration = d.inSeconds);
    });
    _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p.inSeconds);
    });
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed && mounted) {
        setState(() { _isPlaying = false; _position = 0; });
        _player.seek(Duration.zero);
      }
    });
    _player.setUrl(widget.audioUrl).catchError((e) { debugPrint('Audio load error: $e'); return Duration.zero; });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8C97A), Color(0xFFC9A84C)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              if (_isPlaying) {
                await _player.pause();
                setState(() => _isPlaying = false);
              } else {
                if (_player.processingState == ProcessingState.idle ||
                    _player.processingState == ProcessingState.completed) {
                  await _player.setUrl(widget.audioUrl);
                }
                await _player.play();
                setState(() => _isPlaying = true);
              }
            },
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFAF7F2),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF412402), width: 2),
              ),
              child: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: const Color(0xFF412402), size: 22),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 28,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: List.generate(22, (i) {
                      final heights = [8.0,14.0,20.0,12.0,18.0,24.0,10.0,16.0,22.0,14.0,8.0,20.0,16.0,24.0,12.0,18.0,10.0,22.0,14.0,8.0,16.0,12.0];
                      return Container(
                        width: 3,
                        height: heights[i % heights.length],
                        decoration: BoxDecoration(
                          color: const Color(0xFF412402).withAlpha(102),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 4),
                Text(_isPlaying ? _fmt(_position) : _fmt(_duration),
                    style: GoogleFonts.nunitoSans(fontSize: 11, color: const Color(0xFF412402).withAlpha(166), fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegacyVideoCardPlayer extends StatelessWidget {
  const _LegacyVideoCardPlayer({required this.videoUrl, required this.isDarkMode});
  final String videoUrl;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openFullscreenVideo(
        context: context,
        videoUrl: videoUrl,
        isDarkMode: isDarkMode,
      ),
      child: Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3D5266), Color(0xFF2A4A45)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 8, left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(38),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam_rounded, color: Color(0xFFE1F5EE), size: 14),
                    SizedBox(width: 4),
                    Text('Video', style: TextStyle(color: Color(0xFFE1F5EE), fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF5DA399),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFFAF7F2), width: 2),
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Color(0xFFFAF7F2), size: 32),
                ),
                const SizedBox(height: 8),
                Text('Tap to play',
                    style: GoogleFonts.nunitoSans(fontSize: 12, color: Colors.white.withAlpha(217), fontStyle: FontStyle.italic)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


class _LegacyStoryCard extends StatefulWidget {
  const _LegacyStoryCard({
    required this.story,
    required this.index,
    required this.isTablet,
    required this.isDarkMode,
    required this.isSenior,
    required this.profileData,
    required this.displayName,
    required this.onHeart,
    required this.onBookmark,
    required this.onShare,
    this.onTap,
  });
  final Map<String, dynamic> story;
  final int index;
  final bool isTablet;
  final bool isDarkMode;
  final bool isSenior;
  final Map<String, dynamic>? profileData;
  final String displayName;
  final VoidCallback onHeart;
  final VoidCallback onBookmark;
  final VoidCallback onShare;
  final VoidCallback? onTap;

  @override
  State<_LegacyStoryCard> createState() => _LegacyStoryCardState();
}

class _LegacyStoryCardState extends State<_LegacyStoryCard> {
  bool _showReplyComposer = false;
  bool _showReplies = false;
  final TextEditingController _replyController = TextEditingController();
  bool _sendingReply = false;
  List<Map<String, dynamic>> _replies = [];
  final Set<String> _repliesHearted = {};

  Color get _cardBg => widget.isDarkMode ? const Color(0xFF242018) : const Color(0xFFFAF7F2);
  Color get _cardBorder => widget.isDarkMode ? const Color(0xFF3D3428) : const Color(0xFFE8E0D0);
  Color get _textPrimary => widget.isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary => widget.isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  @override
  void initState() {
    super.initState();
    _loadReplies();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadReplies() async {
    try {
      final supabase = Supabase.instance.client;
      final storyId = widget.story['id'] as String? ?? '';
      if (storyId.isEmpty) return;
      final response = await supabase
          .from('feed_posts')
          .select('*, user_profiles(display_name)')
          .eq('legacy_entry_id', storyId)
          .order('created_at', ascending: true);
      if (mounted) {
        setState(() => _replies = List<Map<String, dynamic>>.from(response as List));
      }
    } catch (e) {
      debugPrint('Legacy reply load error: \$e');
    }
  }

  Future<void> _sendReply(String text) async {
    if (text.trim().isEmpty) return;
    setState(() => _sendingReply = true);
    try {
      final supabase = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();
      final nestId = prefs.getString('nest_id') ?? '';
      final userId = supabase.auth.currentUser?.id;
      if (nestId.isEmpty || userId == null) {
        setState(() => _sendingReply = false);
        return;
      }
      final storyId = widget.story['id'] as String? ?? '';
      await supabase.from('feed_posts').insert({
        'nest_id': nestId,
        'author_id': userId,
        'post_type': 'text',
        'content': text.trim(),
        'legacy_entry_id': storyId,
      });
      _replyController.clear();
      await _loadReplies();
      if (mounted) {
        setState(() {
          _sendingReply = false;
          _showReplyComposer = false;
          _showReplies = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _sendingReply = false);
    }
  }

  String _formatTimestamp(DateTime ts) {
    final now = DateTime.now();
    final diff = now.difference(ts);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.story;
    final hasImage = (story['imageUrl'] as String? ?? '').isNotEmpty;
    final isHearted = story['isHearted'] as bool? ?? false;
    final heartCount = story['heartCount'] as int? ?? 0;
    final entryType = story['entry_type'] as String? ?? 'text';
    final mediaUrl = story['media_url'] as String? ?? '';

    return Container(
      margin: EdgeInsets.fromLTRB(widget.isTablet ? 28 : 20, 0, widget.isTablet ? 28 : 20, 14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder, width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14.5),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasImage)
                  GestureDetector(
                    onTap: () => openFullscreenImage(
                      context: context,
                      imageUrl: story['imageUrl'] as String? ?? '',
                      semanticLabel: story['imageLabel'] as String? ?? '',
                      isDarkMode: widget.isDarkMode,
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                      child: Stack(
                        children: [
                          Image.network(
                            story['imageUrl'] as String? ?? '',
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                          Positioned(
                            bottom: 8, right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(120),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.fullscreen_rounded, color: Colors.white, size: 14),
                                  SizedBox(width: 3),
                                  Text('Tap to expand', style: TextStyle(color: Colors.white, fontSize: 10)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ProfileAvatarWidget(
                            profileData: widget.profileData,
                            displayName: widget.displayName,
                            size: 36,
                            borderColor: const Color(0xFF5DA399),
                            borderWidth: 1.5,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.displayName.isNotEmpty ? widget.displayName : 'My Story',
                                style: GoogleFonts.nunitoSans(fontSize: 13, fontWeight: FontWeight.w700, color: _textPrimary),
                              ),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF5DA399).withAlpha(25),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  story['category'] as String? ?? 'Memories',
                                  style: GoogleFonts.nunitoSans(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF5DA399)),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            () {
                              final d = DateTime.tryParse(story['date'] as String? ?? '');
                              if (d == null) return story['date'] as String? ?? '';
                              const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
                              return '${months[d.month - 1]} ${d.day}';
                            }(),
                            style: GoogleFonts.nunitoSans(fontSize: 12, color: _textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        story['title'] as String? ?? '',
                        style: GoogleFonts.nunitoSans(fontSize: 17, fontWeight: FontWeight.w700, color: _textPrimary, height: 1.3),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      if (entryType == 'audio' && mediaUrl.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _LegacyAudioPlayer(audioUrl: mediaUrl, isDarkMode: widget.isDarkMode),
                        )
                      else if (entryType == 'video' && mediaUrl.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _LegacyVideoCardPlayer(videoUrl: mediaUrl, isDarkMode: widget.isDarkMode),
                        )
                      else
                        Text(
                          story['excerpt'] as String? ?? '',
                          style: GoogleFonts.nunitoSans(fontSize: 14, color: _textSecondary, height: 1.5),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 36, height: 36,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                  icon: Icon(
                                    isHearted ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                                    color: isHearted ? const Color(0xFFE05C5C) : _textSecondary,
                                    size: 22,
                                  ),
                                  onPressed: widget.onHeart,
                                ),
                              ),
                              Text(
                                heartCount.toString(),
                                style: GoogleFonts.nunitoSans(fontSize: 13, fontWeight: FontWeight.w600,
                                    color: isHearted ? const Color(0xFFE05C5C) : _textSecondary),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          GestureDetector(
                            onTap: () => setState(() => _showReplyComposer = !_showReplyComposer),
                            child: Row(
                              children: [
                                Icon(Icons.reply_rounded, size: 18, color: _textSecondary),
                                const SizedBox(width: 4),
                                Text(
                                  _replies.isNotEmpty ? 'Reply (${_replies.length})' : 'Reply',
                                  style: GoogleFonts.nunitoSans(fontSize: 13, fontWeight: FontWeight.w500, color: _textSecondary),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: widget.onBookmark,
                            child: Icon(
                              (story['isBookmarked'] as bool? ?? false) ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                              size: 22,
                              color: (story['isBookmarked'] as bool? ?? false) ? const Color(0xFF5DA399) : _textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: widget.onShare,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD4AA00).withAlpha(18),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFD4AA00).withAlpha(60), width: 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.ios_share_rounded, size: 14, color: Color(0xFFD4AA00)),
                                  const SizedBox(width: 5),
                                  Text('Share Story', style: GoogleFonts.nunitoSans(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFFD4AA00))),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_replies.isNotEmpty) ...[
                        GestureDetector(
                          onTap: () => setState(() => _showReplies = !_showReplies),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                Icon(_showReplies ? Icons.expand_less : Icons.expand_more, size: 16, color: const Color(0xFF5DA399)),
                                const SizedBox(width: 4),
                                Text(
                                  _showReplies ? 'Hide replies' : '${_replies.length} ${_replies.length == 1 ? "reply" : "replies"}',
                                  style: GoogleFonts.nunitoSans(fontSize: 12, color: const Color(0xFF5DA399), fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_showReplies)
                          ..._replies.map((reply) {
                            final profile = reply['user_profiles'] as Map<String, dynamic>?;
                            final name = profile?['display_name'] as String? ?? 'Family';
                            final text = reply['content'] as String? ?? '';
                            final ts = DateTime.tryParse(reply['created_at'] as String? ?? '') ?? DateTime.now();
                            final replyId = reply['id'] as String? ?? '';
                            return Container(
                              margin: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: widget.isDarkMode ? const Color(0xFF1A1612) : const Color(0xFFF0EBE3),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: widget.isDarkMode ? const Color(0xFF3D3428) : const Color(0xFFE0D8CC)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(name, style: GoogleFonts.nunitoSans(fontSize: 13, fontWeight: FontWeight.w700, color: _textPrimary)),
                                      const SizedBox(width: 8),
                                      Text(_formatTimestamp(ts), style: GoogleFonts.nunitoSans(fontSize: 11, color: _textSecondary)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(text, style: GoogleFonts.nunitoSans(fontSize: 13, color: _textPrimary)),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      GestureDetector(
                                        onTap: () => setState(() {
                                          if (_repliesHearted.contains(replyId)) {
                                            _repliesHearted.remove(replyId);
                                          } else {
                                            _repliesHearted.add(replyId);
                                          }
                                        }),
                                        child: Icon(
                                          _repliesHearted.contains(replyId) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                          size: 16,
                                          color: _repliesHearted.contains(replyId) ? const Color(0xFFE05C5C) : _textSecondary,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(_repliesHearted.contains(replyId) ? '1' : '0',
                                          style: GoogleFonts.nunitoSans(fontSize: 12,
                                              color: _repliesHearted.contains(replyId) ? const Color(0xFFE05C5C) : _textSecondary)),
                                      const SizedBox(width: 16),
                                      GestureDetector(
                                        onTap: () => setState(() => _showReplyComposer = !_showReplyComposer),
                                        child: Text('Reply', style: GoogleFonts.nunitoSans(fontSize: 12, color: const Color(0xFF5DA399), fontWeight: FontWeight.w600)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                      if (_showReplyComposer)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _replyController,
                                  autofocus: true,
                                  style: GoogleFonts.nunitoSans(fontSize: 13, color: _textPrimary),
                                  decoration: InputDecoration(
                                    hintText: 'Write a reply...',
                                    hintStyle: GoogleFonts.nunitoSans(fontSize: 13, color: _textSecondary),
                                    filled: true,
                                    fillColor: widget.isDarkMode ? const Color(0xFF1A1612) : const Color(0xFFF0EBE3),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _sendingReply ? null : () => _sendReply(_replyController.text),
                                child: Container(
                                  width: 36, height: 36,
                                  decoration: const BoxDecoration(color: Color(0xFF5DA399), shape: BoxShape.circle),
                                  child: _sendingReply
                                      ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                      : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
