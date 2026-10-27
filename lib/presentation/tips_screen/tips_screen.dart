import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Oct 15 2026: plain-language "Tips & Tricks" page, opened from Setup.
/// Each tip is a card that opens to show a few short lines and, where one
/// exists, a real screenshot with a circle and a caption.
enum _Audience { everyone, senior, family, owner }

class _Tip {
  const _Tip({
    required this.emoji,
    required this.title,
    required this.lines,
    this.audience = _Audience.everyone,
    this.image,
    this.caption,
  });
  final String emoji;
  final String title;
  final List<String> lines;
  final _Audience audience;
  final String? image;
  final String? caption;
}

/// Oct 15 2026: tips are text-only for now (screenshots can be added later
/// through [image] / [caption]). Each tip is shown only to the people it
/// applies to: everyone, seniors, family members, or the Nest Owner.
const List<_Tip> _tips = [
  _Tip(
    emoji: '✨',
    title: 'Why do I see example posts?',
    lines: [
      'When your Nest is new, we show a few example posts, stories and photos so you can see what it will look like.',
      'They are labeled as examples, and they disappear on their own as soon as your family starts posting real ones.',
      'Your own posts and your family\'s posts are always real, and always shown.',
    ],
  ),
  _Tip(
    emoji: '🔖',
    title: 'Saving a story with the bookmark',
    lines: [
      'See a story you want to keep? Tap the bookmark on it.',
      'Saved stories are collected in the Favs tab at the bottom of the screen, so you can find them again in one place.',
      'To remove one, tap the bookmark again.',
    ],
  ),
  _Tip(
    emoji: '💌',
    title: 'Sending something to your family',
    lines: [
      'Open the Share tab and choose Text, Photo, Voice or Video.',
      'Write or record your message, then tap Send with Love.',
    ],
  ),
  _Tip(
    emoji: '👤',
    title: 'Changing your name, birthday or photo',
    lines: [
      'In Setup, tap the pencil on your profile card to change your name, what you want to be called, and your birthday and anniversary.',
      'Tap your picture to choose a new photo or emoji.',
      'Changes show up right away.',
    ],
  ),
  _Tip(
    emoji: '💚',
    title: 'Letting family know you\'re okay',
    audience: _Audience.senior,
    lines: [
      'On the Home tab, tap the "I\'m Good Today" heart. One tap, no phone call needed.',
      'Your family sees it right away on their Home screen.',
    ],
  ),
  _Tip(
    emoji: '🎙️',
    title: 'Recording a Legacy story',
    audience: _Audience.senior,
    lines: [
      'Open the Legacy tab to record a memory in your own voice or on video. Take your time, and record in parts if you like.',
      'Stories are saved for your family to enjoy and share together.',
    ],
  ),
  _Tip(
    emoji: '💚',
    title: 'Knowing your loved one is okay',
    audience: _Audience.family,
    lines: [
      'When your senior taps "I\'m Good Today", you will see it right away on your Home screen.',
      'You can also send them a message any time from the Share tab.',
    ],
  ),
  _Tip(
    emoji: '🔑',
    title: 'Inviting family and renaming your Nest',
    audience: _Audience.owner,
    lines: [
      'Your invite code is at the top of Setup. Tap Share to send it by text or email. Everyone you invite joins for free.',
      'To rename your Nest, open Setup, tap Nest Name under Your Nest, type the new name, and save.',
    ],
  ),
];

class TipsScreen extends StatelessWidget {
  const TipsScreen({
    super.key,
    required this.isDarkMode,
    this.isSenior = false,
    this.isNestOwner = false,
  });

  final bool isDarkMode;
  final bool isSenior;
  final bool isNestOwner;

  bool _shows(_Tip t) {
    switch (t.audience) {
      case _Audience.everyone:
        return true;
      case _Audience.senior:
        return isSenior;
      case _Audience.family:
        return !isSenior;
      case _Audience.owner:
        return isNestOwner;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = isDarkMode ? const Color(0xFF1A1610) : const Color(0xFFFDFDFD);
    final card = isDarkMode ? const Color(0xFF2A2418) : const Color(0xFFFAF6EC);
    final border =
        isDarkMode ? const Color(0xFF3D3428) : const Color(0xFFE8D9A8);
    final textPrimary =
        isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
    final textSecondary =
        isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        iconTheme: IconThemeData(color: textPrimary),
        title: Text(
          'Tips & Tricks',
          style: GoogleFonts.nunitoSans(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              'Little things that make SeniorNest easier.',
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                color: textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            for (final tip in _tips.where(_shows))
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: border, width: 1.5),
                ),
                child: Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    childrenPadding:
                        const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    iconColor: const Color(0xFFC8922A),
                    collapsedIconColor: const Color(0xFFC8922A),
                    title: Row(
                      children: [
                        Text(tip.emoji, style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            tip.title,
                            style: GoogleFonts.nunitoSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in tip.lines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            line,
                            style: GoogleFonts.nunitoSans(
                              fontSize: 15,
                              color: textSecondary,
                              height: 1.55,
                            ),
                          ),
                        ),
                      if (tip.image != null) ...[
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(tip.image!, fit: BoxFit.fitWidth),
                        ),
                        if (tip.caption != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              tip.caption!,
                              style: GoogleFonts.nunitoSans(
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                color: textSecondary,
                              ),
                            ),
                          ),
                      ],
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
