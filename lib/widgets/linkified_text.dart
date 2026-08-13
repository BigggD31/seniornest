import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders [text] with any http/https URLs turned into tappable, underlined
/// links that open in the device's browser. Everything else renders exactly
/// like a plain [Text] widget would, using [style] as the base style.
///
/// This is the "simple" version of link handling (tappable text only) --
/// no fetched title/description/image preview card. See the "Link previews
/// / hyperlinking in messages" backlog item for the fuller preview-card
/// version, which is a separate, bigger build.
class LinkifiedText extends StatelessWidget {
  const LinkifiedText(
    this.text, {
    super.key,
    required this.style,
    this.linkColor,
    this.maxLines,
    this.overflow,
    this.showLinkBackground = true,
  });

  final String text;
  final TextStyle style;

  /// Color used for the tappable link portions. Defaults to the app's
  /// teal (#5DA399) if not supplied.
  final Color? linkColor;

  final int? maxLines;
  final TextOverflow? overflow;

  /// Paints a soft highlighted background behind link text, like an inset
  /// chip, so links stand out from the surrounding body text on a plain
  /// card background. Defaults on. Turned off in contexts that already
  /// have their own colored backdrop behind the text (the DM thread's
  /// "mine" message bubbles), where a second background would fight with
  /// the bubble color instead of helping.
  final bool showLinkBackground;

  // Matches http/https URLs. Intentionally simple/conservative: stops at
  // whitespace, so it won't mis-grab trailing punctuation like a sentence's
  // closing period in most everyday phrasing.
  static final RegExp _urlPattern = RegExp(
    r'(https?:\/\/[^\s]+)',
    caseSensitive: false,
  );

  Future<void> _openLink(String rawUrl) async {
    // Trim common trailing punctuation a user might have typed right after
    // a pasted link (e.g. "check this out: https://example.com!").
    final cleaned = rawUrl.replaceAll(RegExp(r'[),.!?]+$'), '');
    final uri = Uri.tryParse(cleaned);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = _urlPattern.allMatches(text);

    if (matches.isEmpty) {
      // No links in this text -- behaves exactly like a plain Text widget.
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final effectiveLinkColor = linkColor ?? const Color(0xFF5DA399);
    final spans = <TextSpan>[];
    var lastEnd = 0;

    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      final url = match.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: style.copyWith(
            color: effectiveLinkColor,
            decoration: TextDecoration.underline,
            decorationColor: effectiveLinkColor,
            background: showLinkBackground
                ? (Paint()..color = effectiveLinkColor.withValues(alpha: 0.14))
                : null,
          ),
          recognizer: TapGestureRecognizer()..onTap = () => _openLink(url),
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      text: TextSpan(style: style, children: spans),
    );
  }
}
