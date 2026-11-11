import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../services/family_plans_service.dart';

/// Nov 7 2026: the three bottom sheets for Family Plans -- Create a Plan,
/// Create a Poll, and "Who can see this". Colors follow the app's own
/// look: terracotta on warm cream (see family_plans_palette.dart).

const Color _teal = Color(0xFFB94A2A);
const Color _gold = Color(0xFF8A3A1F);

Color _text(bool dark) =>
    dark ? const Color(0xFFF5EDD8) : const Color(0xFF3B2F2A);
Color _muted(bool dark) =>
    dark ? const Color(0xFFC4B49C) : const Color(0xFF6B5A50);
Color _sheetBg(bool dark) =>
    dark ? const Color(0xFF1A1612) : const Color(0xFFFBF6EE);
Color _fieldBg(bool dark) =>
    dark ? const Color(0xFF2A241D) : const Color(0xFFFFFFFF);
Color _fieldBorder(bool dark) =>
    dark ? const Color(0xFF3D342B) : const Color(0xFFE4D8C8);

/// Short list of hidden names: "Nana", "Nana and Sarah", "Nana and 2 others".
String hiddenNamesText(List<String> names) {
  if (names.isEmpty) return '';
  if (names.length == 1) return names[0];
  if (names.length == 2) return '${names[0]} and ${names[1]}';
  return '${names[0]} and ${names.length - 1} others';
}

// ── Who can see this ─────────────────────────────────────────────

/// Opens the checkbox list. [members] are everyone except me ({id, name}).
/// [hiddenIds] are the people currently unchecked. Returns the new set of
/// hidden ids, or null if closed without tapping Done.
Future<Set<String>?> showWhoCanSeeSheet(
  BuildContext context, {
  required bool isDarkMode,
  required List<Map<String, String>> members,
  required Set<String> hiddenIds,
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _sheetBg(isDarkMode),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _WhoCanSeeSheet(
      isDarkMode: isDarkMode,
      members: members,
      hiddenIds: hiddenIds,
    ),
  );
}

class _WhoCanSeeSheet extends StatefulWidget {
  const _WhoCanSeeSheet({
    required this.isDarkMode,
    required this.members,
    required this.hiddenIds,
  });
  final bool isDarkMode;
  final List<Map<String, String>> members;
  final Set<String> hiddenIds;

  @override
  State<_WhoCanSeeSheet> createState() => _WhoCanSeeSheetState();
}

