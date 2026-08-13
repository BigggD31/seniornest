import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../../widgets/custom_image_widget.dart';
import '../../widgets/linkified_text.dart';
import '../profile_photo_picker_screen/profile_photo_picker_screen.dart';
import '../../widgets/keyboard_done_bar.dart';
import '../../core/app_state.dart';

/// Private 1:1 conversation between the current user and [recipientId].
/// Reads/writes public.private_messages (RLS: sender/recipient only).
class MessageThreadScreen extends StatefulWidget {
  const MessageThreadScreen({
    super.key,
    required this.recipientId,
    required this.recipientName,
    this.recipientAvatarUrl,
  });

  final String recipientId;
  final String recipientName;
  final String? recipientAvatarUrl;

  @override
  State<MessageThreadScreen> createState() => _MessageThreadScreenState();
}

class _MessageThreadScreenState extends State<MessageThreadScreen> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  String? _myUserId;
  String? _myAvatarUrl;
  String _myDisplayName = 'You';
  String? _nestId;
  bool _isLoading = true;
  bool _isSending = false;
  // Seeded from the already-resolved app-wide notifier instead of a
  // hardcoded false -- see messages_inbox_screen.dart for the full
  // explanation of the white-flash bug this fixes.
  bool _isDarkMode = appDarkModeNotifier.value;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('dark_mode') ?? false;
    _myUserId = _supabase.auth.currentUser?.id;
    _nestId = prefs.getString('nest_id');

    // Fetches the same profile fields, from the same table, that
    // messages_inbox_screen.dart already fetches for the OTHER person
    // (widget.recipientAvatarUrl) -- needed so each bubble in the thread
    // below can show whose message it actually is, not just infer it from
    // bubble color/alignment alone.
    if (_myUserId != null) {
      try {
        final myProfile = await _supabase
            .from('user_profiles')
            .select('display_name, preferred_name, avatar_url')
            .eq('id', _myUserId!)
            .maybeSingle();
        if (myProfile != null && mounted) {
          final preferred = myProfile['preferred_name'] as String? ?? '';
          final display = myProfile['display_name'] as String? ?? '';
          setState(() {
            _myAvatarUrl = myProfile['avatar_url'] as String?;
            _myDisplayName =
                preferred.isNotEmpty ? preferred : (display.isNotEmpty ? display : 'You');
          });
        }
      } catch (e) {
        debugPrint('MY_PROFILE_LOAD_ERROR: $e');
      }
    }

    if (_nestId == null || _nestId!.isEmpty) {
      final result = await _supabase
          .from('nest_members')
          .select('nest_id')
          .eq('user_id', _myUserId ?? '')
          .maybeSingle();
      if (result != null) {
        _nestId = result['nest_id'] as String;
        await prefs.setString('nest_id', _nestId!);
      }
    }

    await _loadMessages();
    _listenForNewMessages();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadMessages() async {
    if (_myUserId == null) return;
    final rows = await _supabase
        .from('private_messages')
        .select()
        .or(
          'and(sender_id.eq.$_myUserId,recipient_id.eq.${widget.recipientId}),'
          'and(sender_id.eq.${widget.recipientId},recipient_id.eq.$_myUserId)',
        )
        .order('created_at', ascending: true);

    if (!mounted) return;
    setState(() {
      _messages = List<Map<String, dynamic>>.from(rows);
    });
    _markIncomingAsRead();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _listenForNewMessages() {
    if (_myUserId == null) return;
    _sub = _supabase
        .from('private_messages')
        .stream(primaryKey: ['id'])
        .eq('nest_id', _nestId ?? '')
        .order('created_at')
        .listen((rows) {
          final relevant = rows.where((r) {
            final s = r['sender_id'];
            final rcv = r['recipient_id'];
            return (s == _myUserId && rcv == widget.recipientId) ||
                (s == widget.recipientId && rcv == _myUserId);
          }).toList();
          if (!mounted) return;
          setState(() => _messages = relevant);
          _markIncomingAsRead();
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        });
  }

  Future<void> _markIncomingAsRead() async {
    if (_myUserId == null) return;
    final unreadIds = _messages
        .where((m) => m['recipient_id'] == _myUserId && m['read_at'] == null)
        .map((m) => m['id'])
        .toList();
    if (unreadIds.isEmpty) return;
    await _supabase
        .from('private_messages')
        .update({'read_at': DateTime.now().toIso8601String()})
        .inFilter('id', unreadIds);
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending || _myUserId == null || _nestId == null) {
      return;
    }
    setState(() => _isSending = true);
    _controller.clear();
    try {
      await _supabase.from('private_messages').insert({
        'nest_id': _nestId,
        'sender_id': _myUserId,
        'recipient_id': widget.recipientId,
        'message_type': 'text',
        'content': text,
      });
      await _loadMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Color get _bg => _isDarkMode ? const Color(0xFF1A1612) : const Color(0xFFFDF9F4);
  Color get _bubbleMine => const Color(0xFF5DA399);
  Color get _bubbleTheirs =>
      _isDarkMode ? const Color(0xFF2E2820) : const Color(0xFFFFF8F0);
  Color get _textPrimary =>
      _isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);

  /// Small grayed-out send time shown under each bubble. Time-only for
  /// anything sent today; otherwise a short date is prefixed so an older
  /// message in the thread doesn't read as if it just arrived.
  String _formatMessageTime(Map<String, dynamic> m) {
    final raw = m['created_at'] as String?;
    if (raw == null) return '';
    final sent = DateTime.tryParse(raw)?.toLocal();
    if (sent == null) return '';
    final now = DateTime.now();
    final isToday = sent.year == now.year &&
        sent.month == now.month &&
        sent.day == now.day;
    return isToday
        ? DateFormat('h:mm a').format(sent)
        : DateFormat('MMM d, h:mm a').format(sent);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF5DA399), width: 1.5),
              ),
              child: ProfileAvatarWidget(
                avatarUrl: widget.recipientAvatarUrl,
                displayName: widget.recipientName,
                size: 33,
                borderColor: Colors.transparent,
                borderWidth: 0,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              widget.recipientName,
              style: GoogleFonts.nunitoSans(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: _textPrimary,
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? Center(
                          child: Text(
                            'Say hello to ${widget.recipientName} 👋',
                            style: GoogleFonts.nunitoSans(
                              color: _textPrimary.withAlpha(150),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final m = _messages[index];
                            final isMine = m['sender_id'] == _myUserId;
                            return _buildBubble(m, isMine);
                          },
                        ),
            ),
            _buildComposer(),
          ],
        ),
          ),
          const KeyboardDoneBarOverlay(),
        ],
      ),
    );
  }

  Widget _buildBubble(Map<String, dynamic> m, bool isMine) {
    // Avatar sits on the outer edge of each bubble (left for theirs, right
    // for mine) so who-said-what is obvious at a glance instead of relying
    // on bubble color/alignment alone -- especially important for a mostly
    // one-sided thread, where every bubble being the same color made it
    // read as one undivided block with no visible separation at all.
    final avatar = ProfileAvatarWidget(
      avatarUrl: isMine ? _myAvatarUrl : widget.recipientAvatarUrl,
      displayName: isMine ? _myDisplayName : widget.recipientName,
      size: 30,
      borderWidth: 1.5,
    );
    final bubble = Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.68),
        decoration: BoxDecoration(
          color: isMine ? _bubbleMine : _bubbleTheirs,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            LinkifiedText(
              m['content'] as String? ?? '',
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                color: isMine ? Colors.white : _textPrimary,
              ),
              // "Mine" bubbles are already teal-on-white text, so the default
              // teal link color would be invisible there -- use white instead.
              // Also skip the highlighted link background there specifically;
              // it already has its own solid teal backdrop, so a second
              // background would double up rather than help it stand out.
              linkColor: isMine ? Colors.white : null,
              showLinkBackground: !isMine,
            ),
            const SizedBox(height: 4),
            Text(
              _formatMessageTime(m),
              style: GoogleFonts.nunitoSans(
                fontSize: 11,
                color: (isMine ? Colors.white : _textPrimary).withAlpha(150),
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: isMine
            ? [bubble, const SizedBox(width: 8), avatar]
            : [avatar, const SizedBox(width: 8), bubble],
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _textPrimary.withAlpha(20))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.nunitoSans(color: _textPrimary),
              decoration: InputDecoration(
                hintText: 'Type a message…',
                hintStyle: GoogleFonts.nunitoSans(color: _textPrimary.withAlpha(120)),
                filled: true,
                fillColor: _bubbleTheirs,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _isSending ? null : _sendMessage,
            icon: _isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.send_rounded),
            color: const Color(0xFF5DA399),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF5DA399).withAlpha(30),
              shape: const CircleBorder(),
            ),
          ),
        ],
      ),
    );
  }
}
