import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/custom_image_widget.dart';
import '../../widgets/app_navigation.dart';
import '../message_thread_screen/message_thread_screen.dart';
import '../../routes/app_routes.dart';

/// Inbox: one row per person the current user has a private thread with,
/// showing their last message and whether it's unread.
class MessagesInboxScreen extends StatefulWidget {
  const MessagesInboxScreen({super.key});

  @override
  State<MessagesInboxScreen> createState() => _MessagesInboxScreenState();
}

class _MessagesInboxScreenState extends State<MessagesInboxScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _threads = [];
  bool _isLoading = true;
  bool _isDarkMode = false;
  final int _currentNavIndex = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('dark_mode') ?? false;
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final rows = await _supabase
          .from('private_messages')
          .select()
          .or('sender_id.eq.$myId,recipient_id.eq.$myId')
          .order('created_at', ascending: false);

      // Collapse into one row per "other person", keeping the latest message.
      final Map<String, Map<String, dynamic>> latestByPartner = {};
      final Map<String, int> unreadByPartner = {};
      for (final row in rows) {
        final isMine = row['sender_id'] == myId;
        final partnerId = isMine ? row['recipient_id'] : row['sender_id'];
        latestByPartner.putIfAbsent(partnerId, () => row);
        if (!isMine && row['read_at'] == null) {
          unreadByPartner[partnerId] = (unreadByPartner[partnerId] ?? 0) + 1;
        }
      }

      if (latestByPartner.isEmpty) {
        setState(() {
          _threads = [];
          _isLoading = false;
        });
        return;
      }

      final partnerIds = latestByPartner.keys.toList();
      final profiles = await _supabase
          .from('user_profiles')
          .select('id, display_name, preferred_name, avatar_url')
          .inFilter('id', partnerIds);

      final profileMap = {for (final p in profiles) p['id']: p};

      final threads = partnerIds.map((id) {
        final profile = profileMap[id];
        final name = (profile?['preferred_name'] as String?)?.isNotEmpty == true
            ? profile!['preferred_name'] as String
            : (profile?['display_name'] as String? ?? 'Nest Member');
        return {
          'partnerId': id,
          'name': name,
          'avatarUrl': profile?['avatar_url'] as String? ?? '',
          'lastMessage': latestByPartner[id]?['content'] as String? ?? '',
          'lastAt': latestByPartner[id]?['created_at'],
          'unreadCount': unreadByPartner[id] ?? 0,
        };
      }).toList()
        ..sort((a, b) => (b['lastAt'] as String).compareTo(a['lastAt'] as String));

      if (mounted) {
        setState(() {
          _threads = threads;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('MessagesInbox load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color get _bg => _isDarkMode ? const Color(0xFF1A1612) : const Color(0xFFFDF9F4);
  Color get _cardBg => _isDarkMode ? const Color(0xFF242018) : Colors.white;
  Color get _textPrimary =>
      _isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      _isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  void _openThread(Map<String, dynamic> thread) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessageThreadScreen(
          recipientId: thread['partnerId'] as String,
          recipientName: thread['name'] as String,
          recipientAvatarUrl: thread['avatarUrl'] as String?,
        ),
      ),
    ).then((_) => _load());
  }

  void _onNavTap(int index) {
    if (index == _currentNavIndex) return;
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, AppRoutes.familyFeedScreen);
        break;
      case 2:
        Navigator.pushReplacementNamed(context, AppRoutes.legacyScreen);
        break;
      case 3:
        Navigator.pushReplacementNamed(context, AppRoutes.safetyScreen);
        break;
      case 4:
        Navigator.pushReplacementNamed(context, AppRoutes.favsScreen);
        break;
      case 5:
        Navigator.pushReplacementNamed(context, AppRoutes.setupScreen);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: Text(
          'Messages',
          style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w800, color: _textPrimary),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _threads.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _threads.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: _textPrimary.withAlpha(15),
                    indent: 78,
                  ),
                  itemBuilder: (context, index) => _buildThreadRow(_threads[index]),
                ),
      bottomNavigationBar: AppNavigation(
        currentIndex: _currentNavIndex,
        onTap: _onNavTap,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 48, color: _textSecondary),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: GoogleFonts.nunitoSans(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap someone\'s photo on Home to start a private conversation.',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunitoSans(fontSize: 13, color: _textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThreadRow(Map<String, dynamic> thread) {
    final unread = thread['unreadCount'] as int;
    final avatarUrl = thread['avatarUrl'] as String;
    final name = thread['name'] as String;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      onTap: () => _openThread(thread),
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF5DA399), width: 2),
        ),
        child: avatarUrl.isNotEmpty
            ? ClipOval(
                child: CustomImageWidget(
                  imageUrl: avatarUrl,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                ),
              )
            : CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFF5DA399).withAlpha(40),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: GoogleFonts.nunitoSans(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF5DA399),
                  ),
                ),
              ),
      ),
      title: Text(
        name,
        style: GoogleFonts.nunitoSans(
          fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w700,
          fontSize: 15.5,
          color: _textPrimary,
        ),
      ),
      subtitle: Text(
        thread['lastMessage'] as String,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.nunitoSans(
          fontSize: 13,
          fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
          color: unread > 0 ? _textPrimary : _textSecondary,
        ),
      ),
      trailing: unread > 0
          ? Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFF5DA399),
                shape: BoxShape.circle,
              ),
              child: Text(
                '$unread',
                style: GoogleFonts.nunitoSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            )
          : null,
    );
  }
}
