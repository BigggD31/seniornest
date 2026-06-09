import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../family_feed_screen.dart';
import '../../../widgets/custom_image_widget.dart';
import '../../../widgets/share_preview_widget.dart';
import '../../../widgets/fullscreen_media_viewer.dart';

class MessageCardWidget extends StatefulWidget {
  const MessageCardWidget({
    super.key,
    required this.message,
    required this.isDarkMode,
    required this.onHeart,
    this.isBookmarked = false,
    this.onBookmark,
  });

  final MessageModel message;
  final bool isDarkMode;
  final VoidCallback onHeart;
  final bool isBookmarked;
  final VoidCallback? onBookmark;

  @override
  State<MessageCardWidget> createState() => _MessageCardWidgetState();
}

class _MessageCardWidgetState extends State<MessageCardWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _heartController;
  late Animation<double> _heartScale;

  @override
  void initState() {
    super.initState();
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _heartScale =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 50),
          TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 50),
        ]).animate(
          CurvedAnimation(parent: _heartController, curve: Curves.easeInOut),
        );
  }

  @override
  void dispose() {
    _heartController.dispose();
    super.dispose();
  }

  void _onHeartTap() {
    _heartController.forward(from: 0);
    widget.onHeart();
  }

  String _formatTimestamp(DateTime ts) {
    final now = DateTime.now();
    final diff = now.difference(ts);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDarkMode;
    final msg = widget.message;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242018) : const Color(0xFFFAF7F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF3D3428) : const Color(0xFFE8E0D0),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF5DA399).withAlpha(77),
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: CustomImageWidget(
                      imageUrl: msg.senderAvatarUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      semanticLabel: msg.senderAvatarLabel,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            msg.senderName,
                            style: GoogleFonts.nunitoSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? const Color(0xFFF5EDD8)
                                  : const Color(0xFF2C2417),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF5DA399).withAlpha(31),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              msg.senderRelationship,
                              style: GoogleFonts.nunitoSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF5DA399),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTimestamp(msg.timestamp),
                        style: GoogleFonts.nunitoSans(
                          fontSize: 11,
                          color: isDark
                              ? const Color(0xFF6B5E4E)
                              : const Color(0xFFA8A090),
                        ),
                      ),
                    ],
                  ),
                ),
                // Message type badge
                _MessageTypeBadge(type: msg.type),
              ],
            ),
          ),
          // Photo (if present)
          if (msg.type == MessageType.photo && msg.imageUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: GestureDetector(
                onTap: () => openFullscreenImage(
                  context: context,
                  imageUrl: msg.imageUrl,
                  semanticLabel: msg.imageSemanticLabel,
                  isDarkMode: widget.isDarkMode,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      CustomImageWidget(
                        imageUrl: msg.imageUrl,
                        width: double.infinity,
                        height: 180,
                        fit: BoxFit.cover,
                        semanticLabel: msg.imageSemanticLabel,
                      ),
                      // Tap-to-expand hint overlay
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
            ),
          // Voice note player
          if (msg.type == MessageType.voice)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _VoiceNotePlayer(isDarkMode: isDark),
            ),
          // Text content
          if (msg.content.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(
                14,
                msg.type == MessageType.photo || msg.type == MessageType.voice
                    ? 10
                    : 0,
                14,
                0,
              ),
              child: Text(
                msg.content,
                style: GoogleFonts.nunitoSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: isDark
                      ? const Color(0xFFD8C8A8)
                      : const Color(0xFF3D3020),
                  height: 1.55,
                ),
              ),
            ),
          // Footer row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                // Heart button
                GestureDetector(
                  onTap: _onHeartTap,
                  child: AnimatedBuilder(
                    animation: _heartScale,
                    builder: (context, child) =>
                        Transform.scale(scale: _heartScale.value, child: child),
                    child: Row(
                      children: [
                        Icon(
                          msg.isHearted
                              ? Icons.favorite_rounded
                              : Icons.favorite_outline_rounded,
                          size: 22,
                          color: msg.isHearted
                              ? const Color(0xFFE05C5C)
                              : isDark
                              ? const Color(0xFF6B5E4E)
                              : const Color(0xFFA8A090),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${msg.heartCount}',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: msg.isHearted
                                ? const Color(0xFFE05C5C)
                                : isDark
                                ? const Color(0xFF6B5E4E)
                                : const Color(0xFFA8A090),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Reply button
                GestureDetector(
                  onTap: () {},
                  child: Row(
                    children: [
                      Icon(
                        Icons.reply_rounded,
                        size: 20,
                        color: isDark
                            ? const Color(0xFF6B5E4E)
                            : const Color(0xFFA8A090),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Reply',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? const Color(0xFF6B5E4E)
                              : const Color(0xFFA8A090),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Share icon
                GestureDetector(
                  onTap: () => SharePreviewWidget.show(
                    context,
                    title: '${msg.senderName} shared a moment',
                    body: msg.content.isNotEmpty
                        ? msg.content
                        : '${msg.senderName} sent a ${msg.type.name}',
                    imageUrl: msg.imageUrl.isNotEmpty ? msg.imageUrl : null,
                    isDarkMode: isDark,
                  ),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4AA00).withAlpha(18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFD4AA00).withAlpha(50),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.ios_share_rounded,
                      size: 15,
                      color: Color(0xFFD4AA00),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Bookmark button — toggles filled/outline, calls onBookmark
                GestureDetector(
                  onTap: widget.onBookmark,
                  child: Icon(
                    widget.isBookmarked
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_outline_rounded,
                    size: 22,
                    color: widget.isBookmarked
                        ? const Color(0xFF5DA399)
                        : isDark
                        ? const Color(0xFF6B5E4E)
                        : const Color(0xFFA8A090),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageTypeBadge extends StatelessWidget {
  const _MessageTypeBadge({required this.type});

  final MessageType type;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String label;

    switch (type) {
      case MessageType.photo:
        icon = Icons.photo_camera_rounded;
        color = const Color(0xFF4A7FA5);
        label = 'Photo';
        break;
      case MessageType.video:
        icon = Icons.videocam_rounded;
        color = const Color(0xFF7A5FA5);
        label = 'Video';
        break;
      case MessageType.voice:
        icon = Icons.mic_rounded;
        color = const Color(0xFF5DA399);
        label = 'Voice';
        break;
      case MessageType.text:
        icon = Icons.chat_bubble_outline_rounded;
        color = const Color(0xFFA8A090);
        label = 'Message';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(31),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.nunitoSans(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceNotePlayer extends StatefulWidget {
  const _VoiceNotePlayer({required this.isDarkMode});

  final bool isDarkMode;

  @override
  State<_VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<_VoiceNotePlayer>
    with SingleTickerProviderStateMixin {
  bool _isPlaying = false;
  final double _progress = 0.0;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: widget.isDarkMode
            ? const Color(0xFF2E2820)
            : const Color(0xFFEEF8F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF5DA399).withAlpha(64),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => setState(() => _isPlaying = !_isPlaying),
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFF5DA399),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Waveform bars
                SizedBox(
                  height: 28,
                  child: AnimatedBuilder(
                    animation: _waveController,
                    builder: (context, _) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: List.generate(22, (i) {
                          final heights = [
                            8.0,
                            14.0,
                            20.0,
                            12.0,
                            18.0,
                            24.0,
                            10.0,
                            16.0,
                            22.0,
                            14.0,
                            8.0,
                            20.0,
                            16.0,
                            24.0,
                            12.0,
                            18.0,
                            10.0,
                            22.0,
                            14.0,
                            8.0,
                            16.0,
                            12.0,
                          ];
                          final h = heights[i % heights.length];
                          final isActive =
                              _isPlaying &&
                              i / 22 <= _progress + 0.1 &&
                              _waveController.value > 0.5;
                          return Container(
                            width: 3,
                            height:
                                h *
                                (_isPlaying
                                    ? (0.7 +
                                          0.3 *
                                              (_waveController.value *
                                                  (i % 3 == 0 ? 1.0 : 0.6)))
                                    : 1.0),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? const Color(0xFF5DA399)
                                  : const Color(0xFF5DA399).withAlpha(89),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '0:28',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 11,
                    color: widget.isDarkMode
                        ? const Color(0xFF6B5E4E)
                        : const Color(0xFFA8A090),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
