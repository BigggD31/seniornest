import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:camera/camera.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/app_navigation.dart';
import '../../widgets/keyboard_done_bar.dart';
import '../../services/auth_service.dart';
import '../profile_photo_picker_screen/profile_photo_picker_screen.dart';
import 'widgets/private_inbox_list_widget.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> with TickerProviderStateMixin {
  int _currentNavIndex = 1;
  bool _isSenior = false;
  bool _isNestOwner = false;
  String _displayName = '';
  bool _isDarkMode = false;
  bool _isSending = false;
  bool _hasSentMessages = false; // hides placeholder once first message sent
  bool _sampleBannerDismissed = false;
  int _topTabIndex = 0; // 0 = Messages (broadcast composer), 1 = For You (private threads)
  Map<String, dynamic>? _profileData;

  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _voiceCaptionController = TextEditingController();
  final TextEditingController _videoCaptionController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  String _selectedType = 'text';
  String? _selectedPhotoBase64;
  final List<String> _selectedRecipients = [];
  List<Map<String, dynamic>> _nestRecipients = []; // real nest members (excludes current user)

  late AnimationController _entranceController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  static const List<Map<String, String>> _quickMessages = [
    {'text': 'Thinking of you today! 💛'},
    {'text': 'Miss you so much! 🏡'},
    {'text': 'Just checking in — how are you? 💙'},
    {'text': 'Love you to the moon 🌸'},
    {'text': 'Sending you a big warm hug 🤗'},
    {'text': 'You make every day brighter ✨'},
    {'text': 'Praying for you always 🙏'},
    {'text': 'Can\'t wait to see you soon ❤️'},
  ];

  // ── Voice recording state ──────────────────────────────────────────────────
  bool _voiceIsRecording = false;
  bool _voiceHasRecording = false;
  int _voiceSeconds = 0;
  Timer? _voiceTimer;
  bool _voiceIsPlaying = false;
  Timer? _voicePlayTimer;
  int _voicePlayPosition = 0;

  // ── Audio/Video recorder instances ──────────────────────────────────────────
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  // ── Audio/Video file paths ──────────────────────────────────────────────────
  String? _voiceFilePath;
  String? _videoFilePath;
  bool _videoIsFromRecording = false;

  // ── Video recording state ──────────────────────────────────────────────────
  bool _videoIsRecording = false;
  bool _videoHasRecording = false;
  int _videoSeconds = 0;
  Timer? _videoTimer;
  bool _videoIsPlaying = false;
  Timer? _videoPlayTimer;
  int _videoPlayPosition = 0;

  static const int _maxRecordSeconds = 60;

  // Size caps for media picked from Photos/Files (not live in-app recording,
  // which is already governed by _maxRecordSeconds and never comes close to
  // these numbers). Agreed with D Von Aug 6 2026: video 750MB, photo 20MB,
  // audio 300MB (generous on purpose -- covers a real historical recording,
  // e.g. an hour-long digitized cassette tape, which can run 300-600MB in
  // an older/uncompressed format even though an hour of modern compressed
  // speech audio is only ~50-60MB).
  static const int _maxVideoBytes = 750 * 1024 * 1024;
  static const int _maxPhotoBytes = 20 * 1024 * 1024;
  // NOT YET ENFORCED ANYWHERE: there is currently no working path to pick an
  // existing audio file at all -- audio is only ever live-recorded (capped
  // at _maxRecordSeconds, nowhere near this size), and the Files picker
  // still mishandles any non-photo file as a photo (separate known bug).
  // This constant is locked in now so the agreed number isn't lost, and
  // should be wired in as part of fixing the Files picker's audio/video
  // type detection.
  // ignore: unused_field
  static const int _maxAudioBytes = 300 * 1024 * 1024;

  void _showSizeLimitError(String mediaType, int maxBytes) {
    if (!mounted) return;
    final maxMb = maxBytes ~/ (1024 * 1024);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('That $mediaType is too large. Please choose one under ${maxMb}MB.'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

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
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Curves.easeOutCubic,
          ),
        );
    _loadPrefs();
    _loadNestRecipients();
  }

  Future<void> _loadNestRecipients() async {
    try {
      final supabase = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();
      final nestId = prefs.getString('nest_id') ?? '';
      final currentUserId = supabase.auth.currentUser?.id ?? '';
      if (nestId.isEmpty) return;

      final membersResponse = await supabase
          .from('nest_members')
          .select(
              'user_id, user_profiles(display_name, preferred_name, avatar_url, relation_type, role)')
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
        final rawRelation = profile?['relation_type'] as String? ?? '';
        final memberRole = profile?['role'] as String? ?? '';
        // relation_type only applies to family members (Son/Daughter/etc.) --
        // it's legitimately empty for the senior, so don't blindly default
        // an empty value to "Family" without checking who this actually is.
        final relationship = rawRelation.isNotEmpty
            ? rawRelation[0].toUpperCase() + rawRelation.substring(1)
            : (memberRole == 'senior' ? 'Senior' : 'Family');
        loaded.add({
          'id': userId,
          'name': name,
          'avatarUrl': profile?['avatar_url'] as String? ?? '',
          'relationship': relationship,
        });
      }

      if (mounted) {
        setState(() {
          _nestRecipients = loaded;
          // Drop any selected recipients who are no longer valid nest members.
          _selectedRecipients.removeWhere(
              (id) => !loaded.any((m) => m['id'] == id));
        });
      }
    } catch (e) {
      debugPrint('SEND_NEST_RECIPIENTS_LOAD_ERROR: $e');
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final profileJson = prefs.getString(kProfilePhotoKey);
    Map<String, dynamic>? profileData;
    if (profileJson != null) {
      try {
        profileData = jsonDecode(profileJson) as Map<String, dynamic>;
      } catch (_) {}
    }
    setState(() {
      _isSenior = (prefs.getString('user_role') ?? 'senior') == 'senior';
      final joinedViaInvite = prefs.getBool('joined_via_invite') ?? false;
      _isNestOwner = !joinedViaInvite;
      _displayName = (prefs.getString('preferred_name') ?? '').isNotEmpty
          ? prefs.getString('preferred_name')!
          : (prefs.getString('display_name') ?? 'You');
      _isDarkMode = prefs.getBool('dark_mode') ?? false;
      _hasSentMessages = prefs.getBool('has_sent_messages') ?? false;
      _sampleBannerDismissed = prefs.getBool('messages_sample_banner_dismissed') ?? false;
      _profileData = profileData;
    });
    _entranceController.forward();
  }

  @override
  void dispose() {
    _voiceTimer?.cancel();
    _voicePlayTimer?.cancel();
    _videoTimer?.cancel();
    _videoPlayTimer?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _videoPlayerController?.dispose();
    _entranceController.dispose();
    _messageController.dispose();
    _voiceCaptionController.dispose();
    _videoCaptionController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  Color get _bg =>
      _isDarkMode ? const Color(0xFF1A1612) : const Color(0xFFFDF9F4);
  Color get _surface =>
      _isDarkMode ? const Color(0xFF242018) : const Color(0xFFFAF3EC);
  Color get _cardBorder =>
      _isDarkMode ? const Color(0xFF3D3428) : const Color(0xFFEDE5D8);
  Color get _textPrimary =>
      _isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      _isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  void _toggleRecipient(String id) {
    setState(() {
      if (_selectedRecipients.contains(id)) {
        _selectedRecipients.remove(id);
      } else {
        _selectedRecipients.add(id);
      }
    });
  }

  // ── Voice recording modal ──────────────────────────────────────────────────
  Future<void> _showVoiceRecordingModal() async {
    // Reset voice state before opening
    _voiceTimer?.cancel();
    _voicePlayTimer?.cancel();
    setState(() {
      _voiceIsRecording = false;
      _voiceHasRecording = false;
      _voiceSeconds = 0;
      _voiceIsPlaying = false;
      _voicePlayPosition = 0;
    });

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            void startRecording() {
              _startVoiceRecording(setModalState).then((_) {
                setModalState(() {});
              });
            }

            void stopRecording() {
              _stopVoiceRecording().then((_) {
                setModalState(() {});
              });
            }

            void retake() {
              _retakeVoice().then((_) {
                setModalState(() {});
              });
            }

            void togglePlayback() async {
              if (_voiceIsPlaying) {
                await _audioPlayer.stop();
                _voicePlayTimer?.cancel();
                setModalState(() => _voiceIsPlaying = false);
              } else {
                if (_voiceFilePath == null) return;
                setModalState(() {
                  _voiceIsPlaying = true;
                  _voicePlayPosition = 0;
                });
                try {
                  await _audioPlayer.setFilePath(_voiceFilePath!);
                  await _audioPlayer.play();
                  _voicePlayTimer = Timer.periodic(const Duration(seconds: 1), (t) {
                    if (_voicePlayPosition >= _voiceSeconds - 1) {
                      t.cancel();
                      _audioPlayer.stop();
                      setModalState(() {
                        _voiceIsPlaying = false;
                        _voicePlayPosition = 0;
                      });
                    } else {
                      setModalState(() => _voicePlayPosition++);
                    }
                  });
                } catch (e) {
                  print('AUDIO PLAYBACK ERROR: $e');
                  setModalState(() => _voiceIsPlaying = false);
                }
              }
            }

            final bg = _isDarkMode
                ? const Color(0xFF242018)
                : const Color(0xFFFAF3EC);
            final cardBorder = _isDarkMode
                ? const Color(0xFF3D3428)
                : const Color(0xFFEDE5D8);
            final surface = _isDarkMode
                ? const Color(0xFF1A1612)
                : const Color(0xFFFDF9F4);
            final textPrimary = _isDarkMode
                ? const Color(0xFFF5EDD8)
                : const Color(0xFF2C2417);
            final textSecondary = _isDarkMode
                ? const Color(0xFFB8A888)
                : const Color(0xFF6B5E4E);

            return KeyboardDoneBar(
              child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(40),
                    blurRadius: 30,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 20, 24, 32 + MediaQuery.of(ctx).viewInsets.bottom),
                child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle bar
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cardBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Header
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8A0A0).withAlpha(38),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.mic_rounded,
                            color: Color(0xFFE8A0A0),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Voice Message',
                              style: GoogleFonts.nunitoSans(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: textPrimary,
                              ),
                            ),
                            Text(
                              'Up to 60 seconds',
                              style: GoogleFonts.nunitoSans(
                                fontSize: 12,
                                color: const Color(0xFFE8A0A0),
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            _voiceTimer?.cancel();
                            _voicePlayTimer?.cancel();
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: cardBorder.withAlpha(120),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              color: textSecondary,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // Recording area
                    if (!_voiceHasRecording && !_voiceIsRecording) ...[
                      // Idle state
                      GestureDetector(
                        onTap: startRecording,
                        child: Container(
                          width: 90,
                          height: 90,
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
                      const SizedBox(height: 16),
                      Text(
                        'Tap to start recording',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 15,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Your family will love hearing your voice 🎙️',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 12,
                          color: const Color(0xFF9B8FD4),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ] else if (_voiceIsRecording) ...[
                      // Recording active
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 96,
                            height: 96,
                            child: CircularProgressIndicator(
                              value: _voiceSeconds / _maxRecordSeconds,
                              strokeWidth: 4,
                              backgroundColor: const Color(
                                0xFFE8A0A0,
                              ).withAlpha(40),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFFE8A0A0),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: stopRecording,
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
                      const SizedBox(height: 16),
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
                            'Recording  ${_formatDuration(_voiceSeconds)} / 1:00',
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
                          color: textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ] else ...[
                      // Preview state
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: _isDarkMode
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
                              onTap: togglePlayback,
                              child: Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8A0A0).withAlpha(40),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFFE8A0A0),
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(
                                  _voiceIsPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: const Color(0xFFE05C5C),
                                  size: 28,
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
                                      value: _voiceIsPlaying
                                          ? _voicePlayPosition /
                                                (_voiceSeconds > 0
                                                    ? _voiceSeconds
                                                    : 1)
                                          : 0,
                                      minHeight: 6,
                                      backgroundColor: const Color(
                                        0xFFE8A0A0,
                                      ).withAlpha(40),
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                            Color(0xFFE8A0A0),
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _voiceIsPlaying
                                            ? _formatDuration(
                                                _voicePlayPosition,
                                              )
                                            : '0:00',
                                        style: GoogleFonts.nunitoSans(
                                          fontSize: 11,
                                          color: textSecondary,
                                        ),
                                      ),
                                      Text(
                                        _formatDuration(_voiceSeconds),
                                        style: GoogleFonts.nunitoSans(
                                          fontSize: 11,
                                          color: textSecondary,
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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cardBorder, width: 1.5),
                        ),
                        child: TextField(
                          textCapitalization: TextCapitalization.sentences,
                          controller: _voiceCaptionController,
                          maxLines: 3,
                          minLines: 1,
                          style: GoogleFonts.nunitoSans(fontSize: 15, color: textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Add a note (optional)...',
                            hintStyle: GoogleFonts.nunitoSans(
                              fontSize: 15,
                              color: textSecondary,
                              fontStyle: FontStyle.italic,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: retake,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: cardBorder,
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.refresh_rounded,
                                      size: 18,
                                      color: textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Retake',
                                      style: GoogleFonts.nunitoSans(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () async {
                                _voicePlayTimer?.cancel();
                                final path = _voiceFilePath;
                                final caption = _voiceCaptionController.text.trim();
                                Navigator.pop(ctx);
                                await _sendMessage(overrideType: 'voice', overridePath: path, overrideContent: caption);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF5DA399),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF5DA399,
                                      ).withAlpha(60),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.send_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Send',
                                      style: GoogleFonts.nunitoSans(
                                        fontSize: 15,
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
                ),
              ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Video recording modal ──────────────────────────────────────────────────
  Future<void> _showVideoRecordingModal() async {
    // Reset video state before opening
    _videoTimer?.cancel();
    _videoPlayTimer?.cancel();
    setState(() {
      _videoIsRecording = false;
      _videoHasRecording = false;
      _videoSeconds = 0;
      _videoIsPlaying = false;
      _videoPlayPosition = 0;
    });

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            void startRecording() {
              _startVideoRecording(setModalState).then((_) {
                setModalState(() {});
              });
            }

            void stopRecording() {
              _stopVideoRecording().then((_) {
                setModalState(() {});
              });
            }

            void retake() {
              _retakeVideo().then((_) {
                setModalState(() {});
              });
            }

            void togglePlayback() async {
              if (_videoIsPlaying) {
                await _videoPlayerController?.pause();
                _videoPlayTimer?.cancel();
                setModalState(() => _videoIsPlaying = false);
              } else {
                if (_videoPlayerController == null) return;
                setModalState(() {
                  _videoIsPlaying = true;
                  _videoPlayPosition = 0;
                });
                try {
                  await _videoPlayerController!.seekTo(Duration.zero);
                  await _videoPlayerController!.play();
                  _videoPlayTimer = Timer.periodic(const Duration(seconds: 1), (t) {
                    if (_videoPlayPosition >= _videoSeconds - 1) {
                      t.cancel();
                      _videoPlayerController?.pause();
                      setModalState(() {
                        _videoIsPlaying = false;
                        _videoPlayPosition = 0;
                      });
                    } else {
                      setModalState(() => _videoPlayPosition++);
                    }
                  });
                } catch (e) {
                  print('VIDEO PLAYBACK ERROR: $e');
                  setModalState(() => _videoIsPlaying = false);
                }
              }
            }

            final bg = _isDarkMode
                ? const Color(0xFF242018)
                : const Color(0xFFFAF3EC);
            final cardBorder = _isDarkMode
                ? const Color(0xFF3D3428)
                : const Color(0xFFEDE5D8);
            final surface = _isDarkMode
                ? const Color(0xFF1A1612)
                : const Color(0xFFFDF9F4);
            final textPrimary = _isDarkMode
                ? const Color(0xFFF5EDD8)
                : const Color(0xFF2C2417);
            final textSecondary = _isDarkMode
                ? const Color(0xFFB8A888)
                : const Color(0xFF6B5E4E);

            return KeyboardDoneBar(
              child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(40),
                    blurRadius: 30,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 20, 24, 32 + MediaQuery.of(ctx).viewInsets.bottom),
                child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle bar
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cardBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Header
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF9B8FD4).withAlpha(38),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.videocam_rounded,
                            color: Color(0xFF9B8FD4),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Video Message',
                              style: GoogleFonts.nunitoSans(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: textPrimary,
                              ),
                            ),
                            Text(
                              'Up to 60 seconds',
                              style: GoogleFonts.nunitoSans(
                                fontSize: 12,
                                color: const Color(0xFF9B8FD4),
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            _videoTimer?.cancel();
                            _videoPlayTimer?.cancel();
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: cardBorder.withAlpha(120),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              color: textSecondary,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Video area
                    if (!_videoHasRecording && !_videoIsRecording) ...[
                      // Idle state — matches Voice Message popup layout
                      GestureDetector(
                        onTap: startRecording,
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            color: const Color(0xFF9B8FD4).withAlpha(38),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF9B8FD4).withAlpha(128),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.videocam_rounded,
                            color: Color(0xFF9B8FD4),
                            size: 40,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Tap to start recording',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 15,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'A face-to-face moment they\'ll treasure',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 12,
                          color: const Color(0xFF9B8FD4),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ] else if (_videoIsRecording) ...[
                      // Recording active
                      Container(
                        height: 380,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1020),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFE05C5C).withAlpha(180),
                            width: 2,
                          ),
                        ),
                        child: Stack(
                          children: [
                            // Real camera preview
                            if (_cameraController != null && _cameraController!.value.isInitialized)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: SizedBox(
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
                              )
                            else
                              const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white54,
                                ),
                              ),
                            Positioned(
                              top: 10,
                              left: 12,
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFE05C5C),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'REC  ${_formatDuration(_videoSeconds)}',
                                    style: GoogleFonts.nunitoSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFFE05C5C),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(14),
                                ),
                                child: LinearProgressIndicator(
                                  value: _videoSeconds / _maxRecordSeconds,
                                  minHeight: 4,
                                  backgroundColor: Colors.white12,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        Color(0xFFE05C5C),
                                      ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: stopRecording,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE05C5C).withAlpha(20),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: const Color(0xFFE05C5C),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.stop_rounded,
                                color: Color(0xFFE05C5C),
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Stop Recording',
                                style: GoogleFonts.nunitoSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFE05C5C),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      // Preview state
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                        height: 380,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1020),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF9B8FD4).withAlpha(120),
                            width: 1.5,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Real video player
                            if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized)
                              AspectRatio(
                                aspectRatio: _videoPlayerController!.value.aspectRatio,
                                child: _videoIsFromRecording
                                    ? Transform(
                                        alignment: Alignment.center,
                                        transform: Matrix4.rotationY(3.14159),
                                        child: VideoPlayer(_videoPlayerController!),
                                      )
                                    : VideoPlayer(_videoPlayerController!),
                              ),
                            // Play/pause overlay
                            GestureDetector(
                              onTap: togglePlayback,
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: Colors.black45,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white70, width: 2),
                                ),
                                child: Icon(
                                  _videoIsPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 8,
                              child: Text(
                                _videoIsPlaying
                                    ? '${_formatDuration(_videoPlayPosition)} / ${_formatDuration(_videoSeconds)}'
                                    : _formatDuration(_videoSeconds),
                                style: GoogleFonts.nunitoSans(fontSize: 12, color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cardBorder, width: 1.5),
                        ),
                        child: TextField(
                          textCapitalization: TextCapitalization.sentences,
                          controller: _videoCaptionController,
                          maxLines: 3,
                          minLines: 1,
                          style: GoogleFonts.nunitoSans(fontSize: 15, color: textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Add a note (optional)...',
                            hintStyle: GoogleFonts.nunitoSans(
                              fontSize: 15,
                              color: textSecondary,
                              fontStyle: FontStyle.italic,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: retake,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: cardBorder,
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.refresh_rounded,
                                      size: 18,
                                      color: textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Retake',
                                      style: GoogleFonts.nunitoSans(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () async {
                                _videoPlayTimer?.cancel();
                                final path = _videoFilePath;
                                final caption = _videoCaptionController.text.trim();
                                Navigator.pop(ctx);
                                await _sendMessage(overrideType: 'video', overridePath: path, overrideContent: caption);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF5DA399),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF5DA399,
                                      ).withAlpha(60),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.send_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Send',
                                      style: GoogleFonts.nunitoSans(
                                        fontSize: 15,
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
                ),
              ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showPhotoOptionsSheet() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bg = _isDarkMode
            ? const Color(0xFF242018)
            : const Color(0xFFFAF3EC);
        final cardBorder = _isDarkMode
            ? const Color(0xFF3D3428)
            : const Color(0xFFEDE5D8);
        final textPrimary = _isDarkMode
            ? const Color(0xFFF5EDD8)
            : const Color(0xFF2C2417);
        final textSecondary = _isDarkMode
            ? const Color(0xFFB8A888)
            : const Color(0xFF6B5E4E);

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(40),
                blurRadius: 30,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AA00).withAlpha(38),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.image_rounded,
                        color: Color(0xFFD4AA00),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Add a Photo',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: cardBorder.withAlpha(120),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          color: textSecondary,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _sheetPhotoOption(
                  ctx: ctx,
                  icon: Icons.photo_library_rounded,
                  label: 'Photo Library',
                  subtitle: 'Choose from your device gallery',
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  onTap: () => Navigator.pop(ctx, 'gallery'),
                ),
                const SizedBox(height: 12),
                _sheetPhotoOption(
                  ctx: ctx,
                  icon: Icons.camera_alt_rounded,
                  label: 'Take Photo',
                  subtitle: 'Use your camera to take a new photo',
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  onTap: () => Navigator.pop(ctx, 'camera'),
                ),
                const SizedBox(height: 12),
                _sheetPhotoOption(
                  ctx: ctx,
                  icon: Icons.folder_open_rounded,
                  label: 'Choose File',
                  subtitle: 'Browse files on your device',
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  onTap: () => Navigator.pop(ctx, 'files'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    if (result == 'gallery') {
      await _pickPhotoFromGallery();
    } else if (result == 'camera') {
      await _pickPhotoFromCamera();
    } else if (result == 'files') {
      await _pickPhotoFromFiles();
    }
  }

  Widget _sheetPhotoOption({
    required BuildContext ctx,
    required IconData icon,
    required String label,
    required String subtitle,
    required Color textPrimary,
    required Color textSecondary,
    required VoidCallback onTap,
  }) {
    final optionBg = _isDarkMode
        ? const Color(0xFF2A2218)
        : const Color(0xFFF5F0E8);
    final optionBorder = _isDarkMode
        ? const Color(0xFF3A3228)
        : const Color(0xFFE8E0D0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: optionBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: optionBorder, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF5DA399).withAlpha(26),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF5DA399), size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 12,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  /// Opens photo/video library — shows both photos and videos.
  Future<void> _pickPhotoFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickMedia();
    if (picked != null && mounted) {
      final isVideo = picked.path.toLowerCase().endsWith('.mp4') ||
          picked.path.toLowerCase().endsWith('.mov') ||
          picked.path.toLowerCase().endsWith('.m4v');
      if (isVideo) {
        final fileSize = await File(picked.path).length();
        if (fileSize > _maxVideoBytes) {
          _showSizeLimitError('video', _maxVideoBytes);
          return;
        }
        setState(() {
          _videoFilePath = picked.path;
          _videoIsFromRecording = false;
          _selectedType = 'video';
          _videoHasRecording = true;
        });
        _videoPlayerController = VideoPlayerController.file(File(picked.path));
        await _videoPlayerController!.initialize();
        // _videoSeconds is otherwise only ever set by the live-recording
        // timer -- for an uploaded video it was staying at 0 (or whatever
        // was left over from a prior recording attempt), which made the
        // play button think the video was already over almost immediately.
        setState(() {
          _videoSeconds = _videoPlayerController!.value.duration.inSeconds;
        });
      } else {
        final bytes = await picked.readAsBytes();
        if (bytes.length > _maxPhotoBytes) {
          _showSizeLimitError('photo', _maxPhotoBytes);
          return;
        }
        setState(() {
          _selectedPhotoBase64 = base64Encode(bytes);
          _selectedType = 'photo';
        });
      }
    }
  }

  /// Opens camera directly — no action sheet.
  Future<void> _pickPhotoFromCamera() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera);
    if (picked != null && mounted) {
      final bytes = await picked.readAsBytes();
      if (bytes.length > _maxPhotoBytes) {
        _showSizeLimitError('photo', _maxPhotoBytes);
        return;
      }
      setState(() {
        _selectedPhotoBase64 = base64Encode(bytes);
        _selectedType = 'photo';
      });
    }
  }

  /// Opens file picker directly — opens iOS Files browser / Android file browser.
  Future<void> _pickPhotoFromFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty && mounted) {
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes != null) {
        if (bytes.length > _maxPhotoBytes) {
          _showSizeLimitError('photo', _maxPhotoBytes);
          return;
        }
        setState(() {
          _selectedPhotoBase64 = base64Encode(bytes);
          _selectedType = 'photo';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = keyboardHeight > 0;

    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: AppNavigation(
        currentIndex: _currentNavIndex,
        onTap: _onNavTap,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.translucent,
            ),
          ),
          const KeyboardDoneBarOverlay(),
          SafeArea(
            bottom: false,
            child: AnimatedBuilder(
              animation: _entranceController,
              builder: (context, child) => SlideTransition(
                position: _slideAnim,
                child: Opacity(opacity: _fadeAnim.value, child: child),
              ),
              child: Column(
                children: [
                  _buildTopBar(isTablet),
                  _buildTopTabSelector(isTablet),
                  Expanded(
                    child: _topTabIndex == 1
                        ? SingleChildScrollView(
                            padding: EdgeInsets.only(
                              left: isTablet ? 28 : 20,
                              right: isTablet ? 28 : 20,
                              top: 16,
                              bottom: kBottomNavigationBarHeight + 24,
                            ),
                            child: PrivateInboxListWidget(isDarkMode: _isDarkMode),
                          )
                        : SingleChildScrollView(
                      padding: EdgeInsets.only(
                        left: isTablet ? 28 : 20,
                        right: isTablet ? 28 : 20,
                        top: 16,
                        bottom: kBottomNavigationBarHeight + 24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!_hasSentMessages && !_sampleBannerDismissed)
                            _buildMessagesSampleBanner(),
                          if (!_hasSentMessages)
                            _buildFirstMessagePlaceholder(),
                          _buildMessageTypeBoxes(),
                          const SizedBox(height: 22),
                          _buildSendToSelector(),
                          const SizedBox(height: 22),
                          _buildMessageComposer(isTablet),
                          const SizedBox(height: 16),
                          _buildSendFAB(),
                          if (_selectedType == 'text') ...[
                            const SizedBox(height: 22),
                            _buildQuickMessages(),
                          ],
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Keyboard dismiss button — appears just above the nav bar when keyboard is open
          if (isKeyboardOpen)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: _isDarkMode
                    ? const Color(0xFF1E1A14)
                    : const Color(0xFFF5EFE6),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => _textFocusNode.unfocus(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 28,
                        color: _isDarkMode
                            ? const Color(0xFFB8A888)
                            : const Color(0xFF6B5E4E),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: null,
    );
  }

  Widget _buildTopTabSelector(bool isTablet) {
    return Container(
      margin: EdgeInsets.fromLTRB(isTablet ? 28 : 20, 12, isTablet ? 28 : 20, 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _isDarkMode ? const Color(0xFF242018) : const Color(0xFFF0E9DC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(child: _buildTopTabButton('Everyone', 0)),
          Expanded(child: _buildTopTabButton('My Messages', 1, icon: Icons.mail_outline_rounded)),
        ],
      ),
    );
  }

  Widget _buildTopTabButton(String label, int index, {IconData? icon}) {
    final isSelected = _topTabIndex == index;
    final color = isSelected
        ? Colors.white
        : (_isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E));
    return GestureDetector(
      onTap: () => setState(() => _topTabIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF5DA399) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: GoogleFonts.nunitoSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
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
      decoration: BoxDecoration(
        color: _bg,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4AA00).withAlpha(15),
            blurRadius: 16,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Share',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('💌', style: const TextStyle(fontSize: 20)),
                ],
              ),
              Text(
                _isSenior
                    ? 'Share a moment with your family'
                    : 'Send love to your loved one',
                style: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  color: _textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE8A0A0).withAlpha(30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFE8A0A0).withAlpha(80),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.send_rounded,
              color: Color(0xFFE05C5C),
              size: 20,
            ),
          ),
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

  Future<void> _dismissMessagesSampleBanner() async {
    setState(() => _sampleBannerDismissed = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('messages_sample_banner_dismissed', true);
  }

  Widget _buildMessagesSampleBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFD4AA00).withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD4AA00).withAlpha(60), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded, color: Color(0xFFB8860B), size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This is where your messages will appear once you start sending them.',
              style: GoogleFonts.nunitoSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: _isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _dismissMessagesSampleBanner,
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close_rounded, color: Color(0xFFB8860B), size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFirstMessagePlaceholder() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      decoration: BoxDecoration(
        color: _isDarkMode ? const Color(0xFF2E2820) : const Color(0xFFFFF8EC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFD4AA00).withAlpha(80),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          const Text('💌', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 14),
          Text(
            'Send your first message — your family is waiting to hear from you',
            style: GoogleFonts.nunitoSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _isDarkMode
                  ? const Color(0xFFD4AA00)
                  : const Color(0xFFB8860B),
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageTypeBoxes() {
    final types = [
      {
        'id': 'text',
        'icon': Icons.chat_bubble_rounded,
        'label': 'Text',
        'color': const Color(0xFF5DA399),
        'bgLight': const Color(0xFFEDF7F6),
        'bgDark': const Color(0xFF1E2E2C),
        'emoji': '💬',
      },
      {
        'id': 'photo',
        'icon': Icons.image_rounded,
        'label': 'Photo',
        'color': const Color(0xFFD4AA00),
        'bgLight': const Color(0xFFFFF8E1),
        'bgDark': const Color(0xFF2E2A1A),
        'emoji': '🖼️',
      },
      {
        'id': 'voice',
        'icon': Icons.mic_rounded,
        'label': 'Voice',
        'color': const Color(0xFFE8A0A0),
        'bgLight': const Color(0xFFFFF0F0),
        'bgDark': const Color(0xFF2E2020),
        'emoji': '🎙️',
      },
      {
        'id': 'video',
        'icon': Icons.play_circle_filled_rounded,
        'label': 'Video',
        'color': const Color(0xFF9B8FD4),
        'bgLight': const Color(0xFFF3F0FF),
        'bgDark': const Color(0xFF221E30),
        'emoji': '🎥',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What would you like to send?',
          style: GoogleFonts.nunitoSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _textSecondary,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: List.generate(types.length, (i) {
            final type = types[i];
            final isSelected = _selectedType == type['id'];
            final color = type['color'] as Color;
            final bgColor = _isDarkMode
                ? type['bgDark'] as Color
                : type['bgLight'] as Color;

            return Expanded(
              child: GestureDetector(
                onTap: () {
                  final typeId = type['id'] as String;
                  if (typeId == 'voice') {
                    setState(() => _selectedType = 'voice');
                    _showVoiceRecordingModal().then((_) {
                      setState(() => _selectedType = 'text');
                    });
                  } else if (typeId == 'video') {
                    setState(() => _selectedType = 'video');
                    _showVideoRecordingModal().then((_) {
                      setState(() => _selectedType = 'text');
                    });
                  } else if (typeId == 'photo') {
                    _showPhotoOptionsSheet();
                  } else {
                    setState(() => _selectedType = typeId);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  margin: EdgeInsets.only(right: i < types.length - 1 ? 10 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: isSelected ? bgColor : _surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isSelected ? color.withAlpha(200) : _cardBorder,
                      width: isSelected ? 2.0 : 1.5,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: color.withAlpha(45),
                              blurRadius: 14,
                              spreadRadius: 1,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withAlpha(8),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color.withAlpha(40)
                              : color.withAlpha(20),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          type['icon'] as IconData,
                          color: isSelected ? color : color.withAlpha(160),
                          size: 22,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        type['label'] as String,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: isSelected ? color : _textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildSendToSelector() {
    final bool everyoneSelected = _selectedRecipients.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Send To:',
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            if (!everyoneSelected)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8A0A0).withAlpha(30),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFE8A0A0).withAlpha(100),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  '${_selectedRecipients.length} selected',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFE8A0A0),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Everyone option
        GestureDetector(
          onTap: () => setState(() => _selectedRecipients.clear()),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: everyoneSelected
                  ? const Color(0xFFE8A0A0).withAlpha(22)
                  : _surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: everyoneSelected
                    ? const Color(0xFFE8A0A0).withAlpha(200)
                    : _cardBorder,
                width: everyoneSelected ? 2.0 : 1.5,
              ),
              boxShadow: everyoneSelected
                  ? [
                      BoxShadow(
                        color: const Color(0xFFE8A0A0).withAlpha(30),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8A0A0).withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('👨‍👩‍👧‍👦', style: TextStyle(fontSize: 20)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Everyone',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _textPrimary,
                        ),
                      ),
                      Text(
                        'All family members receive your message',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 12,
                          color: _textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: everyoneSelected
                        ? const Color(0xFFE8A0A0)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: everyoneSelected
                          ? const Color(0xFFE8A0A0)
                          : _cardBorder,
                      width: 2,
                    ),
                  ),
                  child: everyoneSelected
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 10,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Individual recipients in a horizontal scroll — real nest members only.
        // Nobody to pick from yet (solo nest) shows nothing here; Everyone still works.
        if (_nestRecipients.isNotEmpty) SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _nestRecipients.length,
            itemBuilder: (context, index) {
              final r = _nestRecipients[index];
              final isSelected = _selectedRecipients.contains(r['id']);
              return GestureDetector(
                onTap: () => _toggleRecipient(r['id'] as String),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  margin: EdgeInsets.only(
                    right: index < _nestRecipients.length - 1 ? 10 : 0,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF5DA399).withAlpha(22)
                        : _surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF5DA399).withAlpha(200)
                          : _cardBorder,
                      width: isSelected ? 2.0 : 1.5,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFF5DA399).withAlpha(30),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : [],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        children: [
                          ProfileAvatarWidget(
                            avatarUrl: r['avatarUrl'] as String?,
                            displayName: r['name'] as String? ?? '',
                            size: 44,
                          ),
                          if (isSelected)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF5DA399),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 10,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        (r['name'] as String? ?? '').isNotEmpty
                            ? r['name'] as String
                            : 'Family Member',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMessageComposer(bool isTablet) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _cardBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4AA00).withAlpha(18),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _selectedType == 'voice'
          ? _buildVoiceRecorder()
          : _selectedType == 'photo'
          ? _buildPhotoComposer()
          : _selectedType == 'video'
          ? _buildVideoComposer()
          : _buildTextComposer(),
    );
  }

  Widget _buildTextComposer() {
    return TextField(
      textCapitalization: TextCapitalization.sentences,
      controller: _messageController,
      focusNode: _textFocusNode,
      maxLines: 5,
      minLines: 4,
      style: GoogleFonts.nunitoSans(
        fontSize: 16,
        color: _textPrimary,
        height: 1.6,
      ),
      decoration: InputDecoration(
        hintText: 'Write something warm and loving...',
        hintStyle: GoogleFonts.nunitoSans(
          fontSize: 16,
          color: _isDarkMode
              ? const Color(0xFF6B5E4E)
              : const Color(0xFFBBAA98),
          height: 1.6,
          fontStyle: FontStyle.italic,
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildPhotoComposer() {
    final photoBytes = _selectedPhotoBase64 != null
        ? (() {
            try {
              return base64Decode(_selectedPhotoBase64!);
            } catch (_) {
              return null;
            }
          })()
        : null;

    if (photoBytes == null) {
      return _buildTextComposer();
    }

    return Column(
      children: [
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                photoBytes,
                fit: BoxFit.cover,
                width: double.infinity,
                height: 140,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => setState(() => _selectedPhotoBase64 = null),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(140),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          textCapitalization: TextCapitalization.sentences,
          controller: _messageController,
          maxLines: 2,
          style: GoogleFonts.nunitoSans(fontSize: 15, color: _textPrimary),
          decoration: InputDecoration(
            hintText: 'Write something warm and loving...',
            hintStyle: GoogleFonts.nunitoSans(
              fontSize: 15,
              color: _isDarkMode
                  ? const Color(0xFF6B5E4E)
                  : const Color(0xFFBBAA98),
              fontStyle: FontStyle.italic,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  // ── Voice recording helpers ────────────────────────────────────────────────
  Future<void> _startVoiceRecording([StateSetter? modalSetState]) async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        debugPrint('Microphone permission denied');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      setState(() {
        _voiceIsRecording = true;
        _voiceHasRecording = false;
        _voiceSeconds = 0;
        _voiceIsPlaying = false;
        _voicePlayPosition = 0;
        _voiceFilePath = path;
      });
      _voiceTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_voiceSeconds >= _maxRecordSeconds - 1) {
          _stopVoiceRecording();
        } else {
          if (mounted) {
            setState(() => _voiceSeconds++);
            modalSetState?.call(() {});
          }
        }
      });
    } catch (e) {
      debugPrint('Start voice recording error: $e');
    }
  }

  Future<void> _stopVoiceRecording() async {
    _voiceTimer?.cancel();
    try {
      await _audioRecorder.stop();
    } catch (e) {
      debugPrint('Stop voice recording error: $e');
    }
    setState(() {
      _voiceIsRecording = false;
      _voiceHasRecording = true;
    });
  }

  Future<void> _retakeVoice() async {
    _voicePlayTimer?.cancel();
    try {
      await _audioRecorder.stop();
    } catch (_) {}
    setState(() {
      _voiceIsRecording = false;
      _voiceHasRecording = false;
      _voiceSeconds = 0;
      _voiceIsPlaying = false;
      _voicePlayPosition = 0;
      _voiceFilePath = null;
    });
  }

  void _toggleVoicePlayback() {
    if (_voiceIsPlaying) {
      _voicePlayTimer?.cancel();
      setState(() => _voiceIsPlaying = false);
    } else {
      setState(() {
        _voiceIsPlaying = true;
        _voicePlayPosition = 0;
      });
      _voicePlayTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_voicePlayPosition >= _voiceSeconds - 1) {
          t.cancel();
          setState(() {
            _voiceIsPlaying = false;
            _voicePlayPosition = 0;
          });
        } else {
          setState(() => _voicePlayPosition++);
        }
      });
    }
  }

  // ── Video recording helpers ────────────────────────────────────────────────
  CameraController? _cameraController;
  VideoPlayerController? _videoPlayerController;

  Future<void> _startVideoRecording([StateSetter? modalSetState]) async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint('No cameras available');
        return;
      }
      // Default to front camera if available
      final camera = cameras.length > 1 ? cameras[1] : cameras.first;
      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await _cameraController!.initialize();
      await _cameraController!.startVideoRecording();
      setState(() {
        _videoIsRecording = true;
        _videoHasRecording = false;
        _videoSeconds = 0;
        _videoIsPlaying = false;
        _videoPlayPosition = 0;
      });
      _videoTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_videoSeconds >= _maxRecordSeconds - 1) {
          _stopVideoRecording();
        } else {
          if (mounted) {
            setState(() => _videoSeconds++);
            modalSetState?.call(() {});
          }
        }
      });
    } catch (e) {
      debugPrint('Start video recording error: $e');
    }
  }

  Future<void> _stopVideoRecording() async {
    _videoTimer?.cancel();
    try {
      if (_cameraController != null && _cameraController!.value.isRecordingVideo) {
        final file = await _cameraController!.stopVideoRecording();
        setState(() {
          _videoFilePath = file.path;
          _videoIsFromRecording = true;
        });
        // Initialize video player for playback
        _videoPlayerController = VideoPlayerController.file(File(file.path));
        await _videoPlayerController!.initialize();
      }
      await _cameraController?.dispose();
      _cameraController = null;
    } catch (e) {
      debugPrint('Stop video recording error: $e');
    }
    setState(() {
      _videoIsRecording = false;
      _videoHasRecording = true;
    });
  }

  Future<void> _retakeVideo() async {
    _videoPlayTimer?.cancel();
    try {
      if (_cameraController != null && _cameraController!.value.isRecordingVideo) {
        await _cameraController!.stopVideoRecording();
      }
      await _cameraController?.dispose();
      _cameraController = null;
    } catch (_) {}
    setState(() {
      _videoIsRecording = false;
      _videoHasRecording = false;
      _videoSeconds = 0;
      _videoIsPlaying = false;
      _videoPlayPosition = 0;
      _videoFilePath = null;
      _videoIsFromRecording = false;
    });
  }

  void _toggleVideoPlayback() async {
    if (_videoPlayerController == null) return;
    if (_videoIsPlaying) {
      await _videoPlayerController!.pause();
      _videoPlayTimer?.cancel();
      setState(() => _videoIsPlaying = false);
    } else {
      setState(() {
        _videoIsPlaying = true;
        _videoPlayPosition = 0;
      });
      try {
        await _videoPlayerController!.seekTo(Duration.zero);
        await _videoPlayerController!.play();
      } catch (e) {
        print('VIDEO PLAYBACK ERROR: $e');
        setState(() => _videoIsPlaying = false);
        return;
      }
      _videoPlayTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_videoPlayPosition >= _videoSeconds - 1) {
          t.cancel();
          _videoPlayerController?.pause();
          setState(() {
            _videoIsPlaying = false;
            _videoPlayPosition = 0;
          });
        } else {
          setState(() => _videoPlayPosition++);
        }
      });
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildVoiceRecorder() {
    if (_voiceHasRecording) {
      return _buildVoicePreview();
    }
    if (_voiceIsRecording) {
      return _buildVoiceRecordingActive();
    }
    return _buildVoiceIdle();
  }

  Widget _buildVoiceIdle() {
    return Column(
      children: [
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _startVoiceRecording,
          child: Container(
            width: 80,
            height: 80,
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
              size: 36,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Tap to start recording',
          style: GoogleFonts.nunitoSans(fontSize: 15, color: _textSecondary),
        ),
        const SizedBox(height: 6),
        Text(
          'Your family will love hearing your voice 🎙️',
          textAlign: TextAlign.center,
          style: GoogleFonts.nunitoSans(
            fontSize: 12,
            color: const Color(0xFF9B8FD4),
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Up to 60 seconds',
          style: GoogleFonts.nunitoSans(
            fontSize: 11,
            color: _textSecondary.withAlpha(160),
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildVoiceRecordingActive() {
    final progress = _voiceSeconds / _maxRecordSeconds;
    return Column(
      children: [
        const SizedBox(height: 16),
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 88,
              height: 88,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 4,
                backgroundColor: const Color(0xFFE8A0A0).withAlpha(40),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFE8A0A0),
                ),
              ),
            ),
            GestureDetector(
              onTap: _stopVoiceRecording,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8A0A0).withAlpha(50),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE8A0A0), width: 2),
                ),
                child: const Icon(
                  Icons.stop_rounded,
                  color: Color(0xFFE05C5C),
                  size: 32,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
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
              'Recording  ${_formatDuration(_voiceSeconds)} / 1:00',
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
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildVoicePreview() {
    final progress = _voiceIsPlaying
        ? _voicePlayPosition / (_voiceSeconds > 0 ? _voiceSeconds : 1)
        : 0.0;
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _isDarkMode
                ? const Color(0xFF2E2820)
                : const Color(0xFFFFF0F0),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFE8A0A0).withAlpha(100),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: _toggleVoicePlayback,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8A0A0).withAlpha(40),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFE8A0A0),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        _voiceIsPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: const Color(0xFFE05C5C),
                        size: 28,
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
                            value: _voiceIsPlaying ? progress : 0,
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
                              _voiceIsPlaying
                                  ? _formatDuration(_voicePlayPosition)
                                  : '0:00',
                              style: GoogleFonts.nunitoSans(
                                fontSize: 11,
                                color: _textSecondary,
                              ),
                            ),
                            Text(
                              _formatDuration(_voiceSeconds),
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
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _retakeVoice,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
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
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          textCapitalization: TextCapitalization.sentences,
          controller: _messageController,
          maxLines: 2,
          style: GoogleFonts.nunitoSans(fontSize: 15, color: _textPrimary),
          decoration: InputDecoration(
            hintText: 'Add a caption...',
            hintStyle: GoogleFonts.nunitoSans(
              fontSize: 15,
              color: _isDarkMode
                  ? const Color(0xFF6B5E4E)
                  : const Color(0xFFBBAA98),
              fontStyle: FontStyle.italic,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildVideoComposer() {
    if (_videoHasRecording) {
      return _buildVideoPreview();
    }
    if (_videoIsRecording) {
      return _buildVideoRecordingActive();
    }
    return _buildVideoIdle();
  }

  Widget _buildVideoIdle() {
    return Column(
      children: [
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _startVideoRecording,
          child: Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: const Color(0xFF9B8FD4).withAlpha(38),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF9B8FD4).withAlpha(128),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.videocam_rounded,
              color: Color(0xFF9B8FD4),
              size: 40,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Tap to start recording',
          style: GoogleFonts.nunitoSans(fontSize: 15, color: _textSecondary),
        ),
        const SizedBox(height: 6),
        Text(
          'A face-to-face moment they\'ll treasure',
          textAlign: TextAlign.center,
          style: GoogleFonts.nunitoSans(
            fontSize: 12,
            color: const Color(0xFF9B8FD4),
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Up to 60 seconds',
          style: GoogleFonts.nunitoSans(
            fontSize: 11,
            color: _textSecondary.withAlpha(160),
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildVideoRecordingActive() {
    final progress = _videoSeconds / _maxRecordSeconds;
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          height: 140,
          decoration: BoxDecoration(
            color: _isDarkMode
                ? const Color(0xFF1A1020)
                : const Color(0xFF1A1020),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFE05C5C).withAlpha(180),
              width: 2,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.videocam_rounded,
                      color: Colors.white54,
                      size: 36,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Recording...',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 10,
                left: 12,
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE05C5C),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'REC  ${_formatDuration(_videoSeconds)}',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFE05C5C),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12),
                  ),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFE05C5C),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _stopVideoRecording,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFE05C5C).withAlpha(20),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: const Color(0xFFE05C5C), width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.stop_rounded,
                  color: Color(0xFFE05C5C),
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  'Stop Recording',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFE05C5C),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildVideoPreview() {
    return Column(
      children: [
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
          height: 200,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1020),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF9B8FD4).withAlpha(120),
              width: 1.5,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Real video player
              if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized)
                AspectRatio(
                  aspectRatio: _videoPlayerController!.value.aspectRatio,
                  child: VideoPlayer(_videoPlayerController!),
                ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _toggleVideoPlayback,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white70,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        _videoIsPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _videoIsPlaying
                        ? '${_formatDuration(_videoPlayPosition)} / ${_formatDuration(_videoSeconds)}'
                        : _formatDuration(_videoSeconds),
                    style: GoogleFonts.nunitoSans(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              if (_videoIsPlaying)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(14),
                    ),
                    child: LinearProgressIndicator(
                      value:
                          _videoPlayPosition /
                          (_videoSeconds > 0 ? _videoSeconds : 1),
                      minHeight: 4,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF9B8FD4),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _retakeVideo,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
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
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          textCapitalization: TextCapitalization.sentences,
          controller: _messageController,
          maxLines: 2,
          style: GoogleFonts.nunitoSans(fontSize: 15, color: _textPrimary),
          decoration: InputDecoration(
            hintText: 'Add a caption...',
            hintStyle: GoogleFonts.nunitoSans(
              fontSize: 15,
              color: _isDarkMode
                  ? const Color(0xFF6B5E4E)
                  : const Color(0xFFBBAA98),
              fontStyle: FontStyle.italic,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildQuickMessages() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '✨ Quick Warm Messages',
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '— tap to use',
              style: GoogleFonts.nunitoSans(
                fontSize: 12,
                color: _textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _quickMessages.map((msg) {
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedType = 'text';
                  _messageController.text = msg['text']!;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _isDarkMode
                      ? const Color(0xFF2E2820)
                      : const Color(0xFFFFF8F0),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: const Color(0xFFE8A0A0).withAlpha(110),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE8A0A0).withAlpha(15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  msg['text']!,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSendFAB() {
    return FloatingActionButton.extended(
      onPressed: _isSending ? null : _sendMessage,
      backgroundColor: const Color(0xFF5DA399),
      elevation: 4,
      label: _isSending
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          : Row(
              children: [
                const Icon(
                  Icons.favorite_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Send with Love',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _sendMessage({String? overrideType, String? overridePath, String? overrideContent}) async {
    if (_isSending) return;
    setState(() => _isSending = true);

    try {
      final supabase = Supabase.instance.client;
      // Previously this only checked currentUser?.id once, with no retry --
      // if the session hadn't fully established yet (confirmed as a real,
      // persistent issue on this exact account tonight, not a one-off),
      // this silently failed: spinner appears, then clears, nothing sent,
      // no explanation, keyboard left stuck. Now it actively waits for a
      // real signed-in session before giving up.
      final userId = await AuthService.getReliableUserId();
      final prefs = await SharedPreferences.getInstance();
      String nestId = prefs.getString('nest_id') ?? '';

      // Fallback: fetch nest_id directly from Supabase if not in SharedPreferences
      if (nestId.isEmpty && userId != null) {
        print('SEND: nest_id empty, fetching from Supabase...');
        final result = await supabase
            .from('nests')
            .select('id')
            .eq('created_by', userId)
            .maybeSingle();
        if (result != null) {
          nestId = result['id'] as String;
          await prefs.setString('nest_id', nestId);
          print('SEND: nest_id fetched = $nestId');
        }
      }

      if (userId == null || nestId.isEmpty) {
        debugPrint('SendMessage: userId or nestId missing');
        setState(() => _isSending = false);
        if (mounted) {
          FocusScope.of(context).unfocus();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Couldn't send -- please check your connection and try again."),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      String? mediaUrl;
      final effectiveType = overrideType ?? _selectedType;
      // Fall back to the actual picked/recorded file when no override was
      // passed -- the main Send button calls _sendMessage() with no
      // arguments at all, so relying only on overridePath meant video and
      // voice uploads from that button silently never happened. Matched to
      // effectiveType specifically so a leftover path from switching
      // between voice/video earlier in the same session can never be
      // picked up for the wrong content type.
      final effectivePath = overridePath ??
          (effectiveType == 'video'
              ? _videoFilePath
              : (effectiveType == 'voice' ? _voiceFilePath : null));

      // Upload media if present
      if (_selectedPhotoBase64 != null) {
        final bytes = base64Decode(_selectedPhotoBase64!);
        final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await supabase.storage.from('media').uploadBinary(
          'posts/$fileName',
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
        mediaUrl = supabase.storage.from('media').getPublicUrl('posts/$fileName');
      } else if (effectiveType == 'voice' && effectivePath != null) {
        final file = File(effectivePath);
        final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await supabase.storage.from('media').upload(
          'audio/$fileName',
          file,
          fileOptions: const FileOptions(contentType: 'audio/m4a'),
        );
        mediaUrl = supabase.storage.from('media').getPublicUrl('audio/$fileName');
      } else if (effectiveType == 'video' && effectivePath != null) {
        final file = File(effectivePath);
        final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.mp4';
        await supabase.storage.from('media').upload(
          'video/$fileName',
          file,
          fileOptions: const FileOptions(contentType: 'video/mp4'),
        );
        mediaUrl = supabase.storage.from('media').getPublicUrl('video/$fileName');
      }

      // Insert post into feed_posts
      // visible_to_ids: null/empty = visible to everyone in the nest (default).
      // Non-empty = only the sender + selected recipients can see this card.
      await supabase.from('feed_posts').insert({
        'nest_id': nestId,
        'author_id': userId,
        'post_type': effectiveType,
        'content': overrideContent ?? _messageController.text.trim(),
        'media_url': mediaUrl,
        'is_recorded_video': effectiveType == 'video' ? _videoIsFromRecording : false,
        'visible_to_ids':
            _selectedRecipients.isEmpty ? null : _selectedRecipients,
      });

      // Mark has_sent_messages
      await prefs.setBool('has_sent_messages', true);

      if (!mounted) return;
      setState(() {
        _isSending = false;
        _hasSentMessages = true;
        _selectedRecipients.clear();
        _messageController.clear();
        _voiceCaptionController.clear();
        _videoCaptionController.clear();
        _selectedPhotoBase64 = null;
        _selectedType = 'text';
        _voiceIsRecording = false;
        _voiceHasRecording = false;
        _voiceSeconds = 0;
        _voiceIsPlaying = false;
        _voicePlayPosition = 0;
        _voiceFilePath = null;
        _videoIsRecording = false;
        _videoHasRecording = false;
        _videoSeconds = 0;
        _videoIsPlaying = false;
        _videoPlayPosition = 0;
        _videoFilePath = null;
        _videoIsFromRecording = false;
      });

    } catch (e) {
      print('SEND_ERROR: $e');
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Send error: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 10),
          ),
        );
      }
    }
  }

  void _onNavTap(int index) {
    if (index == _currentNavIndex) return;
    setState(() => _currentNavIndex = index);
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/family-feed-screen');
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
}

/// End of send_screen.dart
