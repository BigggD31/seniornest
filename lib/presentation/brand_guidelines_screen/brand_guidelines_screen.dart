import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class BrandGuidelinesScreen extends StatelessWidget {
  const BrandGuidelinesScreen({super.key});

  static const Color _teal = Color(0xFF5DA399);
  static const Color _gold = Color(0xFFD4AA00);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A1612) : const Color(0xFFFDFDFD);
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
    final textMuted = isDark
        ? const Color(0xFF6B5E4E)
        : const Color(0xFFA8A090);

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
          'Brand Guidelines',
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
          // Header
          _GradientHeader(),
          const SizedBox(height: 28),

          // Colors Section
          _SectionTitle(title: 'Colors', textColor: textPrimary),
          const SizedBox(height: 12),
          _SubSectionTitle(title: 'Brand / Primary', textColor: textSecondary),
          const SizedBox(height: 8),
          _ColorGrid(
            cardBg: cardBg,
            cardBorder: cardBorder,
            textPrimary: textPrimary,
            textMuted: textMuted,
            colors: const [
              _ColorItem(
                name: 'Primary (Teal)',
                hex: '#5DA399',
                color: Color(0xFF5DA399),
                usage: 'Buttons, active states, icons',
              ),
              _ColorItem(
                name: 'Primary Light',
                hex: '#7DBDB5',
                color: Color(0xFF7DBDB5),
                usage: 'Hover / lighter teal accents',
              ),
              _ColorItem(
                name: 'Primary Muted',
                hex: '#5DA399 · 25%',
                color: Color(0x405DA399),
                usage: 'Subtle teal backgrounds',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SubSectionTitle(title: 'Accent / Gold', textColor: textSecondary),
          const SizedBox(height: 8),
          _ColorGrid(
            cardBg: cardBg,
            cardBorder: cardBorder,
            textPrimary: textPrimary,
            textMuted: textMuted,
            colors: const [
              _ColorItem(
                name: 'Gold',
                hex: '#D4AA00',
                color: Color(0xFFD4AA00),
                usage: 'Secondary accent, celebrations',
              ),
              _ColorItem(
                name: 'Gold Light',
                hex: '#D4AA00 · 12%',
                color: Color(0x20D4AA00),
                usage: 'Gold background tints',
              ),
              _ColorItem(
                name: 'Gold Muted',
                hex: '#D4AA00 · 40%',
                color: Color(0x66D4AA00),
                usage: 'Softer gold highlights',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SubSectionTitle(
            title: 'Surfaces & Backgrounds',
            textColor: textSecondary,
          ),
          const SizedBox(height: 8),
          _ColorGrid(
            cardBg: cardBg,
            cardBorder: cardBorder,
            textPrimary: textPrimary,
            textMuted: textMuted,
            colors: const [
              _ColorItem(
                name: 'Background',
                hex: '#FDFDFD',
                color: Color(0xFFFDFDFD),
                usage: 'App scaffold background',
              ),
              _ColorItem(
                name: 'Surface Warm',
                hex: '#F5F0E8',
                color: Color(0xFFF5F0E8),
                usage: 'Warm card/section backgrounds',
              ),
              _ColorItem(
                name: 'Surface Card',
                hex: '#FAF7F2',
                color: Color(0xFFFAF7F2),
                usage: 'Card fill color',
              ),
              _ColorItem(
                name: 'Card Border',
                hex: '#E8E0D0',
                color: Color(0xFFE8E0D0),
                usage: 'Default card/input borders',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SubSectionTitle(title: 'Text', textColor: textSecondary),
          const SizedBox(height: 8),
          _ColorGrid(
            cardBg: cardBg,
            cardBorder: cardBorder,
            textPrimary: textPrimary,
            textMuted: textMuted,
            colors: const [
              _ColorItem(
                name: 'Text Primary',
                hex: '#2C2417',
                color: Color(0xFF2C2417),
                usage: 'Main body text',
              ),
              _ColorItem(
                name: 'Text Secondary',
                hex: '#6B5E4E',
                color: Color(0xFF6B5E4E),
                usage: 'Subtitles, secondary labels',
              ),
              _ColorItem(
                name: 'Text Muted',
                hex: '#A8A090',
                color: Color(0xFFA8A090),
                usage: 'Hints, placeholders',
              ),
              _ColorItem(
                name: 'Text on Primary',
                hex: '#FFFFFF',
                color: Color(0xFFFFFFFF),
                usage: 'Text on teal backgrounds',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SubSectionTitle(title: 'Semantic', textColor: textSecondary),
          const SizedBox(height: 8),
          _ColorGrid(
            cardBg: cardBg,
            cardBorder: cardBorder,
            textPrimary: textPrimary,
            textMuted: textMuted,
            colors: const [
              _ColorItem(
                name: 'Success',
                hex: '#5DA399',
                color: Color(0xFF5DA399),
                usage: 'Success states',
              ),
              _ColorItem(
                name: 'Warning',
                hex: '#D4AA00',
                color: Color(0xFFD4AA00),
                usage: 'Warning states',
              ),
              _ColorItem(
                name: 'Error',
                hex: '#C0392B',
                color: Color(0xFFC0392B),
                usage: 'Error messages, destructive',
              ),
              _ColorItem(
                name: 'Error Light',
                hex: '#C0392B · 12%',
                color: Color(0x20C0392B),
                usage: 'Error background tints',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SubSectionTitle(title: 'Dark Mode', textColor: textSecondary),
          const SizedBox(height: 8),
          _ColorGrid(
            cardBg: cardBg,
            cardBorder: cardBorder,
            textPrimary: textPrimary,
            textMuted: textMuted,
            colors: const [
              _ColorItem(
                name: 'Dark Background',
                hex: '#1A1612',
                color: Color(0xFF1A1612),
                usage: 'Dark scaffold background',
              ),
              _ColorItem(
                name: 'Dark Surface',
                hex: '#242018',
                color: Color(0xFF242018),
                usage: 'Dark card/surface fill',
              ),
              _ColorItem(
                name: 'Dark Surface Variant',
                hex: '#2E2820',
                color: Color(0xFF2E2820),
                usage: 'Elevated dark surfaces',
              ),
              _ColorItem(
                name: 'Dark Card Border',
                hex: '#3D3428',
                color: Color(0xFF3D3428),
                usage: 'Dark mode borders',
              ),
              _ColorItem(
                name: 'Dark Text Primary',
                hex: '#F5EDD8',
                color: Color(0xFFF5EDD8),
                usage: 'Main text in dark mode',
              ),
              _ColorItem(
                name: 'Dark Text Secondary',
                hex: '#B8A888',
                color: Color(0xFFB8A888),
                usage: 'Secondary text in dark mode',
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Gradient Section
          _SectionTitle(title: 'Gradient', textColor: textPrimary),
          const SizedBox(height: 12),
          _GradientCard(
            cardBg: cardBg,
            cardBorder: cardBorder,
            textPrimary: textPrimary,
            textMuted: textMuted,
          ),
          const SizedBox(height: 28),

          // Typography Section
          _SectionTitle(title: 'Typography', textColor: textPrimary),
          const SizedBox(height: 4),
          Text(
            'Font Family: Nunito Sans (Google Fonts)',
            style: GoogleFonts.nunitoSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _teal,
            ),
          ),
          const SizedBox(height: 12),
          _TypographyTable(
            cardBg: cardBg,
            cardBorder: cardBorder,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textMuted: textMuted,
          ),
          const SizedBox(height: 28),

          // Spacing & Shape Section
          _SectionTitle(title: 'Spacing & Shape', textColor: textPrimary),
          const SizedBox(height: 12),
          _ShapeSpacingSection(
            cardBg: cardBg,
            cardBorder: cardBorder,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textMuted: textMuted,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Gradient Header ────────────────────────────────────────────
class _GradientHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5DA399), Color(0xFFD4AA00)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Center(
        child: Text(
          'SeniorNest',
          style: GoogleFonts.nunitoSans(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ── Section Title ──────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.textColor});
  final String title;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.nunitoSans(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
    );
  }
}

class _SubSectionTitle extends StatelessWidget {
  const _SubSectionTitle({required this.title, required this.textColor});
  final String title;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.nunitoSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
    );
  }
}

// ── Color Item Model ───────────────────────────────────────────
class _ColorItem {
  const _ColorItem({
    required this.name,
    required this.hex,
    required this.color,
    required this.usage,
  });
  final String name;
  final String hex;
  final Color color;
  final String usage;
}

// ── Color Grid ─────────────────────────────────────────────────
class _ColorGrid extends StatelessWidget {
  const _ColorGrid({
    required this.colors,
    required this.cardBg,
    required this.cardBorder,
    required this.textPrimary,
    required this.textMuted,
  });
  final List<_ColorItem> colors;
  final Color cardBg;
  final Color cardBorder;
  final Color textPrimary;
  final Color textMuted;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: colors
          .map(
            (item) => _ColorRow(
              item: item,
              cardBg: cardBg,
              cardBorder: cardBorder,
              textPrimary: textPrimary,
              textMuted: textMuted,
            ),
          )
          .toList(),
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.item,
    required this.cardBg,
    required this.cardBorder,
    required this.textPrimary,
    required this.textMuted,
  });
  final _ColorItem item;
  final Color cardBg;
  final Color cardBorder;
  final Color textPrimary;
  final Color textMuted;

  void _copyHex(BuildContext context) {
    Clipboard.setData(ClipboardData(text: item.hex));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${item.hex} copied!',
          style: GoogleFonts.nunitoSans(fontSize: 13),
        ),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF5DA399),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _copyHex(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: cardBorder, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: item.color,
                borderRadius: BorderRadius.circular(10.0),
                border: Border.all(color: cardBorder, width: 1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.usage,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cardBorder.withAlpha(102),
                borderRadius: BorderRadius.circular(6.0),
              ),
              child: Text(
                item.hex,
                style: GoogleFonts.nunitoSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Gradient Card ──────────────────────────────────────────────
class _GradientCard extends StatelessWidget {
  const _GradientCard({
    required this.cardBg,
    required this.cardBorder,
    required this.textPrimary,
    required this.textMuted,
  });
  final Color cardBg;
  final Color cardBorder;
  final Color textPrimary;
  final Color textMuted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: cardBorder, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF5DA399), Color(0xFFD4AA00)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(10.0),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _GradientStop(
                label: 'Start',
                hex: '#5DA399',
                color: const Color(0xFF5DA399),
                textPrimary: textPrimary,
                textMuted: textMuted,
              ),
              const SizedBox(width: 16),
              _GradientStop(
                label: 'End',
                hex: '#D4AA00',
                color: const Color(0xFFD4AA00),
                textPrimary: textPrimary,
                textMuted: textMuted,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GradientStop extends StatelessWidget {
  const _GradientStop({
    required this.label,
    required this.hex,
    required this.color,
    required this.textPrimary,
    required this.textMuted,
  });
  final String label;
  final String hex;
  final Color color;
  final Color textPrimary;
  final Color textMuted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.nunitoSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: textMuted,
              ),
            ),
            Text(
              hex,
              style: GoogleFonts.nunitoSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Typography Table ───────────────────────────────────────────
class _TypographyTable extends StatelessWidget {
  const _TypographyTable({
    required this.cardBg,
    required this.cardBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
  });
  final Color cardBg;
  final Color cardBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  static const List<List<String>> _rows = [
    ['Display Large', '36sp', 'Bold 700'],
    ['Display Medium', '30sp', 'Bold 700'],
    ['Display Small', '26sp', 'SemiBold 600'],
    ['Headline Large', '24sp', 'Bold 700'],
    ['Headline Medium', '20sp', 'Bold 700'],
    ['Headline Small', '18sp', 'SemiBold 600'],
    ['Title Large', '17sp', 'Bold 700'],
    ['Title Medium', '15sp', 'SemiBold 600'],
    ['Title Small', '13sp', 'SemiBold 600'],
    ['Body Large', '16sp', 'Regular 400'],
    ['Body Medium', '14sp', 'Regular 400'],
    ['Body Small', '12sp', 'Regular 400'],
    ['Label Large', '14sp', 'SemiBold 600'],
    ['Label Medium', '12sp', 'SemiBold 600'],
    ['Label Small', '11sp', 'Medium 500'],
    ['Button Text', '16sp', 'Bold 700'],
    ['App Bar Title', '18sp', 'Bold 700'],
    ['Nav Label (active)', '11sp', 'Bold 700'],
    ['Nav Label (inactive)', '11sp', 'Regular 400'],
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: cardBorder, width: 1.5),
      ),
      child: Column(
        children: [
          // Header row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF5DA399).withAlpha(26),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    'Role',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF5DA399),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Size',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF5DA399),
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Weight',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF5DA399),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...List.generate(_rows.length, (i) {
            final row = _rows[i];
            final isLast = i == _rows.length - 1;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(bottom: BorderSide(color: cardBorder, width: 0.8)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      row[0],
                      style: GoogleFonts.nunitoSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      row[1],
                      style: GoogleFonts.nunitoSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF5DA399),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      row[2],
                      style: GoogleFonts.nunitoSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Shape & Spacing Section ────────────────────────────────────
class _ShapeSpacingSection extends StatelessWidget {
  const _ShapeSpacingSection({
    required this.cardBg,
    required this.cardBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
  });
  final Color cardBg;
  final Color cardBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  @override
  Widget build(BuildContext context) {
    final items = [
      ['Cards', 'Border Radius', '16px'],
      ['Cards', 'Border Width', '1.5px'],
      ['Buttons', 'Border Radius', '16px'],
      ['Buttons', 'Height', '56px'],
      ['Buttons', 'Width', 'Full width'],
      ['Inputs', 'Style', 'Underline'],
      ['Inputs', 'Border Width', '1.5px (default)'],
      ['Inputs', 'Border Width', '2px (focused)'],
      ['Inputs', 'Vertical Padding', '12px'],
      ['Nav Icons', 'Size', '24px'],
    ];

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: cardBorder, width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFD4AA00).withAlpha(26),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Element',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFD4AA00),
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    'Property',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFD4AA00),
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Value',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFD4AA00),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...List.generate(items.length, (i) {
            final row = items[i];
            final isLast = i == items.length - 1;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(bottom: BorderSide(color: cardBorder, width: 0.8)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      row[0],
                      style: GoogleFonts.nunitoSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(
                      row[1],
                      style: GoogleFonts.nunitoSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: textMuted,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      row[2],
                      style: GoogleFonts.nunitoSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF5DA399),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