class _WhoCanSeeSheetState extends State<_WhoCanSeeSheet> {
  late Set<String> _hidden = {...widget.hiddenIds};

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDarkMode;
    final hiddenNames = [
      for (final m in widget.members)
        if (_hidden.contains(m['id'])) m['name']!
    ];
    final doneLabel = hiddenNames.isEmpty
        ? 'Done · Everyone'
        : 'Done · Everyone except ${hiddenNamesText(hiddenNames)}';
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _fieldBorder(dark),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('Who can see this',
                  style: GoogleFonts.nunitoSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _text(dark))),
              const SizedBox(height: 4),
              Text(
                'Uncheck anyone who should not see it. They will not see it or get a notification.',
                style: GoogleFonts.nunitoSans(
                    fontSize: 14, height: 1.4, color: _muted(dark)),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.check_box_rounded,
                              color: Color(0xFF9E9384)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('You',
                                style: GoogleFonts.nunitoSans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: _text(dark))),
                          ),
                          Text('Always included',
                              style: GoogleFonts.nunitoSans(
                                  fontSize: 13, color: _muted(dark))),
                        ],
                      ),
                    ),
                    for (final m in widget.members)
                      InkWell(
                        onTap: () {
                          setState(() {
                            final id = m['id']!;
                            if (_hidden.contains(id)) {
                              _hidden.remove(id);
                            } else {
                              _hidden.add(id);
                            }
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                _hidden.contains(m['id'])
                                    ? Icons.check_box_outline_blank_rounded
                                    : Icons.check_box_rounded,
                                color: _hidden.contains(m['id'])
                                    ? _muted(dark)
                                    : _teal,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(m['name']!,
                                    style: GoogleFonts.nunitoSans(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: _text(dark))),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.of(context).pop(_hidden),
                  child: Text(doneLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunitoSans(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "Who can see this" row used on both create sheets.
class _WhoCanSeeRow extends StatelessWidget {
  const _WhoCanSeeRow({
    required this.isDarkMode,
    required this.members,
    required this.hiddenIds,
    required this.noun, // 'plan' or 'poll'
    required this.onTap,
  });
  final bool isDarkMode;
  final List<Map<String, String>> members;
  final Set<String> hiddenIds;
  final String noun;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode;
    final hiddenNames = [
      for (final m in members)
        if (hiddenIds.contains(m['id'])) m['name']!
    ];
    final allHidden = members.isNotEmpty && hiddenNames.length == members.length;
    final label = hiddenNames.isEmpty
        ? 'Everyone'
        : allHidden
            ? 'Only me'
            : 'Everyone except ${hiddenNamesText(hiddenNames)}';
    final note = hiddenNames.isEmpty
        ? null
        : '${noun == 'plan' ? 'Surprise plan' : 'Secret poll'}. '
            '${hiddenNamesText(hiddenNames)} won\'t see it or get a notification.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Who can see this',
            style: GoogleFonts.nunitoSans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _text(dark))),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _fieldBg(dark),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _fieldBorder(dark), width: 2),
            ),
            child: Row(
              children: [
                Icon(hiddenNames.isEmpty ? Icons.people_rounded : Icons.lock_rounded,
                    color: hiddenNames.isEmpty
                        ? _teal
                        : (dark ? const Color(0xFFF2B8A0) : _gold),
                    size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label,
                      style: GoogleFonts.nunitoSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _text(dark))),
                ),
                Icon(Icons.chevron_right_rounded, color: _text(dark)),
              ],
            ),
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 6),
          Text(note,
              style: GoogleFonts.nunitoSans(
                  fontSize: 13, color: _muted(dark))),
        ],
      ],
    );
  }
}

// ── Shared field helpers ─────────────────────────────────────────

Widget _label(bool dark, String text, {String? hint}) {
  return Text.rich(
    TextSpan(
      text: text,
      style: GoogleFonts.nunitoSans(
          fontSize: 15, fontWeight: FontWeight.w800, color: _text(dark)),
      children: [
        if (hint != null)
          TextSpan(
            text: ' $hint',
            style: GoogleFonts.nunitoSans(
                fontSize: 15, fontWeight: FontWeight.w600, color: _muted(dark)),
          ),
      ],
    ),
  );
}

InputDecoration _fieldDecoration(bool dark, {String? hint}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.nunitoSans(color: _muted(dark).withAlpha(160)),
    filled: true,
    fillColor: _fieldBg(dark),
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: _fieldBorder(dark), width: 2),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _teal, width: 2),
    ),
  );
}

Widget _sheetHeader(BuildContext context, bool dark, String title) {
  return Column(
    children: [
      Center(
        child: Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(
            color: _fieldBorder(dark),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: Text(title,
                style: GoogleFonts.nunitoSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _text(dark))),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close_rounded, color: _text(dark)),
          ),
        ],
      ),
    ],
  );
}

Widget _switchRow(bool dark, String title, String subtitle, bool value,
    ValueChanged<bool> onChanged) {
  return Container(
    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
    decoration: BoxDecoration(
      color: _fieldBg(dark),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _fieldBorder(dark)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: GoogleFonts.nunitoSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _text(dark))),
              Text(subtitle,
                  style: GoogleFonts.nunitoSans(
                      fontSize: 13, color: _muted(dark))),
            ],
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: Colors.white,
          activeTrackColor: _teal,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

// ── Create / edit a Plan ─────────────────────────────────────────

/// Returns true if a plan was posted (or saved).
Future<bool?> showCreatePlanSheet(
  BuildContext context, {
  required bool isDarkMode,
  required String nestId,
  FamilyPlan? editing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _sheetBg(isDarkMode),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _CreatePlanSheet(
      isDarkMode: isDarkMode,
      nestId: nestId,
      editing: editing,
    ),
  );
}

class _CreatePlanSheet extends StatefulWidget {
  const _CreatePlanSheet({
    required this.isDarkMode,
    required this.nestId,
    this.editing,
  });
  final bool isDarkMode;
  final String nestId;
  final FamilyPlan? editing;

