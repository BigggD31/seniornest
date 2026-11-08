import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/family_plans_service.dart';
import '../../profile_photo_picker_screen/profile_photo_picker_screen.dart';
import 'family_plans_palette.dart';
import 'family_plans_sheets.dart';

/// Nov 7 2026: the "Family Plans" tab on Home (build 1.06) -- plans and
/// polls for one nest. Who can see each item is enforced by the database;
/// this widget just shows whatever comes back.

class FamilyPlansTabWidget extends StatefulWidget {
  const FamilyPlansTabWidget({
    super.key,
    required this.isDarkMode,
    required this.nestId,
    required this.isArchived,
    required this.refreshTick,
  });

  final bool isDarkMode;
  final String nestId;
  final bool isArchived;

  /// Bumped by Home's pull-to-refresh so this tab reloads too.
  final int refreshTick;

  @override
  State<FamilyPlansTabWidget> createState() => _FamilyPlansTabWidgetState();
}

class _FamilyPlansTabWidgetState extends State<FamilyPlansTabWidget> {
  // Last result per nest, so switching tabs back and forth never flashes
  // an empty page while the fresh load runs.
  static final Map<String, FamilyPlansData> _cache = {};

  FamilyPlansData? _data;
  List<Map<String, String>> _members = [];
  bool _loadFailed = false;
  // Polls where the person tapped "Change my vote".
  final Set<String> _changingVote = {};
  RealtimeChannel? _channel;
  Timer? _debounce;
  bool _disposed = false;

  bool get _dark => widget.isDarkMode;
  String? get _me => FamilyPlansService.myId;

