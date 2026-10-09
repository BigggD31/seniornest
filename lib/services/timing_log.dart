import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Oct 9 2026: TEMPORARY diagnostic. Stamps how long each step of sign-in,
/// returning to the app, and sign-out takes, into temp_debug_logs (tag
/// TIMING_DEBUG). Steps recorded while signed out (e.g. the end of sign-out)
/// are held in memory and sent as soon as a session exists. Remove at wipe
/// time together with PUSH_DEBUG / BADGE_DEBUG.
class TimingLog {
  static final List<String> _pending = [];
  static String _flow = '';
  static DateTime? _start;

  static void begin(String flow) {
    _flow = flow;
    _start = DateTime.now();
    _add('begin');
  }

  static void mark(String step) => _add(step);

  static void _add(String step) {
    final s = _start;
    final ms = s == null ? -1 : DateTime.now().difference(s).inMilliseconds;
    final line = '$_flow +${ms}ms $step';
    debugPrint('TIMING: $line');
    _pending.add(line);
    _flush();
  }

  static void _flush() {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null || _pending.isEmpty) return;
    final batch = List<String>.from(_pending);
    _pending.clear();
    () async {
      try {
        await client.from('temp_debug_logs').insert([
          for (final m in batch) {'tag': 'TIMING_DEBUG', 'message': m},
        ]);
      } catch (_) {}
    }();
  }
}