  @override
  State<_CreatePlanSheet> createState() => _CreatePlanSheetState();
}

class _CreatePlanSheetState extends State<_CreatePlanSheet> {
  final _title = TextEditingController();
  final _where = TextEditingController();
  final _details = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  bool _remind = true;
  bool _rsvp = false;
  bool _showNames = true; // false = counts only (hide_rsvp_names)
  bool _saving = false;
  String? _error;
  List<Map<String, String>> _members = [];
  Set<String> _hidden = {};

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _title.text = e.title;
      _where.text = e.location;
      _details.text = e.details;
      _date = DateTime(e.startsAt.year, e.startsAt.month, e.startsAt.day);
      _time = TimeOfDay(hour: e.startsAt.hour, minute: e.startsAt.minute);
      _remind = e.remind24h;
      _rsvp = e.rsvpEnabled;
      _showNames = !e.hideRsvpNames;
    } else {
      _loadMembers();
    }
  }

  Future<void> _loadMembers() async {
    try {
      final m = await FamilyPlansService.otherMembers(widget.nestId);
      if (mounted) setState(() => _members = m);
    } catch (_) {}
  }

  @override
  void dispose() {
    _title.dispose();
    _where.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 18, minute: 0),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickVisibility() async {
    FocusScope.of(context).unfocus();
    final result = await showWhoCanSeeSheet(
      context,
      isDarkMode: widget.isDarkMode,
      members: _members,
      hiddenIds: _hidden,
    );
    if (result != null) setState(() => _hidden = result);
  }

  Future<void> _post() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Please tell the family what the plan is.');
      return;
    }
    if (_date == null || _time == null) {
      setState(() => _error = 'Please choose a date and a time.');
      return;
    }
    final startsAt = DateTime(
        _date!.year, _date!.month, _date!.day, _time!.hour, _time!.minute);
    if (!_isEdit && startsAt.isBefore(DateTime.now())) {
      setState(() => _error = 'That time has already passed. Please pick a later time.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        await FamilyPlansService.updatePlan(
          plan: widget.editing!,
          title: title,
          details: _details.text.trim(),
          location: _where.text.trim(),
          startsAt: startsAt,
          remind24h: _remind,
          rsvpEnabled: _rsvp,
          hideRsvpNames: _rsvp && !_showNames,
        );
      } else {
        final visible = _hidden.isEmpty
            ? <String>[]
            : [
                for (final m in _members)
                  if (!_hidden.contains(m['id'])) m['id']!
              ];
        await FamilyPlansService.createPlan(
          nestId: widget.nestId,
          title: title,
          details: _details.text.trim(),
          location: _where.text.trim(),
          startsAt: startsAt,
          remind24h: _remind,
          rsvpEnabled: _rsvp,
          hideRsvpNames: _rsvp && !_showNames,
          visibleToIds: visible,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('FAMILY_PLANS post plan error: $e');
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'That did not go through. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDarkMode;
    final fmtDate = DateFormat('EEE, MMM d');
    final dateText = _date == null ? 'Choose a date' : fmtDate.format(_date!);
    final timeText = _time == null ? 'Choose a time' : _time!.format(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHeader(
                    context, dark, _isEdit ? 'Edit this Plan' : 'Create a Plan'),
                const SizedBox(height: 8),
                _label(dark, 'What\'s the plan?'),
                const SizedBox(height: 6),
                TextField(
                  controller: _title,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.sentences,
                  style: GoogleFonts.nunitoSans(fontSize: 16, color: _text(dark)),
                  decoration: _fieldDecoration(dark, hint: 'Nana\'s Birthday Dinner'),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label(dark, 'Date'),
                          const SizedBox(height: 6),
                          _pickerBox(dark, dateText, _date == null, _pickDate),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label(dark, 'Time'),
                          const SizedBox(height: 6),
                          _pickerBox(dark, timeText, _time == null, _pickTime),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${FamilyPlansService.zoneLabel()} (your time zone). Everyone sees it in their own time zone.',
                  style: GoogleFonts.nunitoSans(
                      fontSize: 13, color: _muted(dark)),
                ),
                const SizedBox(height: 14),
                _label(dark, 'Where', hint: '(optional)'),
                const SizedBox(height: 6),
                TextField(
                  controller: _where,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.sentences,
                  style: GoogleFonts.nunitoSans(fontSize: 16, color: _text(dark)),
                  decoration: _fieldDecoration(dark, hint: 'Nana\'s house'),
                ),
                const SizedBox(height: 14),
                _label(dark, 'Details', hint: '(optional)'),
                const SizedBox(height: 6),
                TextField(
                  controller: _details,
                  maxLength: 500,
                  minLines: 3,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  style: GoogleFonts.nunitoSans(fontSize: 16, color: _text(dark)),
                  decoration: _fieldDecoration(dark,
                      hint: 'Anything the family should know'),
                ),
                if (!_isEdit) ...[
                  const SizedBox(height: 14),
                  _WhoCanSeeRow(
                    isDarkMode: dark,
                    members: _members,
                    hiddenIds: _hidden,
                    noun: 'plan',
                    onTap: _members.isEmpty ? () {} : _pickVisibility,
                  ),
                ],
                const SizedBox(height: 14),
                _switchRow(dark, 'Remind everyone', '24 hours before the plan',
                    _remind, (v) => setState(() => _remind = v)),
                const SizedBox(height: 10),
                _switchRow(dark, 'Ask who\'s coming',
                    'Family taps Going, Maybe, or Can\'t', _rsvp,
                    (v) => setState(() => _rsvp = v)),
                if (_rsvp) ...[
                  const SizedBox(height: 10),
                  _switchRow(
                      dark,
                      'Show who answered',
                      'Family can open a list of names. Turn off to show counts only.',
                      _showNames,
                      (v) => setState(() => _showNames = v)),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: GoogleFonts.nunitoSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFC0392B))),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _teal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _saving ? null : _post,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white))
                        : Text(_isEdit ? 'Save changes' : 'Post to the Family',
                            style: GoogleFonts.nunitoSans(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pickerBox(bool dark, String text, bool isPlaceholder, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 52,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: _fieldBg(dark),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _fieldBorder(dark), width: 2),
        ),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.nunitoSans(
                fontSize: 16,
                color: isPlaceholder ? _muted(dark) : _text(dark))),
      ),
    );
  }
}