  @override
  void initState() {
    super.initState();
    _data = _cache[widget.nestId];
    _load();
    _loadMembers();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant FamilyPlansTabWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) _load();
    if (oldWidget.nestId != widget.nestId) {
      _data = _cache[widget.nestId];
      _load();
      _loadMembers();
      _subscribe();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    final ch = _channel;
    _channel = null;
    if (ch != null) Supabase.instance.client.removeChannel(ch);
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.nestId.isEmpty) return;
    try {
      final d = await FamilyPlansService.load(widget.nestId);
      _cache[widget.nestId] = d;
      if (!_disposed && mounted) {
        setState(() {
          _data = d;
          _loadFailed = false;
        });
      }
    } catch (e) {
      debugPrint('FAMILY_PLANS load error: $e');
      if (!_disposed && mounted && _data == null) {
        setState(() => _loadFailed = true);
      }
    }
  }

  Future<void> _loadMembers() async {
    if (widget.nestId.isEmpty) return;
    try {
      final m = await FamilyPlansService.otherMembers(widget.nestId);
      if (!_disposed && mounted) setState(() => _members = m);
    } catch (_) {}
  }

  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!_disposed && mounted) _load();
    });
  }

  void _subscribe() {
    final old = _channel;
    if (old != null) Supabase.instance.client.removeChannel(old);
    if (widget.nestId.isEmpty) return;
    var ch = Supabase.instance.client.channel('family_plans_rt_${widget.nestId}');
    for (final table in const [
      'family_plans',
      'family_polls',
      'poll_votes',
      'plan_rsvps',
      'family_item_hearts',
      'family_item_comments',
    ]) {
      ch = ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => _scheduleReload(),
      );
    }
    _channel = ch.subscribe();
  }

  // ── helpers ──────────────────────────────────────────────────

  PlansPalette get _p => PlansPalette(_dark);
  Color get _textColor => _p.ink;
  Color get _mutedColor => _p.muted;
  Color get _cardColor => _p.card;
  Color get _cardBorder => _p.border;

  String _nameOf(String userId) {
    if (userId == _me) return _data?.names[userId] ?? 'You';
    return _data?.names[userId] ??
        _members.firstWhere((m) => m['id'] == userId,
            orElse: () => {'name': 'Family'})['name']!;
  }

  /// Names of members who cannot see an item (empty if it is for everyone).
  List<String> _hiddenNames(List<String> visibleToIds) {
    if (visibleToIds.isEmpty) return [];
    return [
      for (final m in _members)
        if (!visibleToIds.contains(m['id'])) m['name']!
    ];
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _run(Future<void> Function() action, {String? fail}) async {
    try {
      await action();
      await _load();
    } catch (e) {
      debugPrint('FAMILY_PLANS action error: $e');
      if (mounted) _toast(fail ?? 'That did not go through. Please try again.');
    }
  }

  Future<bool> _confirm(String title, String body, String yes) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _createPlan() async {
    final ok = await showCreatePlanSheet(context,
        isDarkMode: _dark, nestId: widget.nestId);
    if (ok == true) _load();
  }

  Future<void> _createPoll() async {
    final ok = await showCreatePollSheet(context,
        isDarkMode: _dark, nestId: widget.nestId);
    if (ok == true) _load();
  }

  // ── build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final canCreate = !widget.isArchived;
    final plans = data?.plans ?? const <FamilyPlan>[];
    final polls = data?.polls ?? const <FamilyPoll>[];
    final upcoming = plans.where((p) => !p.isPast && !p.isCanceled).toList();
    final earlier = plans.where((p) => p.isPast || p.isCanceled).toList()
      ..sort((a, b) => b.startsAt.compareTo(a.startsAt));
    final noPlans = upcoming.isEmpty && earlier.isEmpty;

    final List<Widget> planBody;
    final List<Widget> pollBody;
    if (data == null) {
      planBody = [
        if (_loadFailed)
          _emptyNote('We could not load Family Plans. Pull down to try again.')
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child:
                Center(child: CircularProgressIndicator(color: _p.accent)),
          ),
      ];
      pollBody = const [];
    } else {
      planBody = [
        if (noPlans)
          (canCreate ? _samplePlanCard() : _emptyNote('No plans yet.')),
        for (final p in upcoming) _planCard(p, data),
        for (final p in earlier) _planCard(p, data),
      ];
      pollBody = [
        if (polls.isEmpty)
          (canCreate ? _samplePollCard() : _emptyNote('No polls yet.')),
        for (final p in polls) _pollCard(p, data),
      ];
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      decoration: BoxDecoration(
        color: _p.cream,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Upcoming Plans',
              'Birthdays, dinners, games, visits. Put it on the family calendar.'),
          if (canCreate) ...[
            _wideButton(Icons.add_rounded, 'Create a Plan', _createPlan,
                filled: true),
            const SizedBox(height: 14),
          ],
          ...planBody,
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, thickness: 1, color: _p.border),
          ),
          _sectionHeader('Family Polls',
              'Can\'t decide? Ask everyone. Anyone in the nest can start a poll.'),
          if (canCreate) ...[
            _wideButton(Icons.add_rounded, 'Create a Poll', _createPoll,
                filled: false),
            const SizedBox(height: 14),
          ],
          ...pollBody,
        ],
      ),
    );
  }

  Widget _wideButton(IconData icon, String label, VoidCallback onTap,
      {required bool filled}) {
    final text = Text(label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style:
            GoogleFonts.nunitoSans(fontSize: 17, fontWeight: FontWeight.w800));
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: filled
          ? ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _p.accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: shape,
              ),
              onPressed: onTap,
              icon: Icon(icon, size: 22),
              label: text,
            )
          : OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                backgroundColor: _p.card,
                foregroundColor: _p.deep,
                side: BorderSide(color: _p.accent, width: 2),
                shape: shape,
              ),
              onPressed: onTap,
              icon: Icon(icon, size: 22),
              label: text,
            ),
    );
  }

  Widget _sectionHeader(String t, String sub) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t,
                style: GoogleFonts.nunitoSans(
                    fontSize: 22, fontWeight: FontWeight.w800, color: _p.ink)),
            const SizedBox(height: 4),
            Text(sub,
                style: GoogleFonts.nunitoSans(
                    fontSize: 15, height: 1.35, color: _p.muted)),
          ],
        ),
      );

  Widget _emptyNote(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(t,
            style: GoogleFonts.nunitoSans(
                fontSize: 14, height: 1.4, color: _mutedColor)),
      );

  // ── sample placeholders (shown only while a section is empty) ───

  Widget _sampleChip() => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _p.chip,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('SAMPLE · yours will look like this',
              style: GoogleFonts.nunitoSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _p.chipText)),
        ),
      );

  Widget _samplePlanCard() {
    final d = DateTime.now().add(const Duration(days: 6));
    final weekday = DateFormat('EEE').format(d).toUpperCase();
    final day = DateFormat('d').format(d);
    Widget rsvp(String label, bool selected) => Expanded(
          child: Container(
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? _p.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _p.accent, width: 1.5),
            ),
            child: Text(label,
                style: GoogleFonts.nunitoSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : _p.accent)),
          ),
        );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toast('This is a sample. Tap Create a Plan to make a real one.'),
      child: _cardShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sampleChip(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dateBlock(weekday, day),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Nana\'s Birthday Dinner',
                          style: GoogleFonts.nunitoSans(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: _p.ink)),
                      const SizedBox(height: 2),
                      Text('6:00 PM · Nana\'s house',
                          style: GoogleFonts.nunitoSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _p.muted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('Pot roast and her favorite lemon cake. Bring a story to tell.',
                style: GoogleFonts.nunitoSans(
                    fontSize: 15, height: 1.4, color: _p.ink)),
            const SizedBox(height: 10),
            Row(
              children: [
                _initialDot(_me ?? '', _nameOf(_me ?? '')),
                const SizedBox(width: 8),
                Text('Posted by ${_nameOf(_me ?? '')}',
                    style:
                        GoogleFonts.nunitoSans(fontSize: 13, color: _p.muted)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                rsvp('Going', true),
                const SizedBox(width: 8),
                rsvp('Maybe', false),
                const SizedBox(width: 8),
                rsvp('Can\'t', false),
              ],
            ),
            const SizedBox(height: 8),
            Text('2 going, 1 maybe',
                style: GoogleFonts.nunitoSans(
                    fontSize: 14, fontWeight: FontWeight.w700, color: _p.deep)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.favorite_rounded,
                    size: 22, color: Color(0xFFE0566B)),
                const SizedBox(width: 5),
                Text('3',
                    style: GoogleFonts.nunitoSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _p.muted)),
                const SizedBox(width: 18),
                Icon(Icons.chat_bubble_outline_rounded,
                    size: 21, color: _p.muted),
                const SizedBox(width: 5),
                Text('2',
                    style: GoogleFonts.nunitoSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _p.muted)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _samplePollCard() {
    const options = [
      ['A photo book of the grandkids', '4'],
      ['Flowers and a spa day', '2'],
      ['A new tablet', '1'],
    ];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toast('This is a sample. Tap Create a Poll to make a real one.'),
      child: _cardShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sampleChip(),
            Text('What should we get Nana for her birthday?',
                style: GoogleFonts.nunitoSans(
                    fontSize: 17, fontWeight: FontWeight.w800, color: _p.ink)),
            const SizedBox(height: 10),
            for (var i = 0; i < options.length; i++)
              _pollOptionBox(
                text: options[i][0],
                count: int.parse(options[i][1]),
                frac: int.parse(options[i][1]) / 7,
                mine: i == 0,
                winner: false,
                onTap: null,
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                _initialDot(_me ?? '', _nameOf(_me ?? '')),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Posted by ${_nameOf(_me ?? '')} · 7 votes · Closes in 24 hours · You voted',
                      style: GoogleFonts.nunitoSans(
                          fontSize: 13, color: _p.muted)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateBlock(String weekday, String day) => Container(
        width: 60,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: _p.tint,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(weekday,
                style: GoogleFonts.nunitoSans(
                    fontSize: 13, fontWeight: FontWeight.w800, color: _p.deep)),
            Text(day,
                style: GoogleFonts.nunitoSans(
                    fontSize: 26,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: _p.deep)),
          ],
        ),
      );

  Widget _cardShell({required Widget child, bool faded = false}) {
    return Opacity(
      opacity: faded ? 0.6 : 1,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(20),
          border: _dark ? Border.all(color: _cardBorder) : null,
          boxShadow: _dark
              ? null
              : const [
                  BoxShadow(
                      color: Color(0x143B2F2A),
                      blurRadius: 8,
                      offset: Offset(0, 2)),
                ],
        ),
        child: child,
      ),
    );
  }

  Widget _privateTag(List<String> visibleToIds) {
    final hidden = _hiddenNames(visibleToIds);
    if (visibleToIds.isEmpty) return const SizedBox.shrink();
    final text = hidden.isEmpty
        ? 'Private'
        : 'Private · Hidden from ${hiddenNamesText(hidden)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _p.chip,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, size: 13, color: _p.chipText),
            const SizedBox(width: 5),
            Flexible(
              child: Text(text,
                  style: GoogleFonts.nunitoSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _p.chipText)),
            ),
          ],
        ),
      ),
    );
  }

  /// The person's real profile picture (or their initial), same as the
  /// rest of the app.
  Widget _initialDot(String userId, String name) => ProfileAvatarWidget(
        avatarUrl: FamilyPlansService.avatarUrls[userId] ?? '',
        displayName: name,
        size: 28,
        borderColor: Colors.transparent,
        borderWidth: 0,
      );

  Widget _heartAndComments(String type, String id, FamilyPlansData data) {
    final k = FamilyPlansService.key(type, id);
    final hearted = data.hearts[k]?.contains(_me) ?? false;
    final heartCount = data.hearts[k]?.length ?? 0;
    final commentCount = data.commentCounts[k] ?? 0;
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _run(() => FamilyPlansService.setHeart(type, id, !hearted)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              children: [
                Icon(hearted ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    size: 22,
                    color: hearted ? const Color(0xFFE0566B) : _mutedColor),
                if (heartCount > 0) ...[
                  const SizedBox(width: 5),
                  Text('$heartCount',
                      style: GoogleFonts.nunitoSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _mutedColor)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openComments(type, id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline_rounded,
                    size: 21, color: _mutedColor),
                if (commentCount > 0) ...[
                  const SizedBox(width: 5),
                  Text('$commentCount',
                      style: GoogleFonts.nunitoSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _mutedColor)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── plan card ────────────────────────────────────────────────

  Widget _planCard(FamilyPlan p, FamilyPlansData data) {
    final faded = p.isPast || p.isCanceled;
    final mine = p.authorId == _me;
    final day = DateFormat('d').format(p.startsAt);
    final when = DateFormat('EEE, MMM d · h:mm a').format(p.startsAt);
    final sameZone = p.sourceTz.isEmpty ||
        p.sourceTz == FamilyPlansService.zoneLabel(p.startsAt);
    final rsvps = data.rsvps[p.id] ?? const <String, String>{};
    final myRsvp = _me == null ? null : rsvps[_me!];
    final going = rsvps.values.where((v) => v == 'going').length;
    final maybe = rsvps.values.where((v) => v == 'maybe').length;
    final cant = rsvps.values.where((v) => v == 'cant').length;

    return _cardShell(
      faded: faded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _privateTag(p.visibleToIds),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dateBlock(DateFormat('EEE').format(p.startsAt).toUpperCase(), day),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (p.isCanceled)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text('Canceled',
                            style: GoogleFonts.nunitoSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFFC0392B))),
                      ),
                    Text(p.title,
                        style: GoogleFonts.nunitoSans(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: _textColor,
                            decoration: faded
                                ? TextDecoration.lineThrough
                                : TextDecoration.none)),
                    const SizedBox(height: 2),
                    Text(when,
                        style: GoogleFonts.nunitoSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _mutedColor)),
                    if (!sameZone)
                      Text('Planned in ${p.sourceTz}',
                          style: GoogleFonts.nunitoSans(
                              fontSize: 12, color: _mutedColor)),
                    if (p.location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.place_outlined,
                              size: 16, color: _mutedColor),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(p.location,
                                style: GoogleFonts.nunitoSans(
                                    fontSize: 14, color: _mutedColor)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (mine && !p.isPast)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz_rounded, color: _mutedColor),
                  onSelected: (v) => _onPlanMenu(v, p),
                  itemBuilder: (ctx) => [
                    if (!p.isCanceled)
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    if (!p.isCanceled)
                      const PopupMenuItem(
                          value: 'cancel', child: Text('Cancel plan')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                )
              else if (mine)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz_rounded, color: _mutedColor),
                  onSelected: (v) => _onPlanMenu(v, p),
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
          if (p.details.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(p.details,
                style: GoogleFonts.nunitoSans(
                    fontSize: 15, height: 1.4, color: _textColor)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _initialDot(p.authorId, _nameOf(p.authorId)),
              const SizedBox(width: 8),
              Text('Posted by ${_nameOf(p.authorId)}',
                  style: GoogleFonts.nunitoSans(
                      fontSize: 13, color: _mutedColor)),
            ],
          ),
          if (p.rsvpEnabled && !p.isCanceled && !p.isPast) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _rsvpButton(p, 'going', 'Going', myRsvp),
                const SizedBox(width: 8),
                _rsvpButton(p, 'maybe', 'Maybe', myRsvp),
                const SizedBox(width: 8),
                _rsvpButton(p, 'cant', 'Can\'t', myRsvp),
              ],
            ),
          ],
          if (p.rsvpEnabled && rsvps.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _showRsvpList(p, rsvps),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  [
                    if (going > 0) '$going going',
                    if (maybe > 0) '$maybe maybe',
                    if (cant > 0) '$cant can\'t',
                  ].join(', '),
                  style: GoogleFonts.nunitoSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _p.deep),
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          _heartAndComments('plan', p.id, data),
        ],
      ),
    );
  }

  Widget _rsvpButton(FamilyPlan p, String status, String label, String? mine) {
    final selected = mine == status;
    return Expanded(
      child: SizedBox(
        height: 42,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: selected ? _p.accent : Colors.transparent,
            foregroundColor: selected ? Colors.white : _p.accent,
            side: BorderSide(color: _p.accent, width: 1.5),
            padding: EdgeInsets.zero,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => _run(() => FamilyPlansService.setRsvp(p.id, status)),
          child: Text(label,
              style: GoogleFonts.nunitoSans(
                  fontSize: 14, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }

  void _showRsvpList(FamilyPlan p, Map<String, String> rsvps) {
    List<String> namesFor(String status) => [
          for (final e in rsvps.entries)
            if (e.value == status) _nameOf(e.key)
        ];
    final groups = <MapEntry<String, List<String>>>[
      MapEntry('Going', namesFor('going')),
      MapEntry('Maybe', namesFor('maybe')),
      MapEntry('Can\'t', namesFor('cant')),
    ].where((g) => g.value.isNotEmpty).toList();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final g in groups) ...[
                Text(g.key,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(g.value.join(', ')),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _onPlanMenu(String v, FamilyPlan p) async {
    if (v == 'edit') {
      final ok = await showCreatePlanSheet(context,
          isDarkMode: _dark, nestId: widget.nestId, editing: p);
      if (ok == true) _load();
    } else if (v == 'cancel') {
      if (await _confirm('Cancel this plan?',
          'Everyone who can see it will be told it was canceled.', 'Cancel plan')) {
        _run(() => FamilyPlansService.cancelPlan(p));
      }
    } else if (v == 'delete') {
      if (await _confirm('Delete this plan?',
          'It will disappear for everyone. This cannot be undone.', 'Delete')) {
        _run(() => FamilyPlansService.deletePlan(p.id));
      }
    }
  }

  // ── poll card ────────────────────────────────────────────────

  String _closesText(FamilyPoll p) {
    if (p.isClosed) return 'Closed';
    final left = p.closesAt.difference(DateTime.now());
    if (left.inDays >= 1) {
      final d = left.inDays;
      return 'Closes in $d ${d == 1 ? 'day' : 'days'}';
    }
    if (left.inHours >= 1) {
      final h = left.inHours;
      return 'Closes in $h ${h == 1 ? 'hour' : 'hours'}';
    }
    final m = left.inMinutes < 1 ? 1 : left.inMinutes;
    return 'Closes in $m ${m == 1 ? 'minute' : 'minutes'}';
  }

  Widget _pollCard(FamilyPoll p, FamilyPlansData data) {
    final mine = p.authorId == _me;
    final votes = data.votes[p.id] ?? const <String, int>{};
    final total = votes.length;
    final counts = List<int>.filled(p.options.length, 0);
    for (final v in votes.values) {
      if (v >= 0 && v < counts.length) counts[v]++;
    }
    final myVote = _me == null ? null : votes[_me!];
    final topCount = counts.isEmpty ? 0 : counts.reduce((a, b) => a > b ? a : b);

    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _privateTag(p.visibleToIds),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(p.question,
                    style: GoogleFonts.nunitoSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _textColor)),
              ),
              if (mine)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz_rounded, color: _mutedColor),
                  onSelected: (v) => _onPollMenu(v, p),
                  itemBuilder: (ctx) => [
                    if (!p.isClosed)
                      const PopupMenuItem(
                          value: 'close', child: Text('Close poll now')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < p.options.length; i++)
            _pollOption(p, i, counts[i], total, myVote == i,
                p.isClosed && counts[i] == topCount && topCount > 0,
                canPick: !p.isClosed &&
                    (myVote == null || _changingVote.contains(p.id))),
          if (!p.isClosed && myVote != null)
            Align(
              alignment: Alignment.centerLeft,
              child: _changingVote.contains(p.id)
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('Tap your new choice',
                          style: GoogleFonts.nunitoSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _p.deep)),
                    )
                  : TextButton(
                      style: TextButton.styleFrom(
                          foregroundColor: _p.deep,
                          padding: const EdgeInsets.symmetric(horizontal: 4)),
                      onPressed: () => setState(() => _changingVote.add(p.id)),
                      child: Text('Change my vote',
                          style: GoogleFonts.nunitoSans(
                              fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              _initialDot(p.authorId, _nameOf(p.authorId)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Posted by ${_nameOf(p.authorId)} · $total ${total == 1 ? 'vote' : 'votes'} · ${_closesText(p)}'
                  '${myVote != null ? ' · You voted' : ''}',
                  style: GoogleFonts.nunitoSans(
                      fontSize: 13, color: _mutedColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _heartAndComments('poll', p.id, data),
        ],
      ),
    );
  }

  Widget _pollOption(
      FamilyPoll p, int i, int count, int total, bool mine, bool winner,
      {required bool canPick}) {
    return _pollOptionBox(
      text: p.options[i],
      count: count,
      frac: total == 0 ? 0.0 : count / total,
      mine: mine,
      winner: winner,
      onTap: !canPick
          ? null
          : () async {
              await _run(() => FamilyPlansService.vote(p.id, i));
              if (mounted) setState(() => _changingVote.remove(p.id));
            },
    );
  }

  Widget _pollOptionBox({
    required String text,
    required int count,
    required double frac,
    required bool mine,
    required bool winner,
    required VoidCallback? onTap,
  }) {
    final highlight = mine || winner;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: highlight ? _p.accent : _cardBorder, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                if (highlight) Positioned.fill(child: ColoredBox(color: _p.tint)),
                FractionallySizedBox(
                  widthFactor: frac,
                  child: Container(
                      color: _p.accent.withAlpha(winner ? 60 : 30)),
                ),
                Positioned.fill(
                  child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (mine)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(Icons.check_circle_rounded,
                              size: 18, color: _p.accent),
                        ),
                      Expanded(
                        child: Text(text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.nunitoSans(
                                fontSize: 16,
                                fontWeight:
                                    highlight ? FontWeight.w800 : FontWeight.w700,
                                color: highlight ? _p.deep : _textColor)),
                      ),
                      Text('$count ${count == 1 ? 'vote' : 'votes'}',
                          style: GoogleFonts.nunitoSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: highlight ? _p.deep : _mutedColor)),
                    ],
                  ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onPollMenu(String v, FamilyPoll p) async {
    if (v == 'close') {
      if (await _confirm('Close this poll now?',
          'Nobody will be able to vote after this.', 'Close poll')) {
        _run(() => FamilyPlansService.closePollEarly(p.id));
      }
    } else if (v == 'delete') {
      if (await _confirm('Delete this poll?',
          'It will disappear for everyone. This cannot be undone.', 'Delete')) {
        _run(() => FamilyPlansService.deletePoll(p.id));
      }
    }
  }

  // ── comments ─────────────────────────────────────────────────

  void _openComments(String type, String id) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _p.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _CommentsSheet(
        isDarkMode: _dark,
        type: type,
        itemId: id,
        onChanged: _load,
      ),
    );
  }
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({
    required this.isDarkMode,
    required this.type,
    required this.itemId,
    required this.onChanged,
  });
  final bool isDarkMode;
  final String type;
  final String itemId;
  final Future<void> Function() onChanged;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _controller = TextEditingController();
  List<FamilyComment> _comments = [];
  Map<String, String> _names = {};
  bool _loading = true;
  bool _sending = false;

  bool get _dark => widget.isDarkMode;
  PlansPalette get _p => PlansPalette(_dark);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await FamilyPlansService.loadComments(widget.type, widget.itemId);
      final n = await FamilyPlansService.namesFor(c.map((e) => e.userId));
      if (mounted) {
        setState(() {
          _comments = c;
          _names = n;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('FAMILY_PLANS comments error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await FamilyPlansService.addComment(widget.type, widget.itemId, text);
      _controller.clear();
      widget.onChanged();
      // The comment is posted, so the box closes. Tap the speech bubble on
      // the card any time to read the comments again.
      if (mounted) Navigator.of(context).pop();
      return;
    } catch (e) {
      debugPrint('FAMILY_PLANS add comment error: $e');
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = _p.ink;
    final muted = _p.muted;
    final me = FamilyPlansService.myId;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Comments',
                    style: GoogleFonts.nunitoSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: text)),
                const SizedBox(height: 10),
                Flexible(
                  child: _loading
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                              child: CircularProgressIndicator(color: _p.accent)),
                        )
                      : _comments.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text('No comments yet. Be the first.',
                                  style: GoogleFonts.nunitoSans(
                                      fontSize: 15, color: muted)),
                            )
                          : ListView(
                              shrinkWrap: true,
                              children: [
                                for (final c in _comments)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ProfileAvatarWidget(
                                          avatarUrl: FamilyPlansService
                                                  .avatarUrls[c.userId] ??
                                              '',
                                          displayName:
                                              _names[c.userId] ?? 'Family',
                                          size: 30,
                                          borderColor: Colors.transparent,
                                          borderWidth: 0,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                  _names[c.userId] ??
                                                      (c.userId == me
                                                          ? 'You'
                                                          : 'Family'),
                                                  style: GoogleFonts.nunitoSans(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: _p.accent)),
                                              Text(c.body,
                                                  style: GoogleFonts.nunitoSans(
                                                      fontSize: 15,
                                                      height: 1.35,
                                                      color: text)),
                                            ],
                                          ),
                                        ),
                                        if (c.userId == me)
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            tooltip: 'Delete my comment',
                                            icon: Icon(Icons.delete_outline_rounded,
                                                size: 20, color: muted),
                                            onPressed: () async {
                                              final yes = await showDialog<bool>(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  title: const Text('Delete your comment?'),
                                                  content: const Text(
                                                      'This removes it for everyone.'),
                                                  actions: [
                                                    TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(ctx, false),
                                                        child: const Text('Keep it')),
                                                    TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(ctx, true),
                                                        child: const Text('Delete')),
                                                  ],
                                                ),
                                              );
                                              if (yes != true) return;
                                              await FamilyPlansService
                                                  .deleteComment(c.id);
                                              await _load();
                                              widget.onChanged();
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        maxLength: 500,
                        textCapitalization: TextCapitalization.sentences,
                        style: GoogleFonts.nunitoSans(fontSize: 15, color: text),
                        decoration: InputDecoration(
                          hintText: 'Write a comment',
                          counterText: '',
                          filled: true,
                          fillColor: _p.card,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: _p.border),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: _p.accent),
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
