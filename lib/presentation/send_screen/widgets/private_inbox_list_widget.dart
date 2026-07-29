import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../widgets/custom_image_widget.dart';
import '../../message_thread_screen/message_thread_screen.dart';

/// The list of private 1:1 conversations. No Scaffold/AppBar of its own —
/// meant to be embedded inside another screen (e.g. as a tab).
class PrivateInboxListWidget extends StatefulWidget {
  const PrivateInboxListWidget({super.key, required this.isDarkMode});

  final bool isDarkMode;

  @override
  State<PrivateInboxListWidget> createState() => _PrivateInboxListWidgetState();
}

class _PrivateInboxListWidgetState extends State<PrivateInboxListWidget> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _threads = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final rows = await _supabase
          .from('private_messages')
          .select()
          .or('sender_id.eq.$myId,recipient_id.eq.$myId')
          .order('created_at', ascending: false);

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
        if (mounted) {
          setState(() {
            _threads = [];
            _isLoading = false;
          });
        }
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
      debugPrint('PrivateInboxList load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color get _textPrimary =>
      widget.isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      widget.isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_threads.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 44, color: _textSecondary),
            const SizedBox(height: 16),
            Text(
              'No private messages yet',
              style: GoogleFonts.nunitoSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap someone\'s photo on Home to start a\nprivate conversation.',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunitoSans(fontSize: 13, color: _textSecondary),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _threads.map((thread) => _buildThreadRow(thread)).toList(),
    );
  }

  Widget _buildThreadRow(Map<String, dynamic> thread) {
    final unread = thread['unreadCount'] as int;
    final avatarUrl = thread['avatarUrl'] as String;
    final name = thread['name'] as String;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openThread(thread),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
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
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.nunitoSans(
                      fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w700,
                      fontSize: 15.5,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    thread['lastMessage'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
                      color: unread > 0 ? _textPrimary : _textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (unread > 0)
              Container(
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
              ),
          ],
        ),
      ),
    );
  }
}
