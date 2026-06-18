import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/app_navigation.dart';
import '../profile_photo_picker_screen/profile_photo_picker_screen.dart';
import 'package:just_audio/just_audio.dart';
import '../../widgets/fullscreen_media_viewer.dart';

class FavsScreen extends StatefulWidget {
  const FavsScreen({super.key});

  @override
  State<FavsScreen> createState() => _FavsScreenState();
}

class _FavsScreenState extends State<FavsScreen> with TickerProviderStateMixin {
  int _currentNavIndex = 4;
  bool _isDarkMode = false;
  bool _isLoading = true;
  int _selectedCategory = 0; // 0=All, 1=Text, 2=Photos, 3=Audio, 4=Video
  Map<String, dynamic>? _profileData;
  String _displayName = '';
  List<Map<String, dynamic>> _bookmarkedItems = [];

  late AnimationController _entranceController;

  static const List<String> _categories = [
    'All',
    'Legacy',
    'Text',
    'Photos',
    'Audio',
    'Video',
  ];
  static const List<IconData> _categoryIcons = [
    Icons.bookmark_rounded,
    Icons.auto_stories_rounded,
    Icons.chat_bubble_outline_rounded,
    Icons.photo_camera_rounded,
    Icons.mic_rounded,
    Icons.videocam_rounded,
  ];
  static const List<Color> _categoryColors = [
    Color(0xFF5DA399),
    Color(0xFFD4AA00),
    Color(0xFFA8A090),
    Color(0xFF4A7FA5),
    Color(0xFF5DA399),
    Color(0xFF7A5FA5),
  ];

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final profileJson = prefs.getString(kProfilePhotoKey);
    Map<String, dynamic>? profileData;
    if (profileJson != null) {
      try {
        profileData = jsonDecode(profileJson) as Map<String, dynamic>;
      } catch (_) {}
    }

    List<Map<String, dynamic>> items = [];
    final itemsJson = prefs.getString('bookmarked_items');
    if (itemsJson != null) {
      try {
        final list = jsonDecode(itemsJson) as List<dynamic>;
        items = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {}
    }

    setState(() {
      _isDarkMode = prefs.getBool('dark_mode') ?? false;
      _isLoading = false;
      _profileData = profileData;
      _displayName = prefs.getString('display_name') ?? '';
      _bookmarkedItems = items.reversed.toList(); // most recent first
    });
    _entranceController.forward();
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

  List<Map<String, dynamic>> get _filteredItems {
    if (_selectedCategory == 0) return _bookmarkedItems;
    final cat = _categories[_selectedCategory];
    return _bookmarkedItems.where((item) => item['category'] == cat).toList();
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
      case 2:
        Navigator.pushReplacementNamed(context, '/legacy-screen');
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/safety-screen');
        break;
      case 5:
        Navigator.pushReplacementNamed(context, '/setup-screen');
        break;
    }
  }

