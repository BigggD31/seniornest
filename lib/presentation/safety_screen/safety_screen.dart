import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/app_navigation.dart';
import '../../widgets/keyboard_done_bar.dart';
import '../profile_photo_picker_screen/profile_photo_picker_screen.dart';
import '../../core/app_state.dart';
import '../../services/push_service.dart';
import '../family_feed_screen/widgets/daily_checkin_card_widget.dart';
import '../family_feed_screen/widgets/daily_meds_card_widget.dart';

class SafetyScreen extends StatefulWidget {
  const SafetyScreen({super.key});

  @override
  State<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends State<SafetyScreen>
    with TickerProviderStateMixin {
  int _currentNavIndex = 3;
  bool _isSenior = appIsSeniorNotifier.value;
  // Seeded from the already-resolved app-wide notifier instead of a
  // hardcoded false -- see messages_inbox_screen.dart for the full
  // explanation of the white-flash bug this fixes.
  bool _isDarkMode = appDarkModeNotifier.value;
  bool _isLoading = true;
  bool _isNestArchived = false; // Aug 31 2026: Archive Nest Mode -- quiets SOS/check-in section when true
  bool _isSendingAlert = false;
  String _seniorName = appSeniorNameNotifier.value;
  // Sep 2 2026: every senior in the nest, each with their own check-in/meds
  // status -- powers _buildCheckInSection's per-senior cards and the
  // "This is what ___ sees" banner's name (single, joined, or generic
  // plural depending on how many). See _loadData's tail for the fetch.
  List<Map<String, dynamic>> _seniorStatuses = [];
  // Was reading its own local prefs copy separately -- now points at the
  // same already-resolved notifier every other screen uses, closing the
  // last gap in the app-wide nest-name flash fix (build 173).
  String _nestName = appNestNameNotifier.value;
  Map<String, dynamic>? _profileData;
  String _displayName = appDisplayNameNotifier.value;

  late AnimationController _entranceController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  late List<Animation<double>> _itemAnimations;

  List<Map<String, dynamic>> _mockContacts = [];

  static const List<Map<String, String>> _safetyTips = [
    {
      'icon': '💊',
      'title': 'Medication Safety',
      'tip':
          'Always take medications as prescribed. Never skip or double doses.',
    },
    {
      'icon': '🚿',
      'title': 'Fall Prevention',
      'tip':
          'Use grab bars in the bathroom and keep pathways clear of clutter.',
    },
    {
      'icon': '🌡️',
      'title': 'Stay Hydrated',
      'tip':
          'Drink at least 8 glasses of water daily, especially in warm weather.',
    },
    {
      'icon': '🏠',
      'title': 'Home Safety',
      'tip':
          'Keep emergency numbers visible and ensure good lighting throughout your home.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _itemAnimations = [];
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    // Cache-first: show cached contacts instantly (same pattern as Home's
    // nest members / checkin cache), then refresh from Supabase quietly in
    // the background. Previously this screen had no cache at all and an
    // unconditional 300ms delay before even starting the network fetch --
    // guaranteed empty-box time on every visit. Removed the delay; added
    // the cache.
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final cachedContactsUserId = prefs.getString('cached_safety_contacts_user_id') ?? '';
    List<Map<String, dynamic>> initialContacts = [];
    if (cachedContactsUserId.isNotEmpty && cachedContactsUserId == currentUserId) {
      final cachedContactsJson = prefs.getString('cached_safety_contacts');
      if (cachedContactsJson != null && cachedContactsJson.isNotEmpty) {
        try {
          final List<dynamic> cachedList = jsonDecode(cachedContactsJson) as List<dynamic>;
          initialContacts = cachedList.map((c) => Map<String, dynamic>.from(c as Map)).toList();
        } catch (_) {}
      }
    }

    // Everything else this screen needs before the senior-name network
    // lookup is a synchronous SharedPreferences read -- no reason to wait
    // on a network round-trip to paint the screen with these.
    final systemDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    final profileJson = prefs.getString(kProfilePhotoKey);
    Map<String, dynamic>? profileData;
    if (profileJson != null) {
      try {
        profileData = jsonDecode(profileJson) as Map<String, dynamic>;
      } catch (_) {}
    }
    final isSeniorRole = (prefs.getString('user_role') ?? 'senior') == 'senior';
    String initialSeniorName;
    if (isSeniorRole) {
      initialSeniorName = (prefs.getString('preferred_name') ?? '').isNotEmpty
          ? prefs.getString('preferred_name')!
          : (prefs.getString('display_name') ?? prefs.getString('user_name') ?? '');
    } else {
      // Aug 25 2026: was reading 'senior_name', a key never actually
      // written anywhere in the app -- confirmed via full codebase
      // search -- so this was blank on every single first paint for
      // every family member, guaranteed, not an occasional flash.
      // cached_checkin_senior_name is family_feed_screen's real, working
      // cache of this same value (written after its own live
      // nest_members lookup resolves); appSeniorNameNotifier is already
      // seeded from it at cold start, so this local read now matches.
      initialSeniorName = prefs.getString('cached_checkin_senior_name') ?? '';
    }

    // Archive Nest Mode: fetched here, before the initial paint, not
    // tacked on after -- Aug 31 2026, D Von found the original placement
    // (after _isLoading flips false) caused the real SOS button and
    // check-in section to render first, then get replaced by the banner
    // a moment later. On fast navigation this fetch could also lose the
    // mounted race entirely, since it ran after several other awaits.
    // Deliberately still a live read every load (see the same reasoning
    // in family_feed_screen.dart's matching fetch), just moved earlier so
    // it's already resolved by the time anything paints.
    bool isNestArchived = false;
    try {
      final nestId = prefs.getString('nest_id') ?? '';
      if (nestId.isNotEmpty) {
        final nestRow = await Supabase.instance.client
            .from('nests')
            .select('is_archived')
            .eq('id', nestId)
            .maybeSingle();
        isNestArchived = nestRow?['is_archived'] as bool? ?? false;
      }
    } catch (e) {
      debugPrint('Load nest archive status error: $e');
    }

    // Sep 3 2026: this section had no synchronous cache-seed at all --
    // _seniorStatuses always started genuinely empty, so the generic
    // "Let your family know you're okay" / "Waiting for today's
    // check-in" fallback (see the `else` branch of _buildCheckInSection
    // below) showed on literally every single visit to this screen,
    // every time, until the live nest_members fetch further down
    // resolved -- not an occasional flash, a guaranteed one. Confirmed
    // via D Von's screenshots (Sep 3): captured the fallback card, then
    // the real one, same visit. Home's equivalent already had this exact
    // seed (initialSeniorStatuses, built the same day as the multi-senior
    // work itself) -- this screen's new multi-senior section just never
    // got the same treatment. Reuses the same shared cache keys Home's
    // live fetch already writes, with the same nest_id + today's-date
    // validation before trusting them.
    final cachedCheckinNestId = prefs.getString('cached_checkin_nest_id') ?? '';
    final cachedCheckinDate = prefs.getString('cached_checkin_date') ?? '';
    List<Map<String, dynamic>> initialSeniorStatuses = [];
    if (cachedCheckinNestId.isNotEmpty &&
        cachedCheckinNestId == (prefs.getString('nest_id') ?? '') &&
        cachedCheckinDate == _todayDateString()) {
      final cachedSeniorId = prefs.getString('cached_checkin_senior_id') ?? '';
      if (cachedSeniorId.isNotEmpty) {
        final cachedTimeStr = prefs.getString('cached_checkin_time');
        final cachedMedsTimeStr = prefs.getString('cached_checkin_meds_time');
        initialSeniorStatuses = [
          {
            'id': cachedSeniorId,
            'name': prefs.getString('cached_checkin_senior_name') ?? '',
            'checkedIn': prefs.getBool('cached_checkin_checked_in') ?? false,
            'checkinTime':
                cachedTimeStr != null ? DateTime.tryParse(cachedTimeStr) : null,
            'medsTaken': prefs.getBool('cached_checkin_meds_taken') ?? false,
            'medsTime': cachedMedsTimeStr != null
                ? DateTime.tryParse(cachedMedsTimeStr)
                : null,
          },
        ];
      }
    }

    setState(() {
      if (initialContacts.isNotEmpty) {
        _mockContacts = initialContacts;
      }
      _isNestArchived = isNestArchived;
      _isSenior = isSeniorRole;
      _isDarkMode = prefs.getBool('dark_mode') ?? systemDark;
      _seniorName = initialSeniorName;
      if (initialSeniorStatuses.isNotEmpty) {
        _seniorStatuses = initialSeniorStatuses;
      }
      _isLoading = false;
      _profileData = profileData;
      _displayName = (prefs.getString('preferred_name') ?? '').isNotEmpty
          ? prefs.getString('preferred_name')!
          : (prefs.getString('display_name') ?? '');
    });
    // See the matching comment in family_feed_screen.dart -- appIsSeniorNotifier
    // only re-resolves at true cold-start, so an in-session account switch
    // needs this screen's own fresh cache read to correct the shared
    // notifier too.
    appIsSeniorNotifier.value = isSeniorRole;
    appDisplayNameNotifier.value = _displayName;
    if (initialSeniorName.isNotEmpty) {
      appSeniorNameNotifier.value = initialSeniorName;
    }
    _setupAnimations();
    _entranceController.forward();

    // Live refresh from Supabase -- updates quietly in place, no second
    // entrance animation (same pattern as Home's background refresh).
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final response = await supabase
            .from('safety_contacts')
            .select()
            .eq('user_id', userId)
            .order('is_primary', ascending: false)
            .order('created_at');
        final contacts = response as List<dynamic>;
        final freshContacts = contacts.map((c) => {
          'id': c['id'],
          'name': c['name'],
          'phone': c['phone'],
          'relation': c['relation'] ?? '',
          'isPrimary': c['is_primary'] ?? false,
        }).toList();
        setState(() {
          _mockContacts = freshContacts;
        });
        _setupAnimations();
        await prefs.setString('cached_safety_contacts', jsonEncode(freshContacts));
        await prefs.setString('cached_safety_contacts_user_id', userId);
      }
    } catch (e) {
      debugPrint('Load contacts error: $e');
    }

    // Sep 2 2026: replaced the old single-senior .maybeSingle() lookup --
    // that call throws/fails silently the moment a nest has TWO seniors
    // (role='senior' matching more than one row), since maybeSingle()
    // only tolerates 0 or 1 results. Now fetches every senior in the
    // nest, with today's real check-in/meds status for each, powering
    // both the per-senior cards below and the "This is what ___ sees"
    // banner's name (joined for 2, generic for 3+).
    try {
      final supabase = Supabase.instance.client;
      final nestId = prefs.getString('nest_id') ?? '';
      if (nestId.isNotEmpty) {
        final memberRows = await supabase
            .from('nest_members')
            .select('user_id, user_profiles(display_name, preferred_name, role)')
            .eq('nest_id', nestId);
        final members = memberRows as List<dynamic>;

        final List<Map<String, String>> seniors = [];
        for (final m in members) {
          final profile = m['user_profiles'] as Map<String, dynamic>?;
          if (profile?['role'] == 'senior') {
            final id = m['user_id'] as String? ?? '';
            if (id.isEmpty) continue;
            final preferred = profile?['preferred_name'] as String? ?? '';
            final first = profile?['display_name'] as String? ?? '';
            final name = preferred.isNotEmpty ? preferred : first;
            seniors.add({'id': id, 'name': name.isNotEmpty ? name : 'Your senior'});
          }
        }

        if (seniors.isNotEmpty) {
          final today = _todayDateString();
          final futures = <Future<dynamic>>[];
          for (final s in seniors) {
            futures.add(supabase
                .from('daily_checkins')
                .select('created_at')
                .eq('user_id', s['id']!)
                .eq('checkin_date', today)
                .maybeSingle());
            futures.add(supabase
                .from('daily_medications')
                .select('created_at')
                .eq('user_id', s['id']!)
                .eq('med_date', today)
                .maybeSingle());
          }
          final results = await Future.wait(futures);

          final List<Map<String, dynamic>> seniorStatuses = [];
          for (int i = 0; i < seniors.length; i++) {
            final checkinResponse = results[i * 2];
            final medsResponse = results[i * 2 + 1];
            seniorStatuses.add({
              'id': seniors[i]['id']!,
              'name': seniors[i]['name']!,
              'checkedIn': checkinResponse != null,
              'checkinTime': checkinResponse != null
                  ? DateTime.parse(checkinResponse['created_at'] as String)
                  : null,
              'medsTaken': medsResponse != null,
              'medsTime': medsResponse != null
                  ? DateTime.parse(medsResponse['created_at'] as String)
                  : null,
            });
          }

          final joinedName = _joinSeniorNames(
              seniorStatuses.map((s) => s['name'] as String).toList());

          if (mounted) {
            setState(() {
              _seniorStatuses = seniorStatuses;
              if (!isSeniorRole) _seniorName = joinedName;
            });
          }
          if (!isSeniorRole) {
            appSeniorNameNotifier.value = joinedName;
            await prefs.setString('cached_checkin_senior_name', joinedName);
          }
        }
      }
    } catch (e) {
      debugPrint('SAFETY SENIOR NAME LOAD ERROR: $e');
    }
  }

