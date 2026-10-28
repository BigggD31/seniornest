import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_state.dart';
import '../services/auth_service.dart';
import 'join_nest_flow.dart';

/// Oct 27 2026 (build 317): lets someone change how they are related to the
/// senior after sign-up, from Settings -> Your Nest -> Your Relationship.
///
/// The answer is stored per nest (nest_members.relation_type), the same place
/// the join-another-nest flow writes it, so someone in several nests can pick
/// a different relationship in each. Members may already update their own
/// nest_members row (policy users_manage_own_nest_members), so no backend
/// change is needed.
class RelationshipEditor {
  static String _cap(String s) =>
      s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1).toLowerCase();

  /// The signed-in person's relationship in the nest saved on this device,
  /// capitalized ('Granddaughter'), or '' if none is set.
  static Future<String> loadCurrent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nestId = prefs.getString('nest_id') ?? '';
      final userId = await AuthService.getReliableUserId();
      if (nestId.isEmpty || userId == null) return '';
      final supabase = Supabase.instance.client;
      final row = await supabase
          .from('nest_members')
          .select('relation_type')
          .eq('nest_id', nestId)
          .eq('user_id', userId)
          .maybeSingle();
      var rel = (row?['relation_type'] as String? ?? '').trim();
      if (rel.isEmpty) {
        final prof = await supabase
            .from('user_profiles')
            .select('relation_type')
            .eq('id', userId)
            .maybeSingle();
        rel = (prof?['relation_type'] as String? ?? '').trim();
      }
      return _cap(rel);
    } catch (e) {
      debugPrint('RELATIONSHIP_LOAD_ERROR: $e');
      return '';
    }
  }

  /// Opens the editor. Returns true if a new relationship was saved.
  static Future<bool> show(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final nestId = prefs.getString('nest_id') ?? '';
    final nestName = prefs.getString('nest_name') ?? '';
    final current = await loadCurrent();
    if (!context.mounted) return false;
    final chosen = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RelationshipDialog(nestName: nestName, initial: current),
    );
    if (chosen == null || chosen == current) return false;
    final messenger =
        context.mounted ? ScaffoldMessenger.maybeOf(context) : null;
    try {
      final userId = await AuthService.getReliableUserId();
      if (nestId.isEmpty || userId == null) throw Exception('no nest or user');
      final supabase = Supabase.instance.client;
      final updated = await supabase
          .from('nest_members')
          .update({'relation_type': chosen.toLowerCase()})
          .eq('nest_id', nestId)
          .eq('user_id', userId)
          .select('user_id');
      if ((updated as List).isEmpty) {
        // No row yet for this nest: create it the same way joining does.
        await supabase.from('nest_members').upsert(
          {
            'nest_id': nestId,
            'user_id': userId,
            'relation_type': chosen.toLowerCase(),
          },
          onConflict: 'nest_id,user_id',
        );
      }
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Saved. Your relationship is now: $chosen.'),
          backgroundColor: const Color(0xFF5DA399),
          duration: const Duration(seconds: 3),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('RELATIONSHIP_SAVE_ERROR: $e');
      messenger?.showSnackBar(
        const SnackBar(
          content: Text("We couldn't save that just now. Please try again."),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
      return false;
    }
  }
}

class _RelationshipDialog extends StatefulWidget {
  const _RelationshipDialog({required this.nestName, required this.initial});

  final String nestName;
  final String initial;

  @override
  State<_RelationshipDialog> createState() => _RelationshipDialogState();
}

class _RelationshipDialogState extends State<_RelationshipDialog> {
  static const Color _teal = Color(0xFF5DA399);
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial.isEmpty ? null : widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final dark = appDarkModeNotifier.value;
    final bg = dark ? const Color(0xFF242018) : const Color(0xFFFAF3EC);
    final ink = dark ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
    final muted = dark ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);
    final changed = _selected != null && _selected != widget.initial;

    return AlertDialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text.rich(
        TextSpan(
          style: GoogleFonts.nunitoSans(
              fontSize: 19, fontWeight: FontWeight.w700, color: ink),
          children: [
            const TextSpan(text: 'How are you related to the '),
            TextSpan(
              text: 'senior',
              style: GoogleFonts.nunitoSans(
                  fontSize: 23, fontWeight: FontWeight.w900, color: ink),
            ),
            const TextSpan(text: '?'),
          ],
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.nestName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(widget.nestName,
                    style:
                        GoogleFonts.nunitoSans(fontSize: 14, color: muted)),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: JoinNestFlow.relationships.map((r) {
                final selected = r == _selected;
                return ChoiceChip(
                  label: Text(r,
                      style: GoogleFonts.nunitoSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : ink)),
                  selected: selected,
                  selectedColor: _teal,
                  backgroundColor:
                      dark ? const Color(0xFF3D3428) : Colors.white,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _selected = r),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: GoogleFonts.nunitoSans(color: muted, fontSize: 15)),
        ),
        ElevatedButton(
          onPressed: changed ? () => Navigator.pop(context, _selected) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _teal,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('Save',
              style: GoogleFonts.nunitoSans(
                  fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
