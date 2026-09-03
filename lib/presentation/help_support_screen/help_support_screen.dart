import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_state.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A1612) : const Color(0xFFF8F4ED);
    final cardBg = isDark ? const Color(0xFF242018) : const Color(0xFFFAF7F2);
    final cardBorder = isDark
        ? const Color(0xFF3D3428)
        : const Color(0xFFE8E0D0);
    final textPrimary = isDark
        ? const Color(0xFFF5EDD8)
        : const Color(0xFF2C2417);
    final textSecondary = isDark
        ? const Color(0xFFB8A888)
        : const Color(0xFF6B5E4E);
    const gold = Color(0xFFD4AA5E);
    const teal = Color(0xFF5DA399);

    final faqs = [
      {
        'q': 'How do I invite a family member?',
        'a':
            'Go to Setup → Your Nest section and tap "Share Invite Code". Send the code to your family member.',
      },
      {
        'q': 'How do I change my display name?',
        'a': 'Go to Setup → tap your name at the top of the screen to edit it.',
      },
      {
        'q': 'Can I use SeniorNest on multiple devices?',
        'a':
            'Yes! Sign in with the same account on any device and your nest will sync automatically.',
      },
      {
        'q': 'How do I turn off notifications?',
        'a':
            'Go to Setup → Notifications section and toggle off the notifications you don\'t want.',
      },
      {
        'q': 'How do I delete my account?',
        'a':
            'Go to Setup → Account section → Sign Out. To fully delete your account, contact us at the email below.',
      },
      {
        'q': 'Is my data private?',
        'a':
            'Yes. SeniorNest collects only what\'s needed to run the app. We never share or sell your data. See our Privacy Policy for full details.',
      },
    ];

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Help & Support',
          style: GoogleFonts.nunitoSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          // Contact card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: teal.withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.mail_outline_rounded,
                        color: teal,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Contact Us',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'We\'re here to help! Reach out anytime and we\'ll get back to you within 24 hours.',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 14,
                    color: textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.email_rounded, color: gold, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'support@seniornest.app',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: gold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // FAQ header
          Text(
            'Frequently Asked Questions',
            style: GoogleFonts.nunitoSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          // FAQ items
          ...faqs.map(
            (faq) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cardBorder, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💬', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          faq['q']!,
                          style: GoogleFonts.nunitoSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: Text(
                      faq['a']!,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 13,
                        color: textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Sep 2 2026: D Von wanted Archive Mode (memorial space) off the
          // main Settings page entirely -- not even a collapsed row there.
          // Lives here instead, behind Help & Support, still fully
          // functional (own fetch, toggle, confirmation dialog), just not
          // something anyone stumbles across casually. Nest Ownership
          // itself (succession status) stayed on Setup -- D Von's own
          // words were that only Archive Mode specifically felt out of
          // place there, not ownership/succession generally.
          _ArchiveModeCard(
            cardBg: cardBg,
            cardBorder: cardBorder,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            bg: bg,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _ArchiveModeCard extends StatefulWidget {
  const _ArchiveModeCard({
    required this.cardBg,
    required this.cardBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.bg,
  });
  final Color cardBg;
  final Color cardBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color bg;

  @override
  State<_ArchiveModeCard> createState() => _ArchiveModeCardState();
}

class _ArchiveModeCardState extends State<_ArchiveModeCard> {
  bool _loading = true;
  bool _isOwner = false;
  bool _isArchived = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final supabase = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();
      final nestId = prefs.getString('nest_id') ?? '';
      final myUserId = supabase.auth.currentUser?.id;
      if (nestId.isEmpty || myUserId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      // Same ownership check as setup_screen.dart -- created_by is the
      // live "current owner" field, updated by Nest Succession on
      // transfer, not a static "who created this" record.
      final nest = await supabase
          .from('nests')
          .select('created_by, is_archived')
          .eq('id', nestId)
          .maybeSingle();
      if (mounted) {
        setState(() {
          final ownerId = nest?['created_by'] as String?;
          _isOwner = ownerId == myUserId;
          _isArchived = nest?['is_archived'] as bool? ?? false;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('ARCHIVE_MODE_CARD_LOAD_ERROR: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _confirmToggle(bool turningOn) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          turningOn
              ? 'Turn this Nest into a memorial space?'
              : 'Turn daily check-ins back on?',
          style: GoogleFonts.nunitoSans(
              fontSize: 20, fontWeight: FontWeight.w700, color: widget.textPrimary),
        ),
        content: Text(
          turningOn
              ? 'Daily check-in, medication, and SOS prompts will be turned off for everyone in this Nest. Legacy stories, photos, and messages stay exactly as they are -- nothing is deleted or locked, and you can turn this back on anytime.'
              : 'Daily check-in, medication, and SOS prompts will come back for everyone in this Nest.',
          style: GoogleFonts.nunitoSans(
              fontSize: 15, color: widget.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style:
                    GoogleFonts.nunitoSans(fontSize: 15, color: widget.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _setArchiveStatus(turningOn);
            },
            child: Text(
              turningOn ? 'Turn On' : 'Turn Back On',
              style: GoogleFonts.nunitoSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF5DA399)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setArchiveStatus(bool value) async {
    final previous = _isArchived;
    setState(() => _isArchived = value); // optimistic, reverted on failure below
    appIsNestArchivedNotifier.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      final nestId = prefs.getString('nest_id') ?? '';
      if (nestId.isEmpty) throw Exception('No nest found.');
      await Supabase.instance.client
          .from('nests')
          .update({'is_archived': value}).eq('id', nestId);
      // Same shared cache key family_feed_screen.dart reads at first
      // paint -- both need to agree, exactly as before this moved.
      await prefs.setBool('cached_is_nest_archived', value);
    } catch (e) {
      if (mounted) setState(() => _isArchived = previous);
      appIsNestArchivedNotifier.value = previous;
      if (mounted) {
        final message = e.toString().contains('Exception:')
            ? e.toString().split('Exception:').last.trim()
            : 'Something went wrong. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message,
                style: GoogleFonts.nunitoSans(fontSize: 14, color: Colors.white)),
            backgroundColor: const Color(0xFFC97B4A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Not the owner, still loading, or no nest found -- nothing to show.
    // Matches the original gating on Setup, which only ever rendered
    // this for the nest owner.
    if (_loading || !_isOwner) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.cardBorder, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                const Icon(Icons.nights_stay_rounded,
                    color: Color(0xFF5DA399), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Memorial Space (Archive Nest)',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: widget.textPrimary,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      color: widget.textSecondary, size: 22),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 12),
            Text(
              'Quiets daily check-in, medication, and SOS prompts for this Nest. Legacy stories, photos, and messages stay exactly as they are.',
              style: GoogleFonts.nunitoSans(
                  fontSize: 13, color: widget.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isArchived ? 'Currently on' : 'Currently off',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: widget.textPrimary,
                    ),
                  ),
                ),
                Switch(
                  value: _isArchived,
                  activeThumbColor: const Color(0xFF5DA399),
                  onChanged: (v) => _confirmToggle(v),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
