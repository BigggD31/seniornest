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
  // Items whose reply box is open (keys from FamilyPlansService.key).
  final Set<String> _replyOpen = {};
  // Plans whose RSVP names are opened (each person's own choice).
  final Set<String> _namesOpen = {};

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
      ['A photo book of the grandkids', '4', 'Ben, Lily, Michael, Sarah'],
      ['Flowers and a spa day', '2', 'Grandpa, Nana'],
      ['A new tablet', '1', 'Aunt Rosa'],
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
                names: options[i][2],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () =>
                  _run(() => FamilyPlansService.setHeart(type, id, !hearted)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                        hearted
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
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
            const SizedBox(width: 10),
            // Same Reply button as the home page.
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() {
                if (!_replyOpen.remove(k)) _replyOpen.add(k);
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.reply_rounded, size: 20, color: _mutedColor),
                    const SizedBox(width: 4),
                    Text(commentCount > 0 ? 'Reply ($commentCount)' : 'Reply',
                        style: GoogleFonts.nunitoSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _mutedColor)),
                  ],
                ),
              ),
            ),
          ],
        ),
        _InlineReplies(
          key: ValueKey('replies_$k'),
          isDarkMode: _dark,
          type: type,
          itemId: id,
          count: commentCount,
          composerOpen: _replyOpen.contains(k),
          onClose: () => setState(() => _replyOpen.remove(k)),
          onChanged: _load,
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
    // When the poster hides names, the database only gives counts.
    final hiddenRsvp = data.rsvpCounts[p.id];
    final going = hiddenRsvp?[0] ?? rsvps.values.where((v) => v == 'going').length;
    final maybe = hiddenRsvp?[1] ?? rsvps.values.where((v) => v == 'maybe').length;
    final cant = hiddenRsvp?[2] ?? rsvps.values.where((v) => v == 'cant').length;
    final audience =
        p.isPrivate ? p.visibleToIds.length : _members.length + 1;
    final waiting = audience - (going + maybe + cant);
    final namesOpen = _namesOpen.contains(p.id);
    final canOpenNames = !p.hideRsvpNames && rsvps.isNotEmpty;

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
          if (p.rsvpEnabled && (going + maybe + cant > 0 || waiting > 0)) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: canOpenNames
                  ? () => setState(() {
                        if (!_namesOpen.remove(p.id)) _namesOpen.add(p.id);
                      })
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        [
                          [
                            if (going > 0) '$going going',
                            if (maybe > 0) '$maybe maybe',
                            if (cant > 0) '$cant can\'t',
                          ].join(', '),
                          if (waiting > 0)
                            '$waiting ${waiting == 1 ? 'hasn\'t' : 'haven\'t'} answered',
                        ].where((t) => t.isNotEmpty).join(' · '),
                        style: GoogleFonts.nunitoSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _p.deep),
                      ),
                    ),
                    if (canOpenNames) ...[
                      const SizedBox(width: 6),
                      Icon(namesOpen ? Icons.expand_less : Icons.expand_more,
                          size: 18, color: _p.deep),
                    ],
                  ],
                ),
              ),
            ),
            if (p.hideRsvpNames)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  mine
                      ? 'You are keeping the names private'
                      : '${_nameOf(p.authorId)} is keeping the names private',
                  style:
                      GoogleFonts.nunitoSans(fontSize: 12, color: _mutedColor),
                ),
              ),
            if (canOpenNames && namesOpen) _rsvpNames(rsvps),
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

  Widget _rsvpNames(Map<String, String> rsvps) {
    List<String> namesFor(String status) => [
          for (final e in rsvps.entries)
            if (e.value == status) _nameOf(e.key)
        ];
    final groups = <MapEntry<String, List<String>>>[
      MapEntry('Going', namesFor('going')),
      MapEntry('Maybe', namesFor('maybe')),
      MapEntry('Can\'t', namesFor('cant')),
    ].where((g) => g.value.isNotEmpty).toList();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: BoxDecoration(
        color: _dark ? const Color(0xFF1A1612) : const Color(0xFFF6EFE3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final g in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(g.key,
                        style: GoogleFonts.nunitoSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _p.deep)),
                  ),
                  Expanded(
                    child: Text(g.value.join(', '),
                        style: GoogleFonts.nunitoSans(
                            fontSize: 14, height: 1.35, color: _textColor)),
                  ),
                ],
              ),
            ),
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
    var counts = List<int>.filled(p.options.length, 0);
    // Names under each option, only when the creator left voters visible.
    final voters = List<List<String>>.generate(p.options.length, (_) => []);
    if (p.hideVoters && data.hiddenCounts[p.id] != null) {
      counts = List<int>.from(data.hiddenCounts[p.id]!);
    } else {
      for (final e in votes.entries) {
        final v = e.value;
        if (v >= 0 && v < counts.length) {
          counts[v]++;
          if (!p.hideVoters) voters[v].add(_nameOf(e.key));
        }
      }
      for (final l in voters) {
        l.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      }
    }
    final total = counts.fold<int>(0, (a, b) => a + b);
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
                names: voters[i].join(', '),
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
          if (p.hideVoters)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 14, color: _p.chipText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Private votes · nobody sees who voted for what',
                        style: GoogleFonts.nunitoSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _p.chipText)),
                  ),
                ],
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
      {required bool canPick, String names = ''}) {
    return _pollOptionBox(
      text: p.options[i],
      names: names,
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
    String names = '',
  }) {
    final highlight = mine || winner;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
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
              // Fill the whole option even when there are no votes yet
              // (a zero-width vote bar used to collapse the option).
              fit: StackFit.expand,
              children: [
                if (highlight) Positioned.fill(child: ColoredBox(color: _p.tint)),
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: frac.clamp(0.0, 1.0),
                      heightFactor: 1,
                      child: ColoredBox(
                          color: _p.accent.withAlpha(winner ? 60 : 30)),
                    ),
                  ),
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
          if (names.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 14, top: 4),
              child: Text(names,
                  style: GoogleFonts.nunitoSans(
                      fontSize: 13, height: 1.3, color: _mutedColor)),
            ),
        ],
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
}

