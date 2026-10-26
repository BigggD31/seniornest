import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_state.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';

/// Oct 26 2026 (build 314): lets someone who is ALREADY signed in join
/// another nest with an invite code, without going through onboarding again.
///
/// Steps (all inside one dialog): enter code -> "Join [Nest Name]?" with a
/// one-tap relationship question pre-filled from the person's existing
/// relationship -> join -> switch to that nest.
///
/// The relationship is stored per nest (nest_members.relation_type). Role,
/// name, photo, birthday and anniversary are NOT asked again -- they stay
/// per account.
class JoinNestFlow {
  static const List<String> relationships = [
    'Son',
    'Daughter',
    'Grandson',
    'Granddaughter',
    'Spouse',
    'Sibling',
    'Caregiver',
    'Friend',
    'Other',
  ];

  /// Pref key set after a sign-in when a typed invite code still needs to be
  /// joined (see save_messages_prompt_screen.dart). Home picks it up.
  static const String pendingCodePrefKey = 'pending_join_code';

  /// Opens the join dialog. [prefillCode] skips straight to the confirm step.
  static Future<void> start(BuildContext context, {String? prefillCode}) async {
    final result = await showDialog<_JoinResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _JoinDialog(prefillCode: prefillCode),
    );
    if (result == null || !context.mounted) return;
    await _switchToNest(context, result);
  }

  static Future<void> _switchToNest(
      BuildContext context, _JoinResult result) async {
    final prefs = await SharedPreferences.getInstance();
    await AuthService.clearStaleNestDataIfNestChanged(result.nestId);
    await prefs.setString('nest_id', result.nestId);
    await prefs.setString('nest_name', result.nestName);
    await prefs.setString('invite_code', result.code);
    await prefs.setBool('joined_via_invite', true);
    appNestNameNotifier.value = result.nestName;
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(
        context, AppRoutes.familyFeedScreen, (route) => false);
  }
}

class _JoinResult {
  _JoinResult(this.nestId, this.nestName, this.code);
  final String nestId;
  final String nestName;
  final String code;
}

enum _Stage { enterCode, confirm, joining }

class _JoinDialog extends StatefulWidget {
  const _JoinDialog({this.prefillCode});
  final String? prefillCode;

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  static const Color _teal = Color(0xFF5DA399);
  final TextEditingController _codeController = TextEditingController();
  _Stage _stage = _Stage.enterCode;
  bool _busy = false;
  String? _error;

  String? _nestId;
  String? _nestName;
  String _code = '';
  bool _alreadyMember = false;
  String? _relationship; // capitalized, e.g. 'Son'

  bool get _dark => appDarkModeNotifier.value;

