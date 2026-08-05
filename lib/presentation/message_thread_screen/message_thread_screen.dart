import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/custom_image_widget.dart';
import '../profile_photo_picker_screen/profile_photo_picker_screen.dart';
import '../../widgets/keyboard_done_bar.dart';

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
  String? _nestId;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isDarkMode = false;
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
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: isMine ? _bubbleMine : _bubbleTheirs,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
        ),
        child: Text(
          m['content'] as String? ?? '',
          style: GoogleFonts.nunitoSans(
            fontSize: 15,
            color: isMine ? Colors.white : _textPrimary,
          ),
        ),
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