// ── Create a Poll ────────────────────────────────────────────────

Future<bool?> showCreatePollSheet(
  BuildContext context, {
  required bool isDarkMode,
  required String nestId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _sheetBg(isDarkMode),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _CreatePollSheet(isDarkMode: isDarkMode, nestId: nestId),
  );
}

class _CreatePollSheet extends StatefulWidget {
  const _CreatePollSheet({required this.isDarkMode, required this.nestId});
  final bool isDarkMode;
  final String nestId;

  @override
  State<_CreatePollSheet> createState() => _CreatePollSheetState();
}

class _CreatePollSheetState extends State<_CreatePollSheet> {
  final _question = TextEditingController();
  final List<TextEditingController> _options = [
    TextEditingController(),
    TextEditingController(),
  ];
  int _closeChoice = 0; // 0 = 24 hours, 1 = 3 days, 2 = 7 days
  bool _saving = false;
  String? _error;
  List<Map<String, String>> _members = [];
  Set<String> _hidden = {};
  bool _hideVoters = false;

  static const _closeLabels = ['24 hours', '3 days', '7 days'];
  static const _closeDurations = [
    Duration(hours: 24),
    Duration(days: 3),
    Duration(days: 7),
  ];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    try {
      final m = await FamilyPlansService.otherMembers(widget.nestId);
      if (mounted) setState(() => _members = m);
    } catch (_) {}
  }

  @override
  void dispose() {
    _question.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickVisibility() async {
    FocusScope.of(context).unfocus();
    final result = await showWhoCanSeeSheet(
      context,
      isDarkMode: widget.isDarkMode,
      members: _members,
      hiddenIds: _hidden,
    );
    if (result != null) setState(() => _hidden = result);
  }

  Future<void> _post() async {
    final question = _question.text.trim();
    final options = _options
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (question.isEmpty) {
      setState(() => _error = 'Please type your question.');
      return;
    }
    if (options.length < 2) {
      setState(() => _error = 'Please add at least two options.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final visible = _hidden.isEmpty
          ? <String>[]
          : [
              for (final m in _members)
                if (!_hidden.contains(m['id'])) m['id']!
            ];
      await FamilyPlansService.createPoll(
        nestId: widget.nestId,
        question: question,
        options: options,
        closesIn: _closeDurations[_closeChoice],
        visibleToIds: visible,
        hideVoters: _hideVoters,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('FAMILY_PLANS post poll error: $e');
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'That did not go through. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDarkMode;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHeader(context, dark, 'Create a Poll'),
                const SizedBox(height: 8),
                _label(dark, 'Your question'),
                const SizedBox(height: 6),
                TextField(
                  controller: _question,
                  maxLength: 140,
                  textCapitalization: TextCapitalization.sentences,
                  style: GoogleFonts.nunitoSans(fontSize: 16, color: _text(dark)),
                  decoration: _fieldDecoration(dark,
                      hint: 'What should we get Nana for her birthday?'),
                ),
                const SizedBox(height: 14),
                _label(dark, 'Options', hint: '(2 to 4)'),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    avatar: const Icon(Icons.bolt_rounded, size: 18, color: _teal),
                    label: Text('Quick: Yes or No',
                        style: GoogleFonts.nunitoSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _text(dark))),
                    backgroundColor: _fieldBg(dark),
                    side: BorderSide(color: _teal.withAlpha(120)),
                    onPressed: () => setState(() {
                      while (_options.length > 2) {
                        _options.removeLast().dispose();
                      }
                      _options[0].text = 'Yes';
                      _options[1].text = 'No';
                    }),
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < _options.length; i++) ...[
                  TextField(
                    controller: _options[i],
                    maxLength: 60,
                    textCapitalization: TextCapitalization.sentences,
                    style:
                        GoogleFonts.nunitoSans(fontSize: 16, color: _text(dark)),
                    decoration: _fieldDecoration(dark, hint: 'Option ${i + 1}'),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_options.length < 4)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _teal,
                        side: const BorderSide(color: _teal, width: 2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => setState(
                          () => _options.add(TextEditingController())),
                      icon: const Icon(Icons.add_rounded),
                      label: Text('Add another option',
                          style: GoogleFonts.nunitoSans(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ),
                const SizedBox(height: 14),
                _label(dark, 'Poll closes in'),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: dark
                        ? const Color(0xFF2A241D)
                        : const Color(0xFFF1E3D3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < _closeLabels.length; i++)
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _closeChoice = i),
                            child: Container(
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _closeChoice == i
                                    ? _teal
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(_closeLabels[i],
                                  style: GoogleFonts.nunitoSans(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: _closeChoice == i
                                          ? Colors.white
                                          : _muted(dark))),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _WhoCanSeeRow(
                  isDarkMode: dark,
                  members: _members,
                  hiddenIds: _hidden,
                  noun: 'poll',
                  onTap: _members.isEmpty ? () {} : _pickVisibility,
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: _fieldBg(dark),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _fieldBorder(dark)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Hide who voted',
                                style: GoogleFonts.nunitoSans(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: _text(dark))),
                            Text(
                                _hideVoters
                                    ? 'Everyone sees the totals, but nobody (not even you) sees who picked what.'
                                    : 'Names show under each option.',
                                style: GoogleFonts.nunitoSans(
                                    fontSize: 13,
                                    height: 1.3,
                                    color: _muted(dark))),
                          ],
                        ),
                      ),
                      Switch(
                        value: _hideVoters,
                        activeColor: _teal,
                        onChanged: (v) => setState(() => _hideVoters = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _fieldBg(dark),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _fieldBorder(dark)),
                  ),
                  child: Text(
                    'Everyone who can see this poll can vote once, and can change their vote until it closes. Results show as they come in.',
                    style: GoogleFonts.nunitoSans(
                        fontSize: 14, height: 1.4, color: _muted(dark)),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: GoogleFonts.nunitoSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFC0392B))),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _teal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _saving ? null : _post,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white))
                        : Text('Post to the Family',
                            style: GoogleFonts.nunitoSans(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