  @override
  void initState() {
    super.initState();
    final pre = widget.prefillCode;
    if (pre != null && pre.trim().isNotEmpty) {
      _codeController.text = pre.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookup());
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  String _normalize(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  Future<void> _lookup() async {
    final code = _normalize(_codeController.text);
    if (code.isEmpty) {
      setState(() => _error = 'Please enter the invite code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final supabase = Supabase.instance.client;
      final userId = await AuthService.getReliableUserId();
      if (userId == null) {
        setState(() {
          _busy = false;
          _error = 'Please sign in again and try once more.';
        });
        return;
      }
      final lookup = await supabase
          .rpc('lookup_nest_by_invite_code', params: {'p_code': code});
      final nest = (lookup is List && lookup.isNotEmpty)
          ? lookup.first as Map<String, dynamic>
          : null;
      if (nest == null) {
        setState(() {
          _busy = false;
          _error =
              "We couldn't find that code. Please check it and try again.";
        });
        return;
      }
      final nestId = nest['id'] as String;
      final existing = await supabase
          .from('nest_members')
          .select('nest_id')
          .eq('nest_id', nestId)
          .eq('user_id', userId)
          .maybeSingle();
      // Pre-fill the relationship from what this person already told us.
      String? pre;
      try {
        final prof = await supabase
            .from('user_profiles')
            .select('relation_type')
            .eq('id', userId)
            .maybeSingle();
        final rel = (prof?['relation_type'] as String? ?? '').trim();
        if (rel.isNotEmpty) {
          final cap = rel[0].toUpperCase() + rel.substring(1).toLowerCase();
          if (JoinNestFlow.relationships.contains(cap)) pre = cap;
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _busy = false;
        _nestId = nestId;
        _nestName = (nest['name'] as String?)?.trim().isNotEmpty == true
            ? nest['name'] as String
            : 'this Nest';
        _code = code;
        _alreadyMember = existing != null;
        _relationship = pre;
        _stage = _Stage.confirm;
      });
    } catch (e) {
      debugPrint('JOIN_NEST_LOOKUP_ERROR: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  Future<void> _join() async {
    if (_alreadyMember) {
      Navigator.pop(context, _JoinResult(_nestId!, _nestName!, _code));
      return;
    }
    if (_relationship == null) return;
    setState(() {
      _stage = _Stage.joining;
      _error = null;
    });
    try {
      final supabase = Supabase.instance.client;
      final userId = await AuthService.getReliableUserId();
      if (userId == null) throw Exception('no user');
      await supabase.from('nest_members').upsert(
        {
          'nest_id': _nestId,
          'user_id': userId,
          'relation_type': _relationship!.toLowerCase(),
        },
        onConflict: 'nest_id,user_id',
      );
      if (!mounted) return;
      Navigator.pop(context, _JoinResult(_nestId!, _nestName!, _code));
    } catch (e) {
      debugPrint('JOIN_NEST_ERROR: $e');
      if (!mounted) return;
      setState(() {
        _stage = _Stage.confirm;
        _error = "We couldn't add you to that Nest. Please try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = _dark ? const Color(0xFF242018) : const Color(0xFFFAF3EC);
    final ink = _dark ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
    final muted = _dark ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

    Widget body;
    List<Widget> actions;

    if (_stage == _Stage.enterCode) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Enter the invite code you were sent.',
              style: GoogleFonts.nunitoSans(fontSize: 15, color: muted)),
          const SizedBox(height: 14),
          TextField(
            controller: _codeController,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            enabled: !_busy,
            style: GoogleFonts.nunitoSans(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
                color: ink),
            decoration: InputDecoration(
              hintText: 'INVITE CODE',
              hintStyle: GoogleFonts.nunitoSans(
                  fontSize: 15, letterSpacing: 2, color: muted),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onSubmitted: (_) => _lookup(),
          ),
          if (_error != null) _errorText(_error!),
        ],
      );
      actions = [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text('Cancel',
              style: GoogleFonts.nunitoSans(color: muted, fontSize: 15)),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _lookup,
          style: _tealStyle(),
          child: _busy ? _spinner() : _btnText('Continue'),
        ),
      ];
    } else {
      final joining = _stage == _Stage.joining;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_alreadyMember)
            Text("You're already part of this Nest.",
                style: GoogleFonts.nunitoSans(fontSize: 15, color: muted))
          else ...[
            Text('How are you connected to $_nestName?',
                style: GoogleFonts.nunitoSans(
                    fontSize: 16, fontWeight: FontWeight.w700, color: ink)),
            const SizedBox(height: 4),
            Text(
                _relationship != null
                    ? 'Tap Join if this is right, or choose another.'
                    : 'Choose the one that fits best.',
                style: GoogleFonts.nunitoSans(fontSize: 13, color: muted)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: JoinNestFlow.relationships.map((r) {
                final selected = r == _relationship;
                return ChoiceChip(
                  label: Text(r,
                      style: GoogleFonts.nunitoSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : ink)),
                  selected: selected,
                  selectedColor: _teal,
                  backgroundColor:
                      _dark ? const Color(0xFF3D3428) : Colors.white,
                  showCheckmark: false,
                  onSelected: joining
                      ? null
                      : (_) => setState(() => _relationship = r),
                );
              }).toList(),
            ),
          ],
          if (_error != null) _errorText(_error!),
        ],
      );
      actions = [
        TextButton(
          onPressed: joining ? null : () => Navigator.pop(context),
          child: Text('Cancel',
              style: GoogleFonts.nunitoSans(color: muted, fontSize: 15)),
        ),
        ElevatedButton(
          onPressed:
              (joining || (!_alreadyMember && _relationship == null))
                  ? null
                  : _join,
          style: _tealStyle(),
          child: joining
              ? _spinner()
              : _btnText(_alreadyMember ? 'Go there' : 'Join'),
        ),
      ];
    }

    final title = _stage == _Stage.enterCode
        ? 'Join a Nest with a code'
        : (_alreadyMember ? _nestName! : 'Join $_nestName?');

    return AlertDialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title,
          style: GoogleFonts.nunitoSans(
              fontSize: 19, fontWeight: FontWeight.w800, color: ink)),
      content: SingleChildScrollView(child: body),
      actions: actions,
    );
  }

  Widget _errorText(String msg) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(msg,
            style: GoogleFonts.nunitoSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFC0392B))),
      );

  ButtonStyle _tealStyle() => ElevatedButton.styleFrom(
        backgroundColor: _teal,
        disabledBackgroundColor: _teal.withAlpha(110),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _btnText(String t) => Text(t,
      style: GoogleFonts.nunitoSans(
          fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white));

  Widget _spinner() => const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));
}