  Future<void> _removeBookmark(Map<String, dynamic> item) async {
    final id = item['id'] as String;
    final prefs = await SharedPreferences.getInstance();

    // Remove from IDs list
    final bookmarksJson = prefs.getString('bookmarks');
    if (bookmarksJson != null) {
      try {
        final ids = List<String>.from(
          jsonDecode(bookmarksJson) as List<dynamic>,
        );
        ids.remove(id);
        await prefs.setString('bookmarks', jsonEncode(ids));
      } catch (_) {}
    }

    // Remove from items list
    final allItemsJson = prefs.getString('bookmarked_items') ?? '[]';
    try {
      final allItems = (jsonDecode(allItemsJson) as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => e['id'] != id)
          .toList();
      await prefs.setString('bookmarked_items', jsonEncode(allItems));
    } catch (_) {}

    setState(() {
      _bookmarkedItems.removeWhere((e) => e['id'] == id);
    });
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
            _buildCategoryFilter(isTablet),
            Expanded(
              child: _isLoading
                  ? _buildLoadingState()
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      color: const Color(0xFF5DA399),
                      backgroundColor: _bg,
                      child: _buildContent(isTablet),
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
                'Memories',
                style: GoogleFonts.nunitoSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                ),
              ),
              Text(
                'Your bookmarked moments',
                style: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  color: _textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          const Text('🔖', style: TextStyle(fontSize: 26)),
          const SizedBox(width: 8),
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

  Widget _buildCategoryFilter(bool isTablet) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: isTablet ? 28 : 20),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedCategory == index;
          final color = _categoryColors[index];
          final count = index == 0
              ? _bookmarkedItems.length
              : _bookmarkedItems
                    .where((item) => item['category'] == _categories[index])
                    .length;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedCategory = index);
              _entranceController
                ..reset()
                ..forward();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? color : _surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? color : _cardBorder,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _categoryIcons[index],
                    size: 13,
                    color: isSelected ? Colors.white : _textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _categories[index],
                    style: GoogleFonts.nunitoSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : _textSecondary,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withAlpha(60)
                            : color.withAlpha(40),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : color,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(bool isTablet) {
    final items = _filteredItems;

    // When viewing "All", show category sections with inline empty placeholders
    if (_selectedCategory == 0) {
      return _buildAllCategoriesView(isTablet);
    }

    // When viewing a specific category
    if (items.isEmpty) {
      return _buildCategoryEmptyState(_selectedCategory);
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 28 : 20,
        16,
        isTablet ? 28 : 20,
        100,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return AnimatedBuilder(
          animation: _entranceController,
          builder: (context, child) {
            final start = (index * 0.1).clamp(0.0, 0.7);
            final end = (start + 0.4).clamp(0.0, 1.0);
            final anim = CurvedAnimation(
              parent: _entranceController,
              curve: Interval(start, end, curve: Curves.easeOutCubic),
            );
            return Opacity(
              opacity: anim.value,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - anim.value)),
                child: child,
              ),
            );
          },
          child: _buildMemoryCard(item, isTablet),
        );
      },
    );
  }

  Widget _buildAllCategoriesView(bool isTablet) {
    // Categories 1-4: Text, Photos, Audio, Video
    final categoryIndices = [1, 2, 3, 4, 5];
    final hPad = isTablet ? 28.0 : 20.0;

    return ListView(
      padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 100),
      children: categoryIndices.map((catIndex) {
        final catName = _categories[catIndex];
        final catItems = _bookmarkedItems
            .where((item) => item['category'] == catName)
            .toList();
        final catColor = _categoryColors[catIndex];
        final catIcon = _categoryIcons[catIndex];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category header
            Padding(
              padding: const EdgeInsets.only(bottom: 10, top: 6),
              child: Row(
                children: [
                  Icon(catIcon, size: 15, color: catColor),
                  const SizedBox(width: 6),
                  Text(
                    catName,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: catColor,
                    ),
                  ),
                  if (catItems.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: catColor.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${catItems.length}',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: catColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Items or inline empty placeholder
            if (catItems.isEmpty)
              _buildInlineCategoryPlaceholder(catIndex)
            else
              ...catItems.map((item) => _buildMemoryCard(item, isTablet)),
            const SizedBox(height: 8),
            Divider(color: _cardBorder, thickness: 1),
            const SizedBox(height: 8),
          ],
        );
      }).toList(),
    );
  }

  static const Map<int, String> _categoryPlaceholderText = {
    1: 'Bookmark a text message from your family to save it here. Tap the bookmark icon on any message to add it to your Memories.',
    2: 'Bookmark a photo from your family to save it here. Tap the bookmark icon on any photo to add it to your Memories.',
    3: 'Bookmark a voice message from your family to save it here. Tap the bookmark icon on any audio message to add it to your Memories.',
    4: 'Bookmark a video from your family to save it here. Tap the bookmark icon on any video message to add it to your Memories.',
  };

  // Demo content for each category — shown only when category is empty
  static const Map<int, Map<String, String>> _demoContent = {
    1: {
      'title': 'Sarah — Daughter',
      'subtitle':
          '"Mom, just wanted to say I love you and I\'m so proud of everything you do. You inspire me every single day. 💛"',
      'timestamp': 'Example · Text Memory',
      'avatar': 'S',
    },
    2: {
      'title': 'Michael — Son',
      'subtitle':
          'Family photo from Thanksgiving — everyone together around the table, smiling.',
      'timestamp': 'Example · Photo Memory',
      'avatar': 'M',
      'imageUrl':
          'https://img.rocket.new/generatedImages/rocket_gen_img_1bc8e5f7f-1767107199150.png',
    },
    3: {
      'title': 'Priya — Granddaughter',
      'subtitle':
          '"Hi Grandma! I recorded this just to say good morning and tell you I miss you so much. Can\'t wait to visit!"',
      'timestamp': 'Example · Voice Memory · 0:18',
      'avatar': 'P',
    },
    4: {
      'title': 'Michael — Son',
      'subtitle':
          'Birthday video message — Michael and the kids singing Happy Birthday from the backyard.',
      'timestamp': 'Example · Video Memory · 1:24',
      'avatar': 'M',
    },
  };

  static const Map<int, Color> _demoAvatarColors = {
    1: Color(0xFF5DA399),
    2: Color(0xFF4A7FA5),
    3: Color(0xFFB07A5A),
    4: Color(0xFF4A7FA5),
  };

  Widget _buildInlineCategoryPlaceholder(int catIndex) {
    final demo = _demoContent[catIndex];
    if (demo == null) return const SizedBox.shrink();
    final catColor = _categoryColors[catIndex];
    final catIcon = _categoryIcons[catIndex];
    final avatarColor = _demoAvatarColors[catIndex] ?? catColor;
    final imageUrl = demo['imageUrl'];

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _cardBorder, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar circle
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: avatarColor.withAlpha(40),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: avatarColor.withAlpha(80),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          demo['avatar'] ?? '',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: avatarColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            demo['title'] ?? '',
                            style: GoogleFonts.nunitoSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            demo['subtitle'] ?? '',
                            style: GoogleFonts.nunitoSans(
                              fontSize: 13,
                              color: _textSecondary,
                              height: 1.45,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (imageUrl != null) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                imageUrl,
                                height: 100,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                semanticLabel: 'Family photo memory example',
                                errorBuilder: (_, __, ___) => Container(
                                  height: 100,
                                  decoration: BoxDecoration(
                                    color: catColor.withAlpha(20),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.photo_rounded,
                                    color: catColor.withAlpha(80),
                                    size: 32,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                catIcon,
                                size: 11,
                                color: catColor.withAlpha(160),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                demo['timestamp'] ?? '',
                                style: GoogleFonts.nunitoSans(
                                  fontSize: 11,
                                  color: _textSecondary.withAlpha(160),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.bookmark_rounded,
                      color: catColor.withAlpha(80),
                      size: 18,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // "Preview" badge overlay
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: _textSecondary.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Preview',
              style: GoogleFonts.nunitoSans(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _textSecondary.withAlpha(180),
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryEmptyState(int catIndex) {
    final demo = _demoContent[catIndex];
    final catColor = _categoryColors[catIndex];
    final catIcon = _categoryIcons[catIndex];
    final cat = _categories[catIndex];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(catIcon, size: 15, color: catColor),
              const SizedBox(width: 6),
              Text(
                cat,
                style: GoogleFonts.nunitoSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: catColor,
                ),
              ),
            ],
          ),
        ),
        if (demo != null)
          _buildCategoryDemoCard(catIndex, demo, catColor, catIcon),
      ],
    );
  }

  Widget _buildCategoryDemoCard(
    int catIndex,
    Map<String, String> demo,
    Color catColor,
    IconData catIcon,
  ) {
    final avatarColor = _demoAvatarColors[catIndex] ?? catColor;
    final imageUrl = demo['imageUrl'];

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _cardBorder, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: avatarColor.withAlpha(40),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: avatarColor.withAlpha(80),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      demo['avatar'] ?? '',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: avatarColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        demo['title'] ?? '',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        demo['subtitle'] ?? '',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 13,
                          color: _textSecondary,
                          height: 1.45,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (imageUrl != null) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            imageUrl,
                            height: 140,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            semanticLabel: 'Family photo memory example',
                            errorBuilder: (_, __, ___) => Container(
                              height: 140,
                              decoration: BoxDecoration(
                                color: catColor.withAlpha(20),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.photo_rounded,
                                color: catColor.withAlpha(80),
                                size: 40,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            catIcon,
                            size: 11,
                            color: catColor.withAlpha(160),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            demo['timestamp'] ?? '',
                            style: GoogleFonts.nunitoSans(
                              fontSize: 11,
                              color: _textSecondary.withAlpha(160),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.bookmark_rounded,
                  color: catColor.withAlpha(80),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: _textSecondary.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Preview',
              style: GoogleFonts.nunitoSans(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _textSecondary.withAlpha(180),
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bookmark_border_rounded,
              size: 52,
              color: const Color(0xFF5DA399).withAlpha(120),
            ),
            const SizedBox(height: 16),
            Text(
              'No memories yet',
              style: GoogleFonts.nunitoSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the bookmark icon on any message or story to save it here',
              style: GoogleFonts.nunitoSans(
                fontSize: 14,
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
      itemCount: 4,
      itemBuilder: (context, index) => Container(
        height: 120,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  void _openMemory(Map<String, dynamic> item) {
    final category = item['category'] as String? ?? '';
    final mediaUrl = item['media_url'] as String? ?? '';
    final entryType = item['entry_type'] as String? ?? 'text';
    final content2 = item['content'] as String? ?? '';
    final title = item['senderName'] as String? ?? item['storyTitle'] as String? ?? 'Memory';
    final imageUrl = item['imageUrl'] as String? ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: _isDarkMode ? const Color(0xFF242018) : const Color(0xFFFDFDFD),
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
                      title,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Icon(Icons.close_rounded, color: _textSecondary, size: 24),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((category == 'Audio' || entryType == 'audio') && mediaUrl.isNotEmpty)
                      _FavsAudioPlayer(audioUrl: mediaUrl, isDarkMode: _isDarkMode)
                    else if ((category == 'Video' || entryType == 'video') && mediaUrl.isNotEmpty)
                      _FavsVideoPlayer(videoUrl: mediaUrl, isDarkMode: _isDarkMode)
                    else if ((category == 'Photos') && imageUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(imageUrl, width: double.infinity, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                      )
                    else if (content2.isNotEmpty)
                      Text(content2,
                          style: GoogleFonts.nunitoSans(
                              fontSize: 16,
                              color: _isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417),
                              height: 1.7)),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryCard(Map<String, dynamic> item, bool isTablet) {
    final category = item['category'] as String? ?? '';
    final title = item['senderName'] as String? ?? item['storyTitle'] as String? ?? 'Memory';
    final subtitle = item['content'] as String? ?? '';
    final timestamp = item['timestamp'] as String? ?? '';
    final entryType = item['entry_type'] as String? ?? 'text';
    final mediaUrl = item['media_url'] as String? ?? '';
    final imageUrl = item['imageUrl'] as String? ?? '';
    final senderRelationship = item['senderRelationship'] as String? ?? '';

    // Format date
    String formattedDate = '';
    if (timestamp.isNotEmpty) {
      final dt = DateTime.tryParse(timestamp);
      if (dt != null) {
        const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        formattedDate = '${months[dt.month - 1]} ${dt.day}';
      }
    }

    // Category color and icon
    final catIndex = _categories.indexOf(category);
    final catColor = catIndex >= 0 ? _categoryColors[catIndex] : const Color(0xFF5DA399);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openMemory(item),
      child: Container(
        margin: EdgeInsets.fromLTRB(isTablet ? 28 : 20, 0, isTablet ? 28 : 20, 14),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _cardBorder, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo preview if available
              if (imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  child: Image.network(imageUrl, height: 160, width: double.infinity, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row
                    Row(
                      children: [
                        ProfileAvatarWidget(
                          profileData: _profileData,
                          displayName: _displayName,
                          size: 36,
                          borderColor: catColor,
                          borderWidth: 1.5,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                style: GoogleFonts.nunitoSans(fontSize: 14, fontWeight: FontWeight.w700, color: _textPrimary),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (senderRelationship.isNotEmpty)
                                Text(senderRelationship,
                                  style: GoogleFonts.nunitoSans(fontSize: 11, color: _textSecondary)),
                            ],
                          ),
                        ),
                        // Category badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: catColor.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(category,
                            style: GoogleFonts.nunitoSans(fontSize: 10, fontWeight: FontWeight.w700, color: catColor)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Content — audio player, video player, text, or photo
                    if ((category == 'Audio' || entryType == 'audio') && mediaUrl.isNotEmpty)
                      _FavsAudioPlayer(audioUrl: mediaUrl, isDarkMode: _isDarkMode)
                    else if ((category == 'Video' || entryType == 'video') && mediaUrl.isNotEmpty)
                      _FavsVideoPlayer(videoUrl: mediaUrl, isDarkMode: _isDarkMode)
                    else if (subtitle.isNotEmpty)
                      Text(subtitle,
                        style: GoogleFonts.nunitoSans(fontSize: 13, color: _textSecondary, height: 1.5),
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 10),
                    // Footer row
                    Row(
                      children: [
                        if (formattedDate.isNotEmpty)
                          Text(formattedDate,
                            style: GoogleFonts.nunitoSans(fontSize: 11, color: _textSecondary.withAlpha(160))),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _removeBookmark(item),
                          child: Icon(Icons.bookmark_rounded, color: catColor, size: 20),
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
    );
  }

}
class _FavsAudioPlayer extends StatefulWidget {
  const _FavsAudioPlayer({required this.audioUrl, required this.isDarkMode});
  final String audioUrl;
  final bool isDarkMode;
  @override
  State<_FavsAudioPlayer> createState() => _FavsAudioPlayerState();
}

class _FavsAudioPlayerState extends State<_FavsAudioPlayer> {
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
    _player.setUrl(widget.audioUrl).catchError((e) => Duration.zero);
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
                        width: 3, height: heights[i % heights.length],
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

class _FavsVideoPlayer extends StatelessWidget {
  const _FavsVideoPlayer({required this.videoUrl, required this.isDarkMode});
  final String videoUrl;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openFullscreenVideo(context: context, videoUrl: videoUrl, isDarkMode: isDarkMode),
      child: Container(
        height: 220,
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