  // Sep 2 2026: same implementation as family_feed_screen.dart's helper --
  // needed here now that this screen also queries daily_checkins/
  // daily_medications directly for the per-senior cards.
  String _todayDateString() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  // Sep 2 2026: joins senior names naturally for the "This is what ___
  // sees" banner and the per-senior card list -- one name unchanged,
  // two names joined with "and", three or more fall back to a generic
  // plural rather than an unwieldy list.
  String _joinSeniorNames(List<String> names) {
    if (names.isEmpty) return 'your loved one';
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} and ${names[1]}';
    return 'your loved ones';
  }

  void _setupAnimations() {
    _itemAnimations.clear();
    final count = _mockContacts.length + _safetyTips.length + 3;
    for (int i = 0; i < count; i++) {
      final start = (i * 0.08).clamp(0.0, 0.7);
      final end = (start + 0.4).clamp(0.0, 1.0);
      _itemAnimations.add(
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Color get _bg =>
      _isDarkMode ? const Color(0xFF1A1612) : const Color(0xFFFDFDFD);
  Color get _surface =>
      _isDarkMode ? const Color(0xFF242018) : const Color(0xFFF5F0E8);
  Color get _cardBg =>
      _isDarkMode ? const Color(0xFF242018) : const Color(0xFFFAF7F2);
  Color get _cardBorder =>
      _isDarkMode ? const Color(0xFF3D3428) : const Color(0xFFE8E0D0);
  Color get _textPrimary =>
      _isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      _isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  void _showSOSConfirmation() {
    // Guards against a fast double-tap firing _sendMessageToContacts twice
    // before Navigator.pop(ctx) has a chance to close the dialog -- this is
    // a plain closure-captured flag, not widget state, because the dialog
    // itself isn't a StatefulWidget; the check-and-set below is synchronous
    // so it's safe against a rapid double-tap even though the send itself
    // is async.
    bool actionTaken = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFC0392B).withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.help_outline_rounded,
                  color: Color(0xFFC0392B),
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Are you okay right now?',
                textAlign: TextAlign.center,
                style: GoogleFonts.nunitoSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Let your family know how you\'re doing.',
                textAlign: TextAlign.center,
                style: GoogleFonts.nunitoSans(
                  fontSize: 14,
                  color: _textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              // Green "I'm Okay" button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (actionTaken) return;
                    actionTaken = true;
                    Navigator.pop(ctx);
                    _sendMessageToContacts(
                      "I'm okay right now, but please check on me when you can.",
                      isEmergency: false,
                    );
                  },
                  icon: const Icon(Icons.check_circle_rounded, size: 22),
                  label: Text(
                    "I'm Okay",
                    style: GoogleFonts.nunitoSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF27AE60),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Red "I Need Help" button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (actionTaken) return;
                    actionTaken = true;
                    Navigator.pop(ctx);
                    _sendMessageToContacts(
                      "EMERGENCY – I need help right now. Please call me immediately.",
                      isEmergency: true,
                    );
                  },
                  icon: const Icon(Icons.sos_rounded, size: 22),
                  label: Text(
                    "I Need Help",
                    style: GoogleFonts.nunitoSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC0392B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 15,
                    color: _textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendMessageToContacts(
    String message, {
    required bool isEmergency,
  }) async {
    setState(() => _isSendingAlert = true);
    bool smsComposerOpened = false;
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      final prefs = await SharedPreferences.getInstance();
      final nestId = prefs.getString('nest_id') ?? '';

      // Send a real in-app message to every other member of this nest,
      // so it actually shows up in their DM inbox -- this previously did
      // nothing at all despite the UI claiming it was sent.
      if (userId != null && nestId.isNotEmpty) {
        final memberRows = await supabase
            .from('nest_members')
            .select('user_id')
            .eq('nest_id', nestId);
        final recipientIds = (memberRows as List<dynamic>)
            .map((m) => m['user_id'] as String?)
            .whereType<String>()
            .where((id) => id != userId)
            .toSet();

        for (final recipientId in recipientIds) {
          await supabase.from('private_messages').insert({
            'nest_id': nestId,
            'sender_id': userId,
            'recipient_id': recipientId,
            'message_type': 'text',
            'content': message,
          });
        }

        // Sep 3 2026: real push alongside the in-app DM above. isEmergency
        // maps to 'sos' (always sends, ignores notify preferences -- same
        // principle as the SMS fallback below); otherwise 'check_in'
        // (respects each recipient's own notify_check_in toggle).
        PushService.notify(
          userIds: recipientIds.toList(),
          title: isEmergency ? '🚨 Emergency Alert' : "$_seniorName checked in",
          body: message,
          category: isEmergency ? 'sos' : 'check_in',
        );
      }

      // Aug 27 2026: D Von's direct ask, confirmed via earlier audit --
      // "I Need Help" was unconditionally DMing every nest member
      // regardless of emergency status, while the confirmation dialog
      // claimed emergency contacts had been notified when they never
      // actually were (only the single primary contact got a real text,
      // and only their number, not the whole configured list). Real
      // contact data (safety_contacts table) already existed, just
      // wasn't being used for genuine emergency routing.
      //
      // For a real emergency: text every configured contact that has a
      // phone number, in one native SMS composer (iOS/Android both
      // support comma-separated recipients, so this doesn't force
      // multiple app-switches). The nest-wide DM above already fires
      // unconditionally for both emergency and non-emergency cases --
      // that's fine for "I'm Okay" (a general check-in), but for a real
      // emergency it should only be the whole story if there's truly
      // nobody else to reach: no configured contacts with a real number
      // at all.
      if (isEmergency) {
        final phones = _mockContacts
            .map((c) => (c['phone'] as String?)?.trim())
            .whereType<String>()
            .where((p) => p.isNotEmpty)
            .toSet()
            .toList();
        if (phones.isNotEmpty) {
          final smsUri = Uri.parse(
            'sms:${phones.join(",")}&body=${Uri.encodeComponent(message)}',
          );
          try {
            await launchUrl(smsUri);
            smsComposerOpened = true;
          } catch (e) {
            debugPrint('SAFETY_ALERT: could not launch SMS composer: $e');
          }
        }
        // phones.isEmpty: nobody configured with a real number -- the
        // nest-wide DM sent above is the only notification that goes
        // out, which is the correct, honest fallback rather than
        // silently doing nothing.
      }
    } catch (e) {
      debugPrint('SAFETY_ALERT ERROR: $e');
    }
    setState(() => _isSendingAlert = false);

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                isEmergency
                    ? Icons.warning_rounded
                    : Icons.check_circle_rounded,
                color: isEmergency
                    ? const Color(0xFFC0392B)
                    : const Color(0xFF27AE60),
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                isEmergency ? 'Alert Sent ✓' : 'Message Sent ✓',
                style: GoogleFonts.nunitoSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
          content: Text(
            isEmergency
                ? (smsComposerOpened
                      ? 'A text to your emergency contacts is ready to send — check your Messages app to send it now. Your family has also been notified in the app.'
                      : 'No emergency contacts are set up yet, so your family has been notified in the app. Add emergency contacts on this page so a real text can go out next time.')
                : 'Your family has been notified that you\'re okay.',
            style: GoogleFonts.nunitoSans(
              fontSize: 15,
              color: _textSecondary,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'OK',
                style: GoogleFonts.nunitoSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF5DA399),
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  void _onNavTap(int index) {
    if (index == _currentNavIndex) return;
    setState(() => _currentNavIndex = index);
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/family-feed-screen');
        break;
      case 1:
        Navigator.pushReplacementNamed(context, '/send-screen');
        break;
      case 2:
        Navigator.pushReplacementNamed(context, '/legacy-screen');
        break;
      case 4:
        Navigator.pushReplacementNamed(context, '/favs-screen');
        break;
      case 5:
        Navigator.pushReplacementNamed(context, '/setup-screen');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          SafeArea(
        bottom: false,
        child: _isLoading
            ? _buildLoadingState()
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildTopBar(isTablet)),
                  if (!_isSenior)
                    SliverToBoxAdapter(
                      child: _buildFamilyReadOnlyNote(isTablet),
                    ),
                  if (_isNestArchived) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 28 : 20,
                          vertical: 10,
                        ),
                        child: _buildArchivedNestBanner(),
                      ),
                    ),
                  ] else ...[
                    if (_isSenior) ...[
                      SliverToBoxAdapter(child: _buildSOSButton(isTablet)),
                    ] else ...[
                      SliverToBoxAdapter(
                        child: _buildSOSButton(isTablet, deadButton: true),
                      ),
                    ],
                    SliverToBoxAdapter(child: _buildCheckInSection(isTablet)),
                  ],
                  if (_isSenior)
                    SliverToBoxAdapter(
                      child: _buildEmergencyContacts(isTablet),
                    ),
                  SliverToBoxAdapter(child: _buildSafetyTips(isTablet)),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
                ],
              ),
          ),
          const KeyboardDoneBarOverlay(),
        ],
      ),
      bottomNavigationBar: AppNavigation(
        currentIndex: _currentNavIndex,
        onTap: _onNavTap,
      ),
    );
  }

  Widget _buildTopBar(bool isTablet) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 28 : 20,
        vertical: 14,
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Safety',
                style: GoogleFonts.nunitoSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                ),
              ),
              Text(
                _isSenior
                    ? 'Your family is always close'
                    : 'Keep your loved one safe',
                style: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  color: _textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFC0392B).withAlpha(20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: Color(0xFFC0392B),
              size: 22,
            ),
          ),
          const SizedBox(width: 8),
          ProfileAvatarWidget(
            profileData: _profileData,
            displayName: _displayName,
            size: 40,
            borderColor: const Color(0xFF5DA399),
            borderWidth: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildSOSButton(bool isTablet, {bool deadButton = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 28 : 20,
        vertical: 8,
      ),
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, child) =>
            Transform.scale(scale: _pulseAnim.value, child: child),
        child: GestureDetector(
          onTap: deadButton
              ? null
              : (_isSendingAlert ? null : _showSOSConfirmation),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFC0392B), Color(0xFFE74C3C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFC0392B).withAlpha(80),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                _isSendingAlert
                    ? const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.sos_rounded,
                        color: Colors.white,
                        size: 44,
                      ),
                const SizedBox(height: 10),
                Text(
                  _isSendingAlert ? 'Sending Alert...' : 'I Need Help',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap to alert your family immediately',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 13,
                    color: Colors.white.withAlpha(200),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckInSection(bool isTablet) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 28 : 20,
        20,
        isTablet ? 28 : 20,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily Check-In',
            style: GoogleFonts.nunitoSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          // Sep 2 2026: real per-senior status once it's loaded -- one
          // card pair per senior, same reusable widgets Home uses. Falls
          // back to the original generic explainer for the brief window
          // before the fetch resolves, or if no senior is in the nest yet
          // (matches this screen's existing cache-then-refresh pattern).
          if (_seniorStatuses.isNotEmpty)
            Column(
              children: [
                for (final status in _seniorStatuses) ...[
                  DailyCheckinCardWidget(
                    isDarkMode: _isDarkMode,
                    isSenior: _isSenior &&
                        status['id'] ==
                            Supabase.instance.client.auth.currentUser?.id,
                    seniorName: status['name'] as String,
                    checkedIn: status['checkedIn'] as bool,
                    checkinTime: status['checkinTime'] as DateTime?,
                  ),
                  const SizedBox(height: 10),
                  DailyMedsCardWidget(
                    isDarkMode: _isDarkMode,
                    isSenior: _isSenior &&
                        status['id'] ==
                            Supabase.instance.client.auth.currentUser?.id,
                    seniorName: status['name'] as String,
                    takenToday: status['medsTaken'] as bool,
                    takenTime: status['medsTime'] as DateTime?,
                  ),
                  const SizedBox(height: 4),
                ],
              ],
            )
          else
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF5DA399).withAlpha(15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF5DA399).withAlpha(60),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF5DA399).withAlpha(26),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: Color(0xFF5DA399),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isSenior
                              ? 'Let your family know you\'re okay'
                              : 'Waiting for today\'s check-in',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isSenior
                              ? 'Tap "I\'m Good Today" on the Family Feed'
                              : 'Your loved one hasn\'t checked in yet today',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 12,
                            color: _textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Archive Nest Mode (Aug 31 2026): shown in place of the SOS button and
  // check-in section once the nest owner has archived this nest. Same
  // widget/copy as family_feed_screen.dart's version -- kept as a
  // duplicate rather than a shared widget file since each screen already
  // manages its own local dark-mode color logic independently.
  Widget _buildArchivedNestBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFD4AA00).withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFD4AA00).withAlpha(60),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.info_outline_rounded,
              color: Color(0xFFB8860B),
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This Nest is now a memorial space. Daily check-ins are turned off, but Legacy, photos, and messages are still here whenever you\'d like to visit.',
              style: GoogleFonts.nunitoSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
                color: _isDarkMode
                    ? const Color(0xFFB8A888)
                    : const Color(0xFF6B5E4E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFamilyReadOnlyNote(bool isTablet) {
    final displayName = _seniorName.isNotEmpty ? _seniorName : 'your loved one';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 28 : 20,
        16,
        isTablet ? 28 : 20,
        0,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF1A6B63),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1A6B63).withAlpha(80),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(40),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.visibility_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'This is what $displayName sees',
                style: GoogleFonts.nunitoSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactPlaceholder(String title, String subtitle, bool isTablet, {bool isPrimary = false}) {
    return GestureDetector(
      onTap: _isSenior ? () => _showAddContactSheet() : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isPrimary
              ? const Color(0xFFC0392B).withAlpha(6)
              : _cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isPrimary
                ? const Color(0xFFC0392B).withAlpha(40)
                : _cardBorder,
            width: 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isPrimary
                    ? const Color(0xFFC0392B).withAlpha(15)
                    : _cardBorder.withAlpha(80),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_add_outlined,
                color: isPrimary
                    ? const Color(0xFFC0392B).withAlpha(150)
                    : _textSecondary.withAlpha(120),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _textSecondary.withAlpha(180),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _isSenior ? subtitle : 'Not yet added',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 12,
                      color: _textSecondary.withAlpha(130),
                    ),
                  ),
                ],
              ),
            ),
            if (_isSenior)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF5DA399).withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF5DA399).withAlpha(60)),
                ),
                child: Text(
                  '+ Add',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF5DA399),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyContacts(bool isTablet) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 28 : 20,
        24,
        isTablet ? 28 : 20,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Emergency Contacts',
                style: GoogleFonts.nunitoSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const Spacer(),
              if (_isSenior)
                GestureDetector(
                  onTap: () => _showAddContactSheet(),
                  child: Text(
                    '+ Add',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF5DA399),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_mockContacts.isEmpty) ...[
            _buildContactPlaceholder('Emergency Contact 1', '(e.g. Son, Daughter)', isTablet),
            _buildContactPlaceholder('Emergency Contact 2', '(e.g. Spouse, Sibling)', isTablet),
            _buildContactPlaceholder('Emergency Contact 3', '(e.g. Niece, Friend)', isTablet),
          ],
          ..._mockContacts.asMap().entries.map((entry) {
            final index = entry.key;
            final contact = entry.value;
            final anim = index < _itemAnimations.length
                ? _itemAnimations[index + 2]
                : const AlwaysStoppedAnimation(1.0);
            final hasAvatar = (contact['avatar'] as String? ?? '').isNotEmpty;
            return AnimatedBuilder(
              animation: anim,
              builder: (context, child) => Opacity(
                opacity: anim.value,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - anim.value)),
                  child: child,
                ),
              ),
              child: GestureDetector(
                onTap: () => _showEditContactSheet(contact),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: contact['isPrimary'] as bool
                        ? const Color(0xFFC0392B).withAlpha(10)
                        : _cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: contact['isPrimary'] as bool
                          ? const Color(0xFFC0392B).withAlpha(60)
                          : _cardBorder,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      hasAvatar
                          ? CircleAvatar(
                              radius: 22,
                              backgroundImage: NetworkImage(
                                contact['avatar'] as String,
                              ),
                              backgroundColor: _surface,
                            )
                          : CircleAvatar(
                              radius: 22,
                              backgroundColor: const Color(
                                0xFF5DA399,
                              ).withAlpha(26),
                              child: const Icon(
                                Icons.local_hospital_rounded,
                                color: Color(0xFF5DA399),
                                size: 20,
                              ),
                            ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  contact['name'] as String,
                                  style: GoogleFonts.nunitoSans(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _textPrimary,
                                  ),
                                ),
                                if (contact['isPrimary'] as bool) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFC0392B,
                                      ).withAlpha(20),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Primary',
                                      style: GoogleFonts.nunitoSans(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFFC0392B),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              contact['phone'] as String,
                              style: GoogleFonts.nunitoSans(
                                fontSize: 13,
                                color: _textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _showEditContactSheet(contact),
                        child: Container(
                          width: 36,
                          height: 36,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: _textSecondary.withAlpha(20),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.edit_rounded,
                            color: _textSecondary,
                            size: 16,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () async {
                          final rawPhone = contact['phone'] as String? ?? '';
                          final digitsOnly = rawPhone.replaceAll(RegExp(r'[^\d+]'), '');
                          if (digitsOnly.isEmpty) return;
                          final telUri = Uri(scheme: 'tel', path: digitsOnly);
                          try {
                            await launchUrl(telUri);
                          } catch (e) {
                            debugPrint('EMERGENCY_CALL_ERROR: $e');
                          }
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF5DA399).withAlpha(20),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.phone_rounded,
                            color: Color(0xFF5DA399),
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSafetyTips(bool isTablet) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isTablet ? 28 : 20,
        24,
        isTablet ? 28 : 20,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_rounded,
                color: Color(0xFFD4AA00),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Safety Tips',
                style: GoogleFonts.nunitoSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._safetyTips.asMap().entries.map((entry) {
            final index = entry.key;
            final tip = entry.value;
            final anim = index < _itemAnimations.length
                ? _itemAnimations[index + _mockContacts.length + 2]
                : const AlwaysStoppedAnimation(1.0);
            return AnimatedBuilder(
              animation: anim,
              builder: (context, child) =>
                  Opacity(opacity: anim.value, child: child),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _cardBorder, width: 1.5),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tip['icon']!, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tip['title']!,
                            style: GoogleFonts.nunitoSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tip['tip']!,
                            style: GoogleFonts.nunitoSans(
                              fontSize: 13,
                              color: _textSecondary,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 5,
      itemBuilder: (context, index) => Container(
        height: index == 0 ? 120 : 80,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  void _showAddContactSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddContactSheet(isDarkMode: _isDarkMode),
    ).then((_) { if (mounted) _loadData(); });
  }

  void _showEditContactSheet(Map<String, dynamic> contact) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) =>
          _EditContactSheet(isDarkMode: _isDarkMode, contact: contact),
    ).then((_) { if (mounted) _loadData(); });
  }
}

