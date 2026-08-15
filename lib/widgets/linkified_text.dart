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
    this.showLinkBackground = false,
    this.interactive = true,
  });

  final String text;
  final TextStyle style;

  /// Color used for the tappable link portions. Defaults to a deeper teal
  /// (#3D6E63) for better contrast against plain card/body text than the
  /// app's lighter primary teal.
  final Color? linkColor;

  final int? maxLines;
  final TextOverflow? overflow;

  /// Paints a soft highlighted background behind link text, like an inset
  /// chip, so links stand out from the surrounding body text on a plain
  /// card background. Defaults OFF -- tried on (teal tint, then gold tint)
  /// across builds 168/169 and D Von preferred plain colored text with no
  /// background at all. Left available for any future context that wants
  /// it, just opt-in now instead of opt-out.
  final bool showLinkBackground;

  /// Whether the link portion is actually tappable. Defaults on. Turn off
  /// for preview/summary contexts already wrapped in their own tap target
  /// (e.g. a conversation list row that opens the thread on tap) -- a live
  /// link there would compete with the row's own tap behavior and open the
  /// URL instead of the conversation. When off, the link still gets its
  /// color/background styling, just no recognizer attached.
  final bool interactive;

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

    final effectiveLinkColor = linkColor ?? const Color(0xFF3D6E63);
    // The highlight background is intentionally a different color (gold)
    // from the link text (teal) -- a same-color tint blended into the text
    // color and didn't read as a distinct highlight. Gold-on-teal separates
    // the two visually.
    const linkHighlightColor = Color(0xFFD4AA00);
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
                ? (Paint()..color = linkHighlightColor.withValues(alpha: 0.14))
                : null,
          ),
          recognizer: interactive
              ? (TapGestureRecognizer()..onTap = () => _openLink(url))
              : null,
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
