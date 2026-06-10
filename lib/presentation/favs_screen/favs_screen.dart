import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/app_navigation.dart';
import '../profile_photo_picker_screen/profile_photo_picker_screen.dart';

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
    'Text',
    'Photos',
    'Audio',
    'Video',
  ];
  static const List<IconData> _categoryIcons = [
    Icons.bookmark_rounded,
    Icons.chat_bubble_outline_rounded,
    Icons.photo_camera_rounded,
    Icons.mic_rounded,
    Icons.videocam_rounded,
  ];
  static const List<Color> _categoryColors = [
    Color(0xFF5DA399),
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
    final categoryIndices = [1, 2, 3, 4];
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
    final content2 = item['content'] as String? ?? '';

    if (category == 'Audio' && mediaUrl.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(item['title'] ?? 'Audio Memory'),
          content: Text('Audio: $mediaUrl'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );
    } else if (category == 'Video' && mediaUrl.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(item['title'] ?? 'Video Memory'),
          content: Text('Video: $mediaUrl'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );
    } else if (category == 'Photos' && mediaUrl.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Image.network(mediaUrl, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );
    } else if (content2.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(item['title'] ?? 'Memory'),
          content: Text(content2),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );
    }
  }

  Widget _buildMemoryCard(Map<String, dynamic> item, bool isTablet) {
    final category = item['category'] as String? ?? '';
    final title = item['senderName'] as String? ?? item['title'] as String? ?? '';
    final subtitle = item['content'] as String? ?? item['subtitle'] as String? ?? '';
    final timestamp = item['timestamp'] as String? ?? '';
    final catIndex = _categories.indexOf(category);
    final catColor = catIndex >= 0
        ? _categoryColors[catIndex]
        : const Color(0xFF5DA399);
    final catIcon = catIndex >= 0
        ? _categoryIcons[catIndex]
        : Icons.bookmark_rounded;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openMemory(item),
      child: Container(
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
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: catColor.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(catIcon, size: 18, color: catColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title.isNotEmpty)
                    Text(
                      title,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 13,
                        color: _textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (timestamp.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      timestamp,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 11,
                        color: _textSecondary.withAlpha(160),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.bookmark_remove_rounded,
                color: catColor,
                size: 20,
              ),
              onPressed: () => _removeBookmark(item),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