class _AddContactSheet extends StatefulWidget {
  const _AddContactSheet({required this.isDarkMode});
  final bool isDarkMode;

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  bool _isPrimary = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _nameFocusNode.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  Color get _bg =>
      widget.isDarkMode ? const Color(0xFF242018) : const Color(0xFFFDFDFD);
  Color get _textPrimary =>
      widget.isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      widget.isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  Future<void> _saveContact() async {
    if (_nameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty) {
      return;
    }
    // The actual call button just strips non-digits and hands whatever's
    // left straight to the phone dialer with no safeguard -- a 7-digit
    // number with no area code will very likely fail to connect on most
    // phones today, since nearly all US areas require 10-digit dialing
    // now. Catch that here instead, before it's ever saved.
    final digitCount =
        _phoneController.text.replaceAll(RegExp(r'[^\d]'), '').length;
    if (digitCount < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please include the area code (10 digits).'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final supabase = Supabase.instance.client;
      String? userId = supabase.auth.currentUser?.id;
      // Fallback: get userId from session if currentUser is null
      if (userId == null) {
        final session = supabase.auth.currentSession;
        userId = session?.user.id;
        print('SAFETY_CONTACT: userId from session = $userId');
      }
      print('SAFETY_CONTACT: userId = $userId');
      if (userId != null) {
        // The "Set as primary contact" toggle used to be pure decoration --
        // this insert always hardcoded is_primary: false regardless of the
        // switch. Now: if this new contact is being set primary, clear
        // primary off every other existing contact first, so exactly one
        // contact is ever primary at a time (matches the single red-styled
        // "Primary" slot the UI actually renders).
        if (_isPrimary) {
          await supabase
              .from('safety_contacts')
              .update({'is_primary': false})
              .eq('user_id', userId);
        }
        await supabase.from('safety_contacts').insert({
          'user_id': userId,
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'is_primary': _isPrimary,
        });
        print('SAFETY_CONTACT: inserted successfully');
        if (mounted) setState(() => _isSaving = false);
      } else {
        print('SAFETY_CONTACT: userId is null - cannot save');
        if (mounted) setState(() => _isSaving = false);
      }
    } catch (e) {
      print('SAFETY_CONTACT ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving contact: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isSaving = false);
        return;
      }
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    // Wrapped in its own Scaffold so ScaffoldMessenger.of(context) inside
    // _saveContact() finds THIS sheet's messenger instead of bubbling past
    // it to the page underneath -- without this, showModalBottomSheet has
    // no local Scaffold ancestor, so the "include area code" SnackBar was
    // rendering anchored to the screen behind the sheet, appearing to sit
    // behind/below it instead of on top where it's actually visible.
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: KeyboardDoneBar(
        alreadyPaddedForKeyboard: true,
        child: GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + bottomPadding,
      ),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE8E0D0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Add Emergency Contact',
            style: GoogleFonts.nunitoSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            focusNode: _nameFocusNode,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).requestFocus(_phoneFocusNode),
            style: GoogleFonts.nunitoSans(fontSize: 16, color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Name',
              labelStyle: GoogleFonts.nunitoSans(
                fontSize: 13,
                color: _textSecondary,
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFE8E0D0), width: 1.5),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF5DA399), width: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneController,
            focusNode: _phoneFocusNode,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            style: GoogleFonts.nunitoSans(fontSize: 16, color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Phone number',
              // Nothing previously showed the expected 10-digit format
              // before someone started typing -- the field just looked
              // blank. This surfaces the area-code requirement up front
              // instead of only after a failed save.
              hintText: '(555) 123-4567',
              hintStyle: GoogleFonts.nunitoSans(
                fontSize: 16,
                color: _textSecondary.withOpacity(0.5),
              ),
              labelStyle: GoogleFonts.nunitoSans(
                fontSize: 13,
                color: _textSecondary,
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFE8E0D0), width: 1.5),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF5DA399), width: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Set as primary contact',
                style: GoogleFonts.nunitoSans(
                  fontSize: 15,
                  color: _textPrimary,
                ),
              ),
              const Spacer(),
              Switch(
                value: _isPrimary,
                onChanged: (v) => setState(() => _isPrimary = v),
                activeThumbColor: const Color(0xFF5DA399),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveContact,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5DA399),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Save Contact',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
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
}