String _replyAgo(DateTime ts) {
  final diff = DateTime.now().difference(ts);
  if (diff.inMinutes < 60) return '${diff.inMinutes < 0 ? 0 : diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  return '${diff.inDays}d ago';
}

/// Replies shown under a plan or poll card, laid out like the home page:
/// an "N replies" toggle, the thread, and a "Write a reply..." box that
/// opens under the card. Replaces the old Comments pop-up (build 1.06).
class _InlineReplies extends StatefulWidget {
  const _InlineReplies({
    super.key,
    required this.isDarkMode,
    required this.type,
    required this.itemId,
    required this.count,
    required this.composerOpen,
    required this.onClose,
    required this.onChanged,
  });
  final bool isDarkMode;
  final String type;
  final String itemId;
  final int count;
  final bool composerOpen;
  final VoidCallback onClose;
  final Future<void> Function() onChanged;

  @override
  State<_InlineReplies> createState() => _InlineRepliesState();
}

class _InlineRepliesState extends State<_InlineReplies> {
  final _controller = TextEditingController();
  List<FamilyComment> _replies = [];
  Map<String, String> _names = {};
  bool _showReplies = false;
  bool _sending = false;

  bool get _dark => widget.isDarkMode;
  PlansPalette get _p => PlansPalette(_dark);

  @override
  void initState() {
    super.initState();
    if (widget.count > 0) _load();
  }

  @override
  void didUpdateWidget(covariant _InlineReplies old) {
    super.didUpdateWidget(old);
    // The parent reloads (and the count changes) when anyone replies or
    // deletes, so refresh the thread whenever the count moves.
    if (old.count != widget.count) {
      if (widget.count == 0) {
        setState(() => _replies = []);
      } else {
        _load();
      }
    }
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
          _replies = c;
          _names = n;
        });
      }
    } catch (e) {
      debugPrint('FAMILY_PLANS replies error: $e');
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await FamilyPlansService.addComment(widget.type, widget.itemId, text);
      _controller.clear();
      await _load();
      if (mounted) {
        setState(() {
          _sending = false;
          _showReplies = true;
        });
      }
      widget.onClose();
      widget.onChanged();
      return;
    } catch (e) {
      debugPrint('FAMILY_PLANS add reply error: $e');
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _delete(FamilyComment c) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your reply?'),
        content: const Text('This removes it for everyone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await FamilyPlansService.deleteComment(c.id);
      await _load();
      widget.onChanged();
    } catch (e) {
      debugPrint('FAMILY_PLANS delete reply error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = _p.muted;
    final me = FamilyPlansService.myId;
    final teal = const Color(0xFF5DA399);
    final boxColor =
        _dark ? const Color(0xFF1A1612) : const Color(0xFFF0EBE3);
    final boxBorder =
        _dark ? const Color(0xFF3D3428) : const Color(0xFFE0D8CC);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_replies.isNotEmpty) ...[
          GestureDetector(
            onTap: () => setState(() => _showReplies = !_showReplies),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
              child: Row(
                children: [
                  Icon(_showReplies ? Icons.expand_less : Icons.expand_more,
                      size: 16, color: teal),
                  const SizedBox(width: 4),
                  Text(
                    _showReplies
                        ? 'Hide replies'
                        : '${_replies.length} ${_replies.length == 1 ? 'reply' : 'replies'}',
                    style: GoogleFonts.nunitoSans(
                        fontSize: 12,
                        color: teal,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          if (_showReplies)
            for (final c in _replies)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(10, 0, 0, 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: boxColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: boxBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                            _names[c.userId] ??
                                (c.userId == me ? 'You' : 'Family'),
                            style: GoogleFonts.nunitoSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _p.ink)),
                        const SizedBox(width: 8),
                        Text(_replyAgo(c.createdAt),
                            style: GoogleFonts.nunitoSans(
                                fontSize: 11, color: muted)),
                        const Spacer(),
                        if (c.userId == me)
                          GestureDetector(
                            onTap: () => _delete(c),
                            child: Icon(Icons.delete_outline_rounded,
                                size: 18, color: muted),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(c.body,
                        style: GoogleFonts.nunitoSans(
                            fontSize: 13, color: _p.ink)),
                  ],
                ),
              ),
        ],
        if (widget.composerOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    style: GoogleFonts.nunitoSans(fontSize: 13, color: _p.ink),
                    decoration: InputDecoration(
                      hintText: 'Write a reply...',
                      hintStyle:
                          GoogleFonts.nunitoSans(fontSize: 13, color: muted),
                      counterText: '',
                      filled: true,
                      fillColor: boxColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sending ? null : _send,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration:
                        BoxDecoration(color: teal, shape: BoxShape.circle),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded,
                            color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