class _EditContactSheet extends StatefulWidget {
  const _EditContactSheet({required this.isDarkMode, required this.contact});
  final bool isDarkMode;
  final Map<String, dynamic> contact;

  @override
  State<_EditContactSheet> createState() => _EditContactSheetState();
}

class _EditContactSheetState extends State<_EditContactSheet> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  late bool _isPrimary;
  bool _isSaving = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.contact['name'] as String? ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.contact['phone'] as String? ?? '',
    );
    _isPrimary = widget.contact['isPrimary'] as bool? ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _nameFocusNode.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  Color get _bg =>
      widget.isDarkMode ? const Color(0xFF242018) : const Color(0xFFFDFDFD);
  Color get _textPrimary =>
      widget.isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      widget.isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  Future<void> _saveContact() async {
    if (_nameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty) {
      return;
    }
    final digitCount =
        _phoneController.text.replaceAll(RegExp(r'[^\d]'), '').length;
    if (digitCount < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please include the area code (10 digits).'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    bool succeeded = true;
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      final contactId = widget.contact['id'];
      if (contactId != null && userId != null) {
        // Same missing piece as the add-contact dialog: this update never
        // included is_primary at all, so the toggle did nothing here
        // either. Clear primary off every other contact first if this one
        // is being set primary, same single-primary rule as add.
        if (_isPrimary) {
          await supabase
              .from('safety_contacts')
              .update({'is_primary': false})
              .eq('user_id', userId)
              .neq('id', contactId);
        }
        await supabase.from('safety_contacts').update({
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'is_primary': _isPrimary,
        }).eq('id', contactId);
      }
    } catch (e) {
      debugPrint('Update contact error: $e');
      succeeded = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error saving contact: $e'),
              backgroundColor: Colors.red),
        );
        setState(() => _isSaving = false);
      }
    }
    if (mounted && succeeded) {
      Navigator.pop(context);
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Remove Contact?',
          style: GoogleFonts.nunitoSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to remove ${_nameController.text.trim()} from your emergency contacts?',
          style: GoogleFonts.nunitoSans(
            fontSize: 14,
            color: _textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                color: _textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isDeleting = true);
              try {
                final supabase = Supabase.instance.client;
                final contactId = widget.contact['id'];
                if (contactId != null) {
                  await supabase.from('safety_contacts')
                      .delete()
                      .eq('id', contactId);
                }
              } catch (e) {
                debugPrint('Delete contact error: $e');
              }
              if (mounted) {
                Navigator.pop(context);
              }
            },
            child: Text(
              'Remove',
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFC0392B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    // Same fix as _AddContactSheet above: wrapped in its own Scaffold so
    // ScaffoldMessenger.of(context) finds THIS sheet's messenger instead of
    // bubbling past it to the page underneath, which was rendering the
    // "include area code" SnackBar behind the sheet instead of on top of it.
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: KeyboardDoneBar(
        alreadyPaddedForKeyboard: true,
        child: GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + bottomPadding,
      ),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE8E0D0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                'Edit Emergency Contact',
                style: GoogleFonts.nunitoSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: (_isSaving || _isDeleting) ? null : _confirmDelete,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC0392B).withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _isDeleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFC0392B),
                          ),
                        )
                      : Text(
                          'Delete',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFC0392B),
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            focusNode: _nameFocusNode,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).requestFocus(_phoneFocusNode),
            style: GoogleFonts.nunitoSans(fontSize: 16, color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Name',
              labelStyle: GoogleFonts.nunitoSans(
                fontSize: 13,
                color: _textSecondary,
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFE8E0D0), width: 1.5),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF5DA399), width: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneController,
            focusNode: _phoneFocusNode,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            style: GoogleFonts.nunitoSans(fontSize: 16, color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Phone number',
              // Nothing previously showed the expected 10-digit format
              // before someone started typing -- the field just looked
              // blank. This surfaces the area-code requirement up front
              // instead of only after a failed save.
              hintText: '(555) 123-4567',
              hintStyle: GoogleFonts.nunitoSans(
                fontSize: 16,
                color: _textSecondary.withOpacity(0.5),
              ),
              labelStyle: GoogleFonts.nunitoSans(
                fontSize: 13,
                color: _textSecondary,
              ),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFE8E0D0), width: 1.5),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF5DA399), width: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Set as primary contact',
                style: GoogleFonts.nunitoSans(
                  fontSize: 15,
                  color: _textPrimary,
                ),
              ),
              const Spacer(),
              Switch(
                value: _isPrimary,
                onChanged: (v) => setState(() => _isPrimary = v),
                activeThumbColor: const Color(0xFF5DA399),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: (_isSaving || _isDeleting) ? null : _saveContact,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5DA399),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Save Changes',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              onPressed: (_isSaving || _isDeleting)
                  ? null
                  : () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: GoogleFonts.nunitoSans(
                  fontSize: 15,
                  color: _textSecondary,
                ),
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
}
