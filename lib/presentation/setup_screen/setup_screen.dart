import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_state.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/share_service.dart';
import '../../widgets/app_navigation.dart';
import '../profile_photo_picker_screen/profile_photo_picker_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen>
    with TickerProviderStateMixin {
  int _currentNavIndex = 5;
  bool _isSenior = appIsSeniorNotifier.value;
  // Seeded from the already-resolved app-wide notifier instead of a
  // hardcoded false -- see messages_inbox_screen.dart for the full
  // explanation of the white-flash bug this fixes.
  bool _isDarkMode = appDarkModeNotifier.value;
  bool _isLoading = true;
  bool _isNestOwner = appIsNestOwnerNotifier.value;
  bool _isNestArchived = false; // Aug 31 2026: Archive Nest Mode -- owner-only toggle, see _buildNestOwnershipSection
  bool _isVipMember = appIsVipMemberNotifier.value;
  String _displayName = appDisplayNameNotifier.value;
  String _preferredName = '';
  // If a preferred name has been set, show that everywhere; otherwise fall back to first name.
  String get _effectiveName =>
      _preferredName.trim().isNotEmpty ? _preferredName.trim() : _displayName;
  // Seeded from the already-resolved app-wide notifier instead of an
  // empty default -- see appNestNameNotifier in app_state.dart and the
  // matching fix in family_feed_screen.dart.
  String _nestName = appNestNameNotifier.value;
  String _relationship = '';
  bool _medsReminders = true;
  bool _dailyCheckIn = true;
  bool _notifyMessages = true;
  bool _notifyCheckIn = true;
  String _textSize = 'Large';
  bool _isGuest = appIsGuestNotifier.value;
  String _inviteCode = '';
  // Aug 27 2026: Nest Succession feature -- see _loadSuccessionStatus.
  Map<String, dynamic>? _nestOwnerProfile;
  Map<String, dynamic>? _pendingSuccessionRequest;
  List<Map<String, dynamic>> _successionObjections = [];
  String? _justBecameOwnerRequestId;
  bool _successionActionLoading = false;
  Map<String, dynamic>? _profileData;
  DateTime? _birthday;
  DateTime? _anniversary;

  // Family members list — populated when real members join via Supabase
  List<Map<String, dynamic>> _familyMembers = [];

  late AnimationController _entranceController;
  late List<Animation<double>> _itemAnimations;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _itemAnimations = [];
    _loadData();
    _loadSuccessionStatus();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? 'senior';
    final isSenior = role == 'senior';
    final joinedViaInvite = prefs.getBool('joined_via_invite') ?? false;
    // Aug 25 2026: was always recomputing this from the joined_via_invite
    // shortcut, even when a reliable, previously-confirmed value already
    // existed in cache -- overwriting the correct value the field was
    // already seeded with (from appIsNestOwnerNotifier) with a worse
    // guess, then a live Supabase check further down would correct it
    // back a moment later. That round trip (correct -> wrong -> correct)
    // was the Setup screen's own flash D Von reported (Aug 25). Now
    // prefers the same persisted cached_is_nest_owner value main.dart
    // already trusts, only falling back to the rough proxy when that
    // cache has genuinely never been set (a true first-ever resolve).
    final cachedIsNestOwner = prefs.getBool('cached_is_nest_owner');
    bool isNestOwner = cachedIsNestOwner ?? !joinedViaInvite;
    final defaultSize = isSenior ? 'Large' : 'Normal';

    String savedName = prefs.getString('display_name') ?? '';
    String savedPreferredName = prefs.getString('preferred_name') ?? '';

    final hasRealPost = prefs.getBool('has_real_post') ?? false;
    final inviteCodeShared = prefs.getBool('invite_code_shared') ?? false;
    final isGuest = prefs.getBool('is_guest') ?? false;
    final removedIds = prefs.getStringList('removed_member_ids') ?? [];

    final profileJson = prefs.getString(kProfilePhotoKey);
    Map<String, dynamic>? profileData;
    if (profileJson != null) {
      try {
        profileData = jsonDecode(profileJson) as Map<String, dynamic>;
      } catch (_) {}
    }

    DateTime? birthday;
    DateTime? anniversary;
    final birthdayStr = prefs.getString('birthday');
    final anniversaryStr = prefs.getString('anniversary');
    if (birthdayStr != null) {
      try {
        birthday = DateTime.parse(birthdayStr);
      } catch (_) {}
    }
    if (anniversaryStr != null) {
      try {
        anniversary = DateTime.parse(anniversaryStr);
      } catch (_) {}
    }

    // Cache-first: show the last-loaded family member list instantly (same
    // pattern as Home's nest members cache), then refresh from Supabase
    // quietly in the background. Previously this screen had no cache and
    // an unconditional 300ms delay before even starting FOUR sequential
    // network round-trips (nest info, birthday/name, VIP check) with
    // nothing on screen the whole time. Removed the delay; added the
    // cache for the one real content list (family members) -- everything
    // else here already had a local-prefs fallback baked in.
    final currentUserIdForCache = Supabase.instance.client.auth.currentUser?.id ?? '';
    final nestIdForCache = prefs.getString('nest_id') ?? '';
    final cachedFamilyNestId = prefs.getString('cached_setup_family_nest_id') ?? '';
    final cachedFamilyUserId = prefs.getString('cached_setup_family_user_id') ?? '';
    List<Map<String, dynamic>> initialFamilyMembers = [];
    if (cachedFamilyNestId.isNotEmpty &&
        cachedFamilyNestId == nestIdForCache &&
        cachedFamilyUserId.isNotEmpty &&
        cachedFamilyUserId == currentUserIdForCache) {
      final cachedFamilyJson = prefs.getString('cached_setup_family_members');
      if (cachedFamilyJson != null && cachedFamilyJson.isNotEmpty) {
        try {
          final List<dynamic> cachedList = jsonDecode(cachedFamilyJson) as List<dynamic>;
          initialFamilyMembers = cachedList.map((m) => Map<String, dynamic>.from(m as Map)).toList();
          if (removedIds.isNotEmpty) {
            initialFamilyMembers = initialFamilyMembers
                .where((m) => !removedIds.contains(m['id'] as String))
                .toList();
          }
        } catch (_) {}
      }
    }
    final initialIsVip = prefs.getBool('cached_is_vip_member') ?? false;

    setState(() {
      _isSenior = isSenior;
      _isNestOwner = isNestOwner;
      _isVipMember = initialIsVip;
      _displayName = savedName;
      _preferredName = savedPreferredName;
      _nestName = prefs.getString('nest_name') ?? 'Your Nest';
      _relationship = prefs.getString('relationship') ?? '';
      _isDarkMode = prefs.getBool('dark_mode') ?? false;
      _medsReminders = prefs.getBool('meds_reminders') ?? true;
      _dailyCheckIn = prefs.getBool('daily_check_in') ?? true;
      _notifyMessages = prefs.getBool('notify_messages') ?? true;
      _notifyCheckIn = prefs.getBool('notify_check_in') ?? true;
      _textSize = prefs.getString('text_size') ?? defaultSize;
      _isGuest = prefs.getBool('is_guest') ?? false;
      _isLoading = false;
      _profileData = profileData;
      _birthday = birthday;
      _anniversary = anniversary;
      _inviteCode = prefs.getString('invite_code') ?? '';
      _familyMembers = initialFamilyMembers;
    });
    // See the matching comment in family_feed_screen.dart -- appIsSeniorNotifier
    // only re-resolves at true cold-start, so an in-session account switch
    // needs this screen's own fresh cache read to correct the shared
    // notifier too.
    appIsSeniorNotifier.value = isSenior;
    appDisplayNameNotifier.value = savedName;
    _setupAnimations();
    _entranceController.forward();

    // From here down: the same three network blocks this screen always
    // had, unchanged in logic, just each doing its own quiet follow-up
    // setState as it completes instead of all accumulating into local
    // variables for one big setState at the very end.

    if (savedName.isEmpty) {
      try {
        final user = Supabase.instance.client.auth.currentUser;
        final metaName =
            user?.userMetadata?['display_name'] as String? ??
            user?.userMetadata?['full_name'] as String? ??
            user?.userMetadata?['name'] as String? ??
            '';
        if (metaName.isNotEmpty) {
          savedName = metaName;
          await prefs.setString('display_name', savedName);
          if (mounted) {
            setState(() => _displayName = savedName);
            appDisplayNameNotifier.value = savedName;
          }
        }
      } catch (_) {}
    }

    // Family Members was previously always an empty list -- nothing ever
    // populated it from real data, so it silently showed "0 members" no
    // matter how many people had actually joined the nest.
    List<Map<String, dynamic>> realFamilyMembers = [];
    // Nest name was previously local-storage-only, so a rename on one
    // device/flow was invisible to every other flow sharing the same nest.
    // Now sourced live from Supabase, with local cache only as an
    // offline/loading-moment fallback.
    String? fetchedNestName;
    // Invite code had this exact same bug, and it's the more serious one:
    // this screen was showing whatever invite_code happened to be cached
    // locally, with no connection at all to this nest's real, current
    // invite_code in the database. Confirmed directly against the DB: an
    // owner's Setup screen was displaying a completely different nest's
    // invite code (one that, unbeknownst to her, had ended up cached
    // locally from an earlier, unrelated interaction) -- meaning she
    // unknowingly shared the WRONG code, and the person who used it
    // joined a stranger's nest instead of hers. Fetched live here, same
    // as the name just above, from the exact same nest row.
    String? fetchedInviteCode;
    try {
      final supabase = Supabase.instance.client;
      final currentUserId = supabase.auth.currentUser?.id;
      final nestId = prefs.getString('nest_id') ?? '';
      if (nestId.isNotEmpty) {
        try {
          final nestRow = await supabase
              .from('nests')
              .select('name, created_by, invite_code')
              .eq('id', nestId)
              .maybeSingle();
          final remoteName = nestRow?['name'] as String?;
          if (remoteName != null && remoteName.isNotEmpty) {
            fetchedNestName = remoteName;
            await prefs.setString('nest_name', remoteName);
            // Keep the shared notifier in sync too, so every other screen
            // that reads it picks up a real rename immediately.
            appNestNameNotifier.value = remoteName;
          }
          final remoteInviteCode = nestRow?['invite_code'] as String?;
          if (remoteInviteCode != null && remoteInviteCode.isNotEmpty) {
            fetchedInviteCode = remoteInviteCode;
            await prefs.setString('invite_code', remoteInviteCode);
          }
          // Real ownership check. Previously "am I the nest owner" was
          // derived only from a local "joined via invite" flag -- fragile
          // in the same way as everything else fixed today, and it was
          // silently showing the actual nest creator as a plain "Member",
          // which also meant the Remove Member button (gated on this same
          // flag) never worked for them even though the DB-level fix was
          // in place.
          final realCreatedBy = nestRow?['created_by'] as String?;
          if (realCreatedBy != null && currentUserId != null) {
            isNestOwner = realCreatedBy == currentUserId;
          }
        } catch (e) {
          debugPrint('NEST_NAME_LOAD_ERROR: $e');
        }
      }
      if (currentUserId != null && nestId.isNotEmpty) {
        final memberRows = await supabase
            .from('nest_members')
            .select('user_id, user_profiles(display_name, preferred_name, avatar_url, relation_type, role)')
            .eq('nest_id', nestId);
        for (final row in (memberRows as List<dynamic>)) {
          final memberUserId = row['user_id'] as String?;
          if (memberUserId == null || memberUserId == currentUserId) continue;
          final profile = row['user_profiles'] as Map<String, dynamic>?;
          if (profile == null) continue;
          final preferred = profile['preferred_name'] as String? ?? '';
          final display = profile['display_name'] as String? ?? '';
          final memberName = preferred.isNotEmpty ? preferred : (display.isNotEmpty ? display : 'Family member');
          final relationType = profile['relation_type'] as String? ?? '';
          final memberRole = profile['role'] as String? ?? '';
          final relationshipLabel = relationType.isNotEmpty
              ? (relationType[0].toUpperCase() + relationType.substring(1))
              : (memberRole == 'senior' ? 'Senior' : 'Family');
          final initials = memberName.trim().isNotEmpty ? memberName.trim()[0].toUpperCase() : '?';
          final avatarUrl = profile['avatar_url'] as String? ?? '';
          realFamilyMembers.add({
            'id': memberUserId,
            'name': memberName,
            'relationship': relationshipLabel,
            'initials': initials,
            'avatarUrl': avatarUrl,
          });
        }
      }
      if (removedIds.isNotEmpty) {
        realFamilyMembers = realFamilyMembers
            .where((m) => !removedIds.contains(m['id'] as String))
            .toList();
      }
      if (mounted) {
        setState(() {
          if (fetchedNestName != null) _nestName = fetchedNestName;
          if (fetchedInviteCode != null) _inviteCode = fetchedInviteCode;
          _isNestOwner = isNestOwner;
          _familyMembers = realFamilyMembers;
        });
        // Update the shared notifier too, so any other screen currently
        // showing this value (e.g. family_feed_screen's own role-gated UI)
        // picks up the confirmed answer immediately, and persist it so the
        // next app launch starts from this confirmed value instead of the
        // instant joined-via-invite guess.
        appIsNestOwnerNotifier.value = isNestOwner;
        await prefs.setBool('cached_is_nest_owner', isNestOwner);
        _setupAnimations();
        if (currentUserId != null && nestId.isNotEmpty) {
          await prefs.setString('cached_setup_family_members', jsonEncode(realFamilyMembers));
          await prefs.setString('cached_setup_family_nest_id', nestId);
          await prefs.setString('cached_setup_family_user_id', currentUserId);
        }
      }
    } catch (e) {
      print('FAMILY_MEMBERS_LOAD_ERROR: $e');
    }

    // Saving a birthday/anniversary already wrote to Supabase, but loading
    // this screen only ever checked local storage. That meant the real
    // data was safe in the database (which is why Home's Celebrations kept
    // showing it correctly), but Setup's own display would silently go
    // blank any time local storage got cleared -- reinstall, sign-out,
    // new device -- even though nothing was actually lost. Now sourced
    // live from Supabase on load, re-caching locally to stay in sync.
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        final profileRow = await Supabase.instance.client
            .from('user_profiles')
            .select('birthday, anniversary, display_name, preferred_name')
            .eq('id', userId)
            .maybeSingle();
        final remoteBirthday = profileRow?['birthday'] as String?;
        final remoteAnniversary = profileRow?['anniversary'] as String?;
        final remoteDisplayName = profileRow?['display_name'] as String?;
        final remotePreferredName = profileRow?['preferred_name'] as String?;
        DateTime? updatedBirthday;
        DateTime? updatedAnniversary;
        if (remoteBirthday != null && remoteBirthday.isNotEmpty) {
          try {
            updatedBirthday = DateTime.parse(remoteBirthday);
            await prefs.setString('birthday', remoteBirthday);
          } catch (_) {}
        }
        if (remoteAnniversary != null && remoteAnniversary.isNotEmpty) {
          try {
            updatedAnniversary = DateTime.parse(remoteAnniversary);
            await prefs.setString('anniversary', remoteAnniversary);
          } catch (_) {}
        }
        // Same local-only-load bug as birthday/anniversary: saving a name
        // change already reached Supabase, but loading here only checked
        // local storage, with just a weak fallback to the original
        // sign-up name. Now sourced live, same as birthday/anniversary.
        if (remoteDisplayName != null && remoteDisplayName.isNotEmpty) {
          savedName = remoteDisplayName;
          await prefs.setString('display_name', remoteDisplayName);
        }
        if (remotePreferredName != null && remotePreferredName.isNotEmpty) {
          savedPreferredName = remotePreferredName;
          await prefs.setString('preferred_name', remotePreferredName);
        }
        if (mounted) {
          setState(() {
            if (updatedBirthday != null) _birthday = updatedBirthday;
            if (updatedAnniversary != null) _anniversary = updatedAnniversary;
            _displayName = savedName;
            _preferredName = savedPreferredName;
          });
          appDisplayNameNotifier.value = savedName;
        }
      }
    } catch (e) {
      debugPrint('BIRTHDAY_ANNIVERSARY_LOAD_ERROR: $e');
    }

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        final result = await Supabase.instance.client
            .rpc('is_vip_member', params: {'p_user_id': userId});
        final isVip = result == true;
        if (mounted) {
          setState(() => _isVipMember = isVip);
        }
        appIsVipMemberNotifier.value = isVip;
        await prefs.setBool('cached_is_vip_member', isVip);
      }
    } catch (e) {
      debugPrint('VIP_CHECK_ERROR: $e');
    }
  }

  // ── Nest Succession ─────────────────────────────────────────────
  // Aug 27 2026: real feature build, scoped and agreed with D Von across
  // several rounds of discussion. Deliberately never asks "why" someone's
  // unreachable (death, missed payment, hospital, anything else) -- it
  // only ever asks "is the current owner responding." See the RPC
  // functions in Supabase for the actual business rules; this just reads
  // and displays their result and calls them.
  Future<void> _loadSuccessionStatus() async {
    try {
      final supabase = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();
      final nestId = prefs.getString('nest_id') ?? '';
      if (nestId.isEmpty) return;

      // Safe to call from anyone -- only ever touches rows objectively
      // past their own deadline, nothing scoped to the calling user.
      try {
        await supabase.rpc('resolve_expired_succession_requests');
      } catch (_) {}

      final nest = await supabase
          .from('nests')
          .select('created_by, is_archived')
          .eq('id', nestId)
          .maybeSingle();
      final ownerId = nest?['created_by'] as String?;
      final isArchived = nest?['is_archived'] as bool? ?? false;

      Map<String, dynamic>? ownerProfile;
      if (ownerId != null) {
        final p = await supabase
            .from('user_profiles')
            .select('id, display_name, preferred_name')
            .eq('id', ownerId)
            .maybeSingle();
        if (p != null) {
          final preferred = (p['preferred_name'] as String?) ?? '';
          final display = (p['display_name'] as String?) ?? '';
          ownerProfile = {
            'id': ownerId,
            'name': preferred.isNotEmpty ? preferred : (display.isNotEmpty ? display : 'the owner'),
          };
        }
      }

      final pending = await supabase
          .from('nest_succession_requests')
          .select('id, requested_by, deadline, status')
          .eq('nest_id', nestId)
          .eq('status', 'pending')
          .maybeSingle();

      Map<String, dynamic>? pendingWithName;
      List<Map<String, dynamic>> objections = [];
      if (pending != null) {
        final requesterId = pending['requested_by'] as String;
        final rp = await supabase
            .from('user_profiles')
            .select('display_name, preferred_name')
            .eq('id', requesterId)
            .maybeSingle();
        final preferred = (rp?['preferred_name'] as String?) ?? '';
        final display = (rp?['display_name'] as String?) ?? '';
        pendingWithName = {
          ...pending,
          'requester_name': preferred.isNotEmpty ? preferred : (display.isNotEmpty ? display : 'A family member'),
        };

        final objRows = await supabase
            .from('nest_succession_objections')
            .select('objected_by')
            .eq('request_id', pending['id']);
        objections = (objRows as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
      }

      // One-time "you're the new owner" prompt -- only shown if the
      // person hasn't already dismissed it (per-request ack flag) and
      // they're genuinely the current owner now, not stale info from an
      // older resolved request.
      final myUserId = supabase.auth.currentUser?.id;
      String? justResolvedId;
      if (myUserId != null && ownerId == myUserId) {
        final resolved = await supabase
            .from('nest_succession_requests')
            .select('id, resolved_at')
            .eq('nest_id', nestId)
            .eq('requested_by', myUserId)
            .inFilter('status', ['approved', 'auto_transferred'])
            .order('resolved_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (resolved != null) {
          final ackKey = 'succession_ack_${resolved['id']}';
          final alreadyAcked = prefs.getBool(ackKey) ?? false;
          if (!alreadyAcked) justResolvedId = resolved['id'] as String;
        }
      }

      if (mounted) {
        setState(() {
          _nestOwnerProfile = ownerProfile;
          _pendingSuccessionRequest = pendingWithName;
          _successionObjections = objections;
          _justBecameOwnerRequestId = justResolvedId;
          _isNestArchived = isArchived;
        });
      }
    } catch (e) {
      debugPrint('SUCCESSION_LOAD_ERROR: $e');
    }
  }

  void _showSuccessionError(Object e) {
    if (!mounted) return;
    final message = e.toString().contains('Exception:')
        ? e.toString().split('Exception:').last.trim()
        : 'Something went wrong. Please try again.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.nunitoSans(fontSize: 14, color: Colors.white),
        ),
        backgroundColor: const Color(0xFFC97B4A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showSuccessionSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.nunitoSans(fontSize: 14, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF5DA399),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _confirmRequestOwnership() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Request Nest Ownership?',
          style: GoogleFonts.nunitoSans(fontSize: 20, fontWeight: FontWeight.w700, color: _textPrimary),
        ),
        content: Text(
          'Everyone in the nest will be notified. The current owner can approve or deny it directly; if they don\'t respond within 7 days and nobody objects, ownership transfers automatically.',
          style: GoogleFonts.nunitoSans(fontSize: 15, color: _textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.nunitoSans(fontSize: 15, color: _textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _requestNestOwnership();
            },
            child: Text(
              'Send Request',
              style: GoogleFonts.nunitoSans(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF5DA399)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _requestNestOwnership() async {
    setState(() => _successionActionLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final nestId = prefs.getString('nest_id') ?? '';
      await Supabase.instance.client.rpc(
        'create_succession_request',
        params: {'p_nest_id': nestId},
      );
      await _loadSuccessionStatus();
      _showSuccessionSuccess('Request sent — everyone in the nest has been notified.');
    } catch (e) {
      _showSuccessionError(e);
    } finally {
      if (mounted) setState(() => _successionActionLoading = false);
    }
  }

  void _confirmApprove(String requestId, String requesterName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Make $requesterName the Nest Owner?',
          style: GoogleFonts.nunitoSans(fontSize: 20, fontWeight: FontWeight.w700, color: _textPrimary),
        ),
        content: Text(
          'This happens immediately. You will no longer be the Nest Owner.',
          style: GoogleFonts.nunitoSans(fontSize: 15, color: _textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.nunitoSans(fontSize: 15, color: _textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _approveSuccession(requestId);
            },
            child: Text(
              'Approve',
              style: GoogleFonts.nunitoSans(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF5DA399)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _approveSuccession(String requestId) async {
    setState(() => _successionActionLoading = true);
    try {
      await Supabase.instance.client.rpc(
        'approve_succession_request',
        params: {'p_request_id': requestId},
      );
      // The approving user is the OUTGOING owner -- reflect that locally
      // right away rather than waiting for the next cold start.
      appIsNestOwnerNotifier.value = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('cached_is_nest_owner', false);
      if (mounted) setState(() => _isNestOwner = false);
      await _loadSuccessionStatus();
      _showSuccessionSuccess('Ownership transferred.');
    } catch (e) {
      _showSuccessionError(e);
    } finally {
      if (mounted) setState(() => _successionActionLoading = false);
    }
  }

  Future<void> _denySuccession(String requestId) async {
    setState(() => _successionActionLoading = true);
    try {
      await Supabase.instance.client.rpc(
        'deny_succession_request',
        params: {'p_request_id': requestId},
      );
      await _loadSuccessionStatus();
      _showSuccessionSuccess('Request denied.');
    } catch (e) {
      _showSuccessionError(e);
    } finally {
      if (mounted) setState(() => _successionActionLoading = false);
    }
  }

  Future<void> _objectToSuccession(String requestId) async {
    setState(() => _successionActionLoading = true);
    try {
      await Supabase.instance.client.rpc(
        'object_to_succession_request',
        params: {'p_request_id': requestId},
      );
      await _loadSuccessionStatus();
      _showSuccessionSuccess('Your objection has been recorded.');
    } catch (e) {
      _showSuccessionError(e);
    } finally {
      if (mounted) setState(() => _successionActionLoading = false);
    }
  }

  Future<void> _dismissNewOwnerBanner() async {
    final requestId = _justBecameOwnerRequestId;
    if (requestId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('succession_ack_$requestId', true);
    if (mounted) setState(() => _justBecameOwnerRequestId = null);
  }

  Widget _buildNewOwnerBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFD4AA00).withAlpha(20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4AA00), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You\'re now the Nest Owner',
            style: GoogleFonts.nunitoSans(fontSize: 15, fontWeight: FontWeight.w700, color: _textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'Subscribe to keep everything active for the whole family.',
            style: GoogleFonts.nunitoSans(fontSize: 13, color: _textSecondary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pushNamed(context, AppRoutes.subscribeNestScreen),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AA00),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Subscribe Now', style: GoogleFonts.nunitoSans(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _dismissNewOwnerBanner,
                child: Text('Later', style: GoogleFonts.nunitoSans(fontSize: 14, color: _textSecondary)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoPendingSuccessionCard(bool iAmOwner, String ownerName) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded, color: Color(0xFF5DA399), size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  iAmOwner ? 'You are the Nest Owner' : '$ownerName is the Nest Owner',
                  style: GoogleFonts.nunitoSans(fontSize: 15, fontWeight: FontWeight.w600, color: _textPrimary),
                ),
              ),
            ],
          ),
          if (!iAmOwner) ...[
            const SizedBox(height: 12),
            Text(
              'If something happens and the current owner becomes unreachable — for any reason — anyone in the nest can request to take over. Everyone is notified, and the current owner has a chance to respond first.',
              style: GoogleFonts.nunitoSans(fontSize: 12, color: _textSecondary, height: 1.5),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _successionActionLoading ? null : _confirmRequestOwnership,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF5DA399)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  'Request Nest Ownership',
                  style: GoogleFonts.nunitoSans(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF5DA399)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPendingSuccessionCard(bool iAmOwner, String? myUserId) {
    final req = _pendingSuccessionRequest!;
    final requesterId = req['requested_by'] as String;
    final requesterName = req['requester_name'] as String;
    final deadline = DateTime.parse(req['deadline'] as String);
    final now = DateTime.now();
    final iAmRequester = myUserId == requesterId;
    final iHaveObjected = _successionObjections.any((o) => o['objected_by'] == myUserId);

    String timeLeftLabel;
    final hoursLeft = deadline.difference(now).inHours;
    if (hoursLeft >= 24) {
      final daysLeft = (hoursLeft / 24).ceil();
      timeLeftLabel = '$daysLeft day${daysLeft == 1 ? '' : 's'} left';
    } else if (hoursLeft > 0) {
      timeLeftLabel = '$hoursLeft hour${hoursLeft == 1 ? '' : 's'} left';
    } else {
      timeLeftLabel = 'Resolving soon';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFC97B4A), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            iAmRequester
                ? 'Your request to become Nest Owner is pending'
                : '$requesterName has requested to become Nest Owner',
            style: GoogleFonts.nunitoSans(fontSize: 15, fontWeight: FontWeight.w700, color: _textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            '$timeLeftLabel for the current owner to respond. If nobody objects, ownership transfers automatically.',
            style: GoogleFonts.nunitoSans(fontSize: 12, color: _textSecondary, height: 1.5),
          ),
          if (_successionObjections.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${_successionObjections.length} member${_successionObjections.length == 1 ? ' has' : 's have'} objected',
              style: GoogleFonts.nunitoSans(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFFC97B4A)),
            ),
          ],
          const SizedBox(height: 12),
          if (iAmOwner)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _successionActionLoading
                        ? null
                        : () => _confirmApprove(req['id'] as String, requesterName),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5DA399),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Approve', style: GoogleFonts.nunitoSans(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _successionActionLoading ? null : () => _denySuccession(req['id'] as String),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFC97B4A)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      'Deny',
                      style: GoogleFonts.nunitoSans(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFFC97B4A)),
                    ),
                  ),
                ),
              ],
            )
          else if (!iAmRequester)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: (_successionActionLoading || iHaveObjected)
                    ? null
                    : () => _objectToSuccession(req['id'] as String),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFC97B4A)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  iHaveObjected ? 'You Objected' : 'Object to This',
                  style: GoogleFonts.nunitoSans(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFFC97B4A)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNestOwnershipSection(bool isTablet) {
    final myUserId = Supabase.instance.client.auth.currentUser?.id;
    final ownerId = _nestOwnerProfile?['id'] as String?;
    final ownerName = _nestOwnerProfile?['name'] as String? ?? 'the owner';
    final iAmOwner = myUserId != null && ownerId == myUserId;

    return Padding(
      padding: EdgeInsets.fromLTRB(isTablet ? 28 : 20, 20, isTablet ? 28 : 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('👑', 'Nest Ownership'),
          const SizedBox(height: 12),
          if (_justBecameOwnerRequestId != null) _buildNewOwnerBanner(),
          if (_pendingSuccessionRequest == null)
            _buildNoPendingSuccessionCard(iAmOwner, ownerName)
          else
            _buildPendingSuccessionCard(iAmOwner, myUserId),
          if (iAmOwner) ...[
            const SizedBox(height: 16),
            _buildToggleRow(
              icon: Icons.nights_stay_rounded,
              label: 'Memorial Space (Archive Nest)',
              value: _isNestArchived,
              onChanged: (v) => _confirmToggleArchiveNest(v),
            ),
          ],
        ],
      ),
    );
  }
  // ── Archive Nest Mode ──────────────────────────────────────────────
  // Owner-only. Quiets the daily-use prompts (check-in, meds, SOS) on
  // Home and Safety, replacing them with a memorial-space banner --
  // Legacy, photos, and messages are untouched, see family_feed_screen.dart
  // and safety_screen.dart for where the banner actually shows.
  void _confirmToggleArchiveNest(bool turningOn) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          turningOn ? 'Turn this Nest into a memorial space?' : 'Turn daily check-ins back on?',
          style: GoogleFonts.nunitoSans(fontSize: 20, fontWeight: FontWeight.w700, color: _textPrimary),
        ),
        content: Text(
          turningOn
              ? 'Daily check-in, medication, and SOS prompts will be turned off for everyone in this Nest. Legacy stories, photos, and messages stay exactly as they are -- nothing is deleted or locked, and you can turn this back on anytime.'
              : 'Daily check-in, medication, and SOS prompts will come back for everyone in this Nest.',
          style: GoogleFonts.nunitoSans(fontSize: 15, color: _textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.nunitoSans(fontSize: 15, color: _textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _setArchiveNestStatus(turningOn);
            },
            child: Text(
              turningOn ? 'Turn On' : 'Turn Back On',
              style: GoogleFonts.nunitoSans(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF5DA399)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setArchiveNestStatus(bool value) async {
    final previous = _isNestArchived;
    setState(() => _isNestArchived = value); // optimistic, reverted on failure below
    try {
      final prefs = await SharedPreferences.getInstance();
      final nestId = prefs.getString('nest_id') ?? '';
      if (nestId.isEmpty) throw Exception('No nest found.');
      await Supabase.instance.client
          .from('nests')
          .update({'is_archived': value}).eq('id', nestId);
    } catch (e) {
      if (mounted) setState(() => _isNestArchived = previous);
      _showSuccessionError(e);
    }
  }
  // ── End Nest Succession ─────────────────────────────────────────

  void _setupAnimations() {
    _itemAnimations.clear();
    for (int i = 0; i < 12; i++) {
      final start = (i * 0.07).clamp(0.0, 0.7);
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

  Future<void> _toggleDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', value);
    appDarkModeNotifier.value = value;
    setState(() => _isDarkMode = value);
  }

  Future<void> _togglePref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    setState(() {
      switch (key) {
        case 'meds_reminders':
          _medsReminders = value;
          break;
        case 'daily_check_in':
          _dailyCheckIn = value;
          break;
        case 'notify_messages':
          _notifyMessages = value;
          break;
        case 'notify_check_in':
          _notifyCheckIn = value;
          break;
      }
    });
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
      case 3:
        Navigator.pushReplacementNamed(context, '/safety-screen');
        break;
      case 4:
        Navigator.pushReplacementNamed(context, '/favs-screen');
        break;
    }
  }

  void _shareInviteCode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('invite_code_shared', true);
    appInviteCodeSharedNotifier.value = true;
    ShareService.shareInviteCode(context, inviteCode: _inviteCode);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;

    return Scaffold(
      backgroundColor: _bg,
      // Aug 19 2026: removed the KeyboardActions wrapper entirely. There
      // are no editable text fields on this screen's main body at all
      // (birthday/anniversary use date pickers, not TextFields) -- this
      // wrapper never had anything to do here. Setup's actual fields
      // (Rename Nest, profile name) live in their own modal sheets below,
      // are all single-line, and are already wired to the real iOS
      // keyboard's own Done key (textInputAction + onSubmitted) -- no
      // custom bar needed for those either. See those sheets' comments.
      body: Stack(
        children: [
          SafeArea(
        bottom: false,
        child: _isLoading
            ? _buildLoadingState()
            : CustomScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverToBoxAdapter(child: _buildTopBar(isTablet)),
                  SliverToBoxAdapter(child: _buildProfileCard(isTablet)),
                  if (_isVipMember)
                    SliverToBoxAdapter(child: _buildVipBadgeCard(isTablet)),
                  SliverToBoxAdapter(
                    child: _buildBirthdayAnniversaryCard(isTablet),
                  ),
                  if (_isGuest)
                    SliverToBoxAdapter(
                      child: _buildGuestAccountBanner(isTablet),
                    ),
                  if (_isNestOwner)
                    SliverToBoxAdapter(child: _buildInviteCodeCard(isTablet)),
                  SliverToBoxAdapter(child: _buildNestSection(isTablet)),
                  SliverToBoxAdapter(child: _buildPreferencesSection(isTablet)),
                  SliverToBoxAdapter(
                    child: _buildNotificationsSection(isTablet),
                  ),
                  SliverToBoxAdapter(child: _buildAppearanceSection(isTablet)),
                  SliverToBoxAdapter(child: _buildNestOwnershipSectionWrapper(isTablet)),
                  SliverToBoxAdapter(child: _buildAccountSection(isTablet)),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
                ],
              ),
          ),
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
                'Setup',
                style: GoogleFonts.nunitoSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                ),
              ),
              Text(
                'Customize your SeniorNest',
                style: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  color: _textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: _openProfilePhotoPicker,
            child: ProfileAvatarWidget(
              profileData: _profileData,
              displayName: _effectiveName,
              size: 40,
              borderColor: const Color(0xFF5DA399),
              borderWidth: 2,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openProfilePhotoPicker() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfilePhotoPickerScreen()),
    );
    if (result != null && mounted) {
      setState(() {
        _profileData = result as Map<String, dynamic>;
      });
    }
  }

  Widget _buildProfileCard(bool isTablet) {
    final anim = _itemAnimations.isNotEmpty
        ? _itemAnimations[0]
        : const AlwaysStoppedAnimation(1.0);
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
        onTap: () => _showEditProfileSheet(),
        child: Container(
          margin: EdgeInsets.symmetric(
            horizontal: isTablet ? 28 : 20,
            vertical: 8,
          ),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF5DA399), Color(0xFF7DBDB5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              ProfileAvatarWidget(
                profileData: _profileData,
                displayName: _effectiveName,
                size: 60,
                borderColor: Colors.white.withAlpha(90),
                borderWidth: 2,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _effectiveName,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    // Moved to its own card below (_buildVipBadgeCard) --
                    // gold-on-translucent-gold sitting directly on the teal
                    // gradient header was very low contrast and hard to
                    // read. A light card background matching the rest of
                    // this screen's cards reads far better.
                    // Clearly labeled role line
                    if (_isSenior)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(40),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_effectiveName.isNotEmpty ? _effectiveName : 'You'} — ${_isNestOwner ? 'Nest Owner 🏠' : 'Member'}',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      )
                    else
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(40),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_effectiveName.isNotEmpty ? _effectiveName : 'You'} — ${_isNestOwner ? 'Nest Owner 🏠' : 'Member'}',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.edit_rounded, color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVipBadgeCard(bool isTablet) {
    // Darker gold reads better on the light cream card; brighter gold
    // reads better against the dark card, same light/dark split as
    // _cardBg/_cardBorder above.
    final vipGold =
        _isDarkMode ? const Color(0xFFE8C040) : const Color(0xFFB8940A);
    return Container(
      margin: EdgeInsets.fromLTRB(
        isTablet ? 28 : 20,
        12,
        isTablet ? 28 : 20,
        0,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: vipGold, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(Icons.workspace_premium_rounded, color: vipGold, size: 20),
          const SizedBox(width: 10),
          Text(
            'VIP Lifetime Member',
            style: GoogleFonts.nunitoSans(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: vipGold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBirthdayAnniversaryCard(bool isTablet) {
    final anim = _itemAnimations.isNotEmpty
        ? _itemAnimations[1]
        : const AlwaysStoppedAnimation(1.0);

    String monthName(int month) {
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return months[month - 1];
    }

    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - anim.value)),
          child: child,
        ),
      ),
      child: Container(
        margin: EdgeInsets.fromLTRB(
          isTablet ? 28 : 20,
          12,
          isTablet ? 28 : 20,
          0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _cardBorder, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Birthday row
            GestureDetector(
              onTap: () => _pickDateOnMain(isBirthday: true),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cake_rounded,
                      color: Color(0xFFE05C5C),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _birthday != null
                            ? '${monthName(_birthday!.month)} ${_birthday!.day}'
                            : 'Birthday (optional)',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 15,
                          fontWeight: _birthday != null
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: _birthday != null
                              ? _textPrimary
                              : const Color(0xFFB0A898),
                        ),
                      ),
                    ),
                    if (_birthday != null)
                      GestureDetector(
                        onTap: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.remove('birthday');
                          setState(() => _birthday = null);
                          try {
                            final supabase = Supabase.instance.client;
                            final userId = supabase.auth.currentUser?.id;
                            if (userId != null) {
                              await supabase
                                  .from('user_profiles')
                                  .update({'birthday': null}).eq('id', userId);
                            }
                          } catch (e) {
                            debugPrint('SETUP_DATE_REMOVE_ERROR: $e');
                          }
                        },
                        child: const Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: Color(0xFFB0A898),
                        ),
                      )
                    else
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: Color(0xFFB0A898),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(color: Color(0xFFE8E0D0), height: 1),
            // Anniversary row
            GestureDetector(
              onTap: () => _pickDateOnMain(isBirthday: false),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.favorite_rounded,
                      color: Color(0xFFD4AA00),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _anniversary != null
                            ? '${monthName(_anniversary!.month)} ${_anniversary!.day}'
                            : 'Anniversary (optional)',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 15,
                          fontWeight: _anniversary != null
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: _anniversary != null
                              ? _textPrimary
                              : const Color(0xFFB0A898),
                        ),
                      ),
                    ),
                    if (_anniversary != null)
                      GestureDetector(
                        onTap: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.remove('anniversary');
                          setState(() => _anniversary = null);
                          try {
                            final supabase = Supabase.instance.client;
                            final userId = supabase.auth.currentUser?.id;
                            if (userId != null) {
                              await supabase
                                  .from('user_profiles')
                                  .update({'anniversary': null}).eq('id', userId);
                            }
                          } catch (e) {
                            debugPrint('SETUP_DATE_REMOVE_ERROR: $e');
                          }
                        },
                        child: const Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: Color(0xFFB0A898),
                        ),
                      )
                    else
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: Color(0xFFB0A898),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateOnMain({required bool isBirthday}) async {
    final now = DateTime.now();
    final initial = isBirthday
        ? (_birthday ?? DateTime(now.year - 60, 1, 1))
        : (_anniversary ?? DateTime(now.year - 10, 1, 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: isBirthday ? 'Select Birthday' : 'Select Anniversary',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF5DA399),
            onPrimary: Colors.white,
            surface: Color(0xFFFDFDFD),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      final prefs = await SharedPreferences.getInstance();
      if (isBirthday) {
        await prefs.setString('birthday', picked.toIso8601String());
        setState(() => _birthday = picked);
      } else {
        await prefs.setString('anniversary', picked.toIso8601String());
        setState(() => _anniversary = picked);
      }
      try {
        final supabase = Supabase.instance.client;
        final userId = supabase.auth.currentUser?.id;
        final userEmail = supabase.auth.currentUser?.email ?? '';
        if (userId != null) {
          await supabase.from('user_profiles').upsert({
            'id': userId,
            if (userEmail.isNotEmpty) 'email': userEmail,
            'birthday': _birthday?.toIso8601String(),
            'anniversary': _anniversary?.toIso8601String(),
          });
        }
      } catch (e) {
        debugPrint('SETUP_DATE_SYNC_ERROR: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  "Saved on this device, but couldn't reach the server. Please check your connection and try again."),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 6),
            ),
          );
        }
      }
    }
  }

  Widget _buildGuestAccountBanner(bool isTablet) {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, '/save-messages-prompt-screen');
      },
      child: Container(
        margin: EdgeInsets.fromLTRB(
          isTablet ? 28 : 20,
          16,
          isTablet ? 28 : 20,
          0,
        ),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF5DA399).withAlpha(20),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF5DA399).withAlpha(100),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF5DA399).withAlpha(40),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_add_rounded,
                color: Color(0xFF5DA399),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create Account to Save Your Messages',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Tap to sign up and keep your messages & stories safe',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 12,
                      color: _textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Color(0xFF5DA399),
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteCodeCard(bool isTablet) {
    final anim = _itemAnimations.length > 1
        ? _itemAnimations[1]
        : const AlwaysStoppedAnimation(1.0);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(opacity: anim.value, child: child),
      child: Container(
        margin: EdgeInsets.fromLTRB(
          isTablet ? 28 : 20,
          16,
          isTablet ? 28 : 20,
          0,
        ),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFD4AA00).withAlpha(15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFD4AA00).withAlpha(80),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.vpn_key_rounded,
                  color: Color(0xFFD4AA00),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Your Invite Code',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
                const Spacer(),
                // Only Nest Owner (senior) sees this — functional share button
                GestureDetector(
                  onTap: _shareInviteCode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5DA399),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.ios_share_rounded,
                          color: Colors.white,
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Share',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Tappable code with copy feedback
            GestureDetector(
              onTap: () {
                final code = _inviteCode;
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Invite code copied! 📋',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    backgroundColor: const Color(0xFF5DA399),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    margin: const EdgeInsets.all(16),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _inviteCode,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFD4AA00),
                          letterSpacing: 6,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.copy_rounded,
                        color: Color(0xFFD4AA00),
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Tap code to copy • Only you can share this as Nest Owner',
                style: GoogleFonts.nunitoSans(
                  fontSize: 12,
                  color: _textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNestSection(bool isTablet) {
    final anim = _itemAnimations.length > 2
        ? _itemAnimations[2]
        : const AlwaysStoppedAnimation(1.0);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(opacity: anim.value, child: child),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isTablet ? 28 : 20,
          24,
          isTablet ? 28 : 20,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('🏡', 'Your Nest'),
            const SizedBox(height: 12),
            if (_isNestOwner)
              _buildSettingRow(
                icon: Icons.home_rounded,
                label: 'Nest Name',
                value: _nestName,
                onTap: () => _showEditNestSheet(),
              ),
            _buildSettingRow(
              icon: Icons.people_rounded,
              label: 'Family Members',
              value: '${_familyMembers.length} members',
              onTap: () => _showFamilyMembersSheet(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNestOwnershipSectionWrapper(bool isTablet) {
    final anim = _itemAnimations.length > 3
        ? _itemAnimations[3]
        : const AlwaysStoppedAnimation(1.0);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(opacity: anim.value, child: child),
      child: _buildNestOwnershipSection(isTablet),
    );
  }

  Widget _buildPreferencesSection(bool isTablet) {
    final anim = _itemAnimations.length > 4
        ? _itemAnimations[4]
        : const AlwaysStoppedAnimation(1.0);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(opacity: anim.value, child: child),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isTablet ? 28 : 20,
          24,
          isTablet ? 28 : 20,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('⚙️', 'Preferences'),
            const SizedBox(height: 12),
            if (_isSenior) ...[
              _buildToggleRow(
                icon: Icons.medication_rounded,
                label: 'Medication Reminders',
                value: _medsReminders,
                onChanged: (v) => _togglePref('meds_reminders', v),
              ),
              _buildToggleRow(
                icon: Icons.favorite_rounded,
                label: 'Daily Check-In',
                value: _dailyCheckIn,
                onChanged: (v) => _togglePref('daily_check_in', v),
              ),
            ],
            _buildSettingRow(
              icon: Icons.text_fields_rounded,
              label: 'Text Size',
              value: _textSize,
              onTap: () => _showTextSizeSheet(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsSection(bool isTablet) {
    final anim = _itemAnimations.length > 6
        ? _itemAnimations[6]
        : const AlwaysStoppedAnimation(1.0);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(opacity: anim.value, child: child),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isTablet ? 28 : 20,
          24,
          isTablet ? 28 : 20,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('🔔', 'Notifications'),
            const SizedBox(height: 12),
            _buildToggleRow(
              icon: Icons.chat_bubble_rounded,
              label: 'New Messages',
              value: _notifyMessages,
              onChanged: (v) => _togglePref('notify_messages', v),
            ),
            _buildToggleRow(
              icon: Icons.favorite_rounded,
              label: '"I\'m Good Today" Check-ins',
              value: _notifyCheckIn,
              onChanged: (v) => _togglePref('notify_check_in', v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceSection(bool isTablet) {
    final anim = _itemAnimations.length > 8
        ? _itemAnimations[8]
        : const AlwaysStoppedAnimation(1.0);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(opacity: anim.value, child: child),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isTablet ? 28 : 20,
          24,
          isTablet ? 28 : 20,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('🎨', 'Appearance'),
            const SizedBox(height: 12),
            _buildToggleRow(
              icon: Icons.dark_mode_rounded,
              label: 'Dark Mode',
              value: _isDarkMode,
              onChanged: _toggleDarkMode,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSection(bool isTablet) {
    final anim = _itemAnimations.length > 10
        ? _itemAnimations[10]
        : const AlwaysStoppedAnimation(1.0);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(opacity: anim.value, child: child),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isTablet ? 28 : 20,
          24,
          isTablet ? 28 : 20,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('👤', 'Account'),
            const SizedBox(height: 12),
            _buildSettingRow(
              icon: Icons.help_outline_rounded,
              label: 'Help & Support',
              value: '',
              onTap: () => Navigator.pushNamed(context, '/help-support-screen'),
            ),
            _buildSettingRow(
              icon: Icons.privacy_tip_outlined,
              label: 'Privacy Policy',
              value: '',
              onTap: () =>
                  Navigator.pushNamed(context, '/privacy-policy-screen'),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _showSignOutDialog(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFC0392B).withAlpha(10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFC0392B).withAlpha(40),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.logout_rounded,
                      color: Color(0xFFC0392B),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sign Out',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFC0392B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _showDeleteAccountDialog(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B0000).withAlpha(10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF8B0000).withAlpha(40),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.delete_forever_rounded,
                      color: Color(0xFF8B0000),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Delete Account',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF8B0000),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String emoji, String title) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.nunitoSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _cardBorder, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF5DA399), size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.nunitoSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                ),
              ),
            ),
            if (value.isNotEmpty) ...[
              Text(
                value,
                style: GoogleFonts.nunitoSans(
                  fontSize: 13,
                  color: _textSecondary,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(Icons.chevron_right_rounded, color: _textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleRow({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF5DA399), size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF5DA399),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 6,
      itemBuilder: (context, index) => Container(
        height: index == 0 ? 100 : 60,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  void _showEditProfileSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditProfileSheet(
        displayName: _displayName,
        preferredName: _preferredName,
        birthday: _birthday,
        anniversary: _anniversary,
        isDarkMode: _isDarkMode,
        profileData: _profileData,
        onAvatarChanged: (data) => setState(() => _profileData = data),
        onSave: (name, preferredName, birthday, anniversary) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('display_name', name);
          await prefs.setString('preferred_name', preferredName);
          if (birthday != null) {
            await prefs.setString('birthday', birthday.toIso8601String());
          } else {
            await prefs.remove('birthday');
          }
          if (anniversary != null) {
            await prefs.setString('anniversary', anniversary.toIso8601String());
          } else {
            await prefs.remove('anniversary');
          }
          try {
            final supabase = Supabase.instance.client;
            final userId = supabase.auth.currentUser?.id;
            if (userId != null) {
              await supabase.from('user_profiles').update({
                'display_name': name,
                'preferred_name': preferredName,
                'birthday': birthday?.toIso8601String(),
                'anniversary': anniversary?.toIso8601String(),
              }).eq('id', userId);
            }
          } catch (e) {
            debugPrint('PROFILE_SAVE_ERROR: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      "Your changes were saved on this device, but couldn't reach the server. Please check your connection and try again."),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 6),
                ),
              );
            }
          }
          setState(() {
            _displayName = name;
            _preferredName = preferredName;
            _birthday = birthday;
            _anniversary = anniversary;
          });
          appDisplayNameNotifier.value =
              preferredName.trim().isNotEmpty ? preferredName.trim() : name;
        },
      ),
    );
  }

  void _showEditNestSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditNestSheet(
        nestName: _nestName,
        isDarkMode: _isDarkMode,
        onSave: (name) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('nest_name', name);
          try {
            final nestId = prefs.getString('nest_id') ?? '';
            if (nestId.isNotEmpty) {
              await Supabase.instance.client
                  .from('nests')
                  .update({'name': name}).eq('id', nestId);
            }
          } catch (e) {
            debugPrint('NEST_NAME_SAVE_ERROR: $e');
          }
          setState(() => _nestName = name);
          // Update the shared notifier immediately too, so Home's top bar
          // (and any other screen reading it) reflects a manual rename
          // right away, not just this screen.
          appNestNameNotifier.value = name;
        },
      ),
    );
  }

  void _showFamilyMembersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FamilyMembersSheet(
        members: List<Map<String, dynamic>>.from(_familyMembers),
        isNestOwner: _isNestOwner,
        isDarkMode: _isDarkMode,
        onRemoveMember: (memberId) => _confirmRemoveMember(memberId),
      ),
    );
  }

  void _confirmRemoveMember(String memberId) {
    final member = _familyMembers.firstWhere(
      (m) => m['id'] == memberId,
      orElse: () => {},
    );
    if (member.isEmpty) return;

    // Close the members sheet first
    Navigator.pop(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Remove ${member['name']}?',
          style: GoogleFonts.nunitoSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        content: Text(
          '${member['name']} will be removed from the nest and will no longer have access.',
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
              // Actually remove the member from the nest in Supabase --
              // previously this only hid them on this one device via a
              // local list, while their real nest_members row (and their
              // access) stayed untouched.
              final prefs = await SharedPreferences.getInstance();
              final supabase = Supabase.instance.client;
              bool deleteSucceeded = false;
              String? errorMessage;
              String resolvedNestId = '';
              try {
                resolvedNestId = prefs.getString('nest_id') ?? '';
                if (resolvedNestId.isEmpty) {
                  // Cached nest_id can be stale or missing on the owner's
                  // own device -- fall back to looking it up directly
                  // instead of silently no-op'ing the whole removal.
                  final ownerUserId = supabase.auth.currentUser?.id;
                  if (ownerUserId != null) {
                    final ownedNest = await supabase
                        .from('nests')
                        .select('id')
                        .eq('created_by', ownerUserId)
                        .maybeSingle();
                    resolvedNestId = ownedNest?['id'] as String? ?? '';
                  }
                }
                if (resolvedNestId.isNotEmpty) {
                  await supabase
                      .from('nest_members')
                      .delete()
                      .eq('user_id', memberId)
                      .eq('nest_id', resolvedNestId);
                  // Confirm the row is actually gone -- a blocked delete
                  // (e.g. an RLS denial) doesn't always throw, it can just
                  // silently affect zero rows. This is what stops the app
                  // from showing "removed" success when the person is
                  // still really a member.
                  final stillThere = await supabase
                      .from('nest_members')
                      .select('nest_id')
                      .eq('user_id', memberId)
                      .eq('nest_id', resolvedNestId)
                      .maybeSingle();
                  deleteSucceeded = stillThere == null;
                } else {
                  errorMessage = 'Could not find your nest — please try again.';
                }
              } catch (e) {
                debugPrint('REMOVE_MEMBER ERROR: $e');
                errorMessage =
                    'Something went wrong removing ${member['name']}. Please try again.';
              }

              if (!deleteSucceeded) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        errorMessage ??
                            '${member['name']} could not be removed. Please try again.',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      backgroundColor: const Color(0xFFB00020),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      margin: const EdgeInsets.all(16),
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
                return;
              }

              // Record a real, permanent removal -- previously "Remove
              // Member" only ever deleted the membership row, which is a
              // kick (same as Discord/GitHub): the person could always walk
              // back in with any still-valid invite code, since nothing
              // anywhere remembered they'd specifically been removed. This
              // is the actual ban record, checked at every future join
              // attempt regardless of which path they use to try to rejoin.
              try {
                final ownerUserId = supabase.auth.currentUser?.id;
                if (resolvedNestId.isNotEmpty) {
                  await supabase.from('nest_removed_members').upsert({
                    'nest_id': resolvedNestId,
                    'user_id': memberId,
                    'removed_by': ownerUserId,
                  });
                }
              } catch (e) {
                debugPrint('REMOVE_MEMBER_BAN_RECORD_ERROR: $e');
              }

              // Keep local hide-list too, so this device's list updates
              // instantly without waiting on a re-fetch.
              final removedIds =
                  prefs.getStringList('removed_member_ids') ?? [];
              if (!removedIds.contains(memberId)) {
                removedIds.add(memberId);
                await prefs.setStringList('removed_member_ids', removedIds);
              }
              setState(() {
                _familyMembers.removeWhere((m) => m['id'] == memberId);
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${member['name']} has been removed from the nest.',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    backgroundColor: const Color(0xFF5DA399),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    margin: const EdgeInsets.all(16),
                    duration: const Duration(seconds: 3),
                  ),
                );
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

  void _showTextSizeSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.all(24),
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
                'Text Size',
                style: GoogleFonts.nunitoSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              if (_isSenior) ...[
                const SizedBox(height: 6),
                Text(
                  'Seniors default to Large for comfortable reading',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 12,
                    color: _textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ...['Normal', 'Large', 'Extra Large'].map((size) {
                final isSelected = _textSize == size;
                final fontSize = size == 'Normal'
                    ? 15.0
                    : size == 'Large'
                    ? 18.0
                    : 22.0;
                return GestureDetector(
                  onTap: () async {
                    // Apply immediately and persist
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('text_size', size);
                    // Update global notifier so the whole app rescales at once
                    appTextScaleNotifier.value = textSizeToScale(size);
                    setState(() => _textSize = size);
                    setSheetState(() {});
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF5DA399).withAlpha(20)
                          : _surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF5DA399)
                            : _cardBorder,
                        width: isSelected ? 2 : 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Aa',
                          style: GoogleFonts.nunitoSans(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? const Color(0xFF5DA399)
                                : _textPrimary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          size,
                          style: GoogleFonts.nunitoSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? const Color(0xFF5DA399)
                                : _textPrimary,
                          ),
                        ),
                        if (_isSenior && size == 'Large' && !isSelected) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD4AA00).withAlpha(30),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Recommended',
                              style: GoogleFonts.nunitoSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFD4AA00),
                              ),
                            ),
                          ),
                        ],
                        if (isSelected) ...[
                          const Spacer(),
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF5DA399),
                            size: 22,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteAccountDialog() {
    // Aug 29 2026: Owners are blocked from deleting their own account here
    // -- deleting their profile would cascade-delete the entire nest out
    // from under every other member. This is enforced server-side too
    // (delete_user() raises OWNER_MUST_TRANSFER_OR_DELETE_NEST), this is
    // just a friendlier up-front message instead of a raw RPC error.
    if (_isNestOwner) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Transfer or Delete Your Nest First',
            style: GoogleFonts.nunitoSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          content: Text(
            'You\'re the owner of this nest, so deleting your account would also delete it for everyone in your family. Please transfer ownership to another member, or delete the whole nest, before deleting your own account.',
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
                'Got it',
                style: GoogleFonts.nunitoSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF5DA399),
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    final userEmail =
        Supabase.instance.client.auth.currentUser?.email?.trim() ?? '';
    final confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final typedEmail = confirmController.text.trim();
          final emailMatches = userEmail.isNotEmpty &&
              typedEmail.toLowerCase() == userEmail.toLowerCase();

          return AlertDialog(
            backgroundColor: _bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Delete Account?',
              style: GoogleFonts.nunitoSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deleting your account will remove your profile, subscription, medication and check-in history from this nest permanently. Your past messages and photos shared with the family will also be deleted and can\'t be recovered -- the family will lose those memories too. This cannot be undone.',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 15,
                    color: _textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Type your email address to confirm.',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmController,
                  keyboardType: TextInputType.emailAddress,
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  onChanged: (_) => setDialogState(() {}),
                  style: GoogleFonts.nunitoSans(
                    fontSize: 16,
                    color: _textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'your@email.com',
                    hintStyle: GoogleFonts.nunitoSans(
                      fontSize: 16,
                      color: _textSecondary.withAlpha(120),
                    ),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: Color(0xFFE8E0D0), width: 1.5),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: Color(0xFF8B0000), width: 2),
                    ),
                  ),
                ),
              ],
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
                onPressed: !emailMatches
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        // Aug 25 2026: was catching the delete_user RPC
                        // failure and silently swallowing it, then
                        // proceeding with local sign-out/wipe/navigation
                        // regardless -- someone could genuinely believe
                        // their account and data were gone when the
                        // server call never actually succeeded. Now stops
                        // and shows a real error on a genuine failure.
                        //
                        // Aug 29 2026: delete_user() now also raises
                        // OWNER_MUST_TRANSFER_OR_DELETE_NEST as a
                        // server-side backstop for the owner block above
                        // -- handled here in case nest-owner status was
                        // stale on this screen.
                        try {
                          await Supabase.instance.client.rpc('delete_user');
                        } catch (e) {
                          if (!mounted) return;
                          if (e.toString().contains(
                              'OWNER_MUST_TRANSFER_OR_DELETE_NEST')) {
                            _showDeleteAccountDialog();
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Couldn\'t delete your account -- please check your connection and try again.',
                                style: GoogleFonts.nunitoSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              backgroundColor: const Color(0xFFC97B4A),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        try {
                          await Supabase.instance.client.auth.signOut();
                        } catch (_) {}
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.clear();
                        if (mounted) {
                          Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/splash-screen',
                            (route) => false,
                          );
                        }
                      },
                child: Text(
                  'Delete Account',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: emailMatches
                        ? const Color(0xFF8B0000)
                        : _textSecondary.withAlpha(100),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Sign Out?',
          style: GoogleFonts.nunitoSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        content: Text(
          'You\'ll need to sign back in to access your family nest.',
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
              // Sign out from Supabase (and Google if applicable)
              await AuthService.signOut();
              final prefs = await SharedPreferences.getInstance();
              // Clear all user-specific cached data on sign-out
              await prefs.remove('display_name');
              await prefs.remove('preferred_name');
              await prefs.remove('user_role');
              await prefs.remove('relationship');
              await prefs.remove('relation_type');
              await prefs.remove('nest_id');
              await prefs.remove('cached_nest_id');
              await prefs.remove('bookmarks');
              await prefs.remove('bookmarked_items');
              await prefs.remove('cached_real_messages');
              await prefs.remove('cached_real_messages_nest_id');
              await prefs.remove('profile_photo_data');
              await prefs.remove('profile_photo_owner_id');
              await prefs.remove('birthday');
              await prefs.remove('anniversary');
              // These three were missing from this list -- meaning a
              // regular Sign Out (as opposed to full account deletion,
              // which does prefs.clear()) left them sitting on the device
              // indefinitely. Found while investigating D Von's report of
              // the wrong nest name appearing on a fresh invite-code
              // attempt, Aug 16 2026 -- confirmed as a real, separate gap
              // regardless of whether it's the exact cause of that report.
              await prefs.remove('invite_code');
              await prefs.remove('joined_via_invite');
              await prefs.remove('nest_name');
              await prefs.setBool('just_signed_out', true);
              // Aug 21 2026: correcting my own earlier mistake here,
              // confirmed by D Von's screenshots -- that fix sent sign-out
              // to save_messages_prompt_screen.dart, which is NOT the
              // real sign-in screen at all (its signInMode argument only
              // ever opens a "Create your account" sheet, regardless of
              // the argument's value -- the function it calls is even
              // named _showCreateAccountSheet). The real "Welcome back /
              // Sign In" screen he's used for many builds is a distinct
              // STATE of splash_screen.dart itself, driven by
              // appIsReturningUserNotifier (see app_state.dart's comment
              // on that notifier for the full design).
              //
              // That notifier is a field initializer read ONCE when
              // SplashScreen's widget is constructed -- confirmed by
              // tracing it precisely, not assumed -- and normally only
              // gets set during main.dart's cold-start resolution, which
              // doesn't run again mid-session. So navigating to
              // '/splash-screen' alone wouldn't be enough here either --
              // the notifier itself needs to be set directly, immediately,
              // right before navigating, so the fresh SplashScreen
              // instance this creates reads the correct value at
              // construction. just_signed_out above still matters
              // separately, for the case D Von already confirmed working
              // correctly -- fully exiting and reopening the app, which
              // goes through main.dart's real cold-start resolution and
              // reads that persisted flag fresh.
              appIsReturningUserNotifier.value = true;
              if (mounted) {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/splash-screen',
                  (route) => false,
                );
              }
            },
            child: Text(
              'Sign Out',
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
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({
    required this.displayName,
    required this.preferredName,
    required this.isDarkMode,
    required this.onSave,
    this.birthday,
    this.anniversary,
    this.profileData,
    this.onAvatarChanged,
  });
  final String displayName;
  final String preferredName;
  final bool isDarkMode;
  final DateTime? birthday;
  final DateTime? anniversary;
  final Map<String, dynamic>? profileData;
  final void Function(Map<String, dynamic>?)? onAvatarChanged;
  final Future<void> Function(String, String, DateTime?, DateTime?) onSave;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late TextEditingController _nameController;
  late TextEditingController _preferredNameController;
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _preferredNameFocusNode = FocusNode();
  bool _isSaving = false;
  DateTime? _birthday;
  DateTime? _anniversary;
  Map<String, dynamic>? _profileData;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.displayName);
    _preferredNameController = TextEditingController(text: widget.preferredName);
    _birthday = widget.birthday;
    _anniversary = widget.anniversary;
    _profileData = widget.profileData;
  }

  Future<void> _openAvatarPicker() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfilePhotoPickerScreen()),
    );
    if (result != null && mounted) {
      setState(() => _profileData = result as Map<String, dynamic>);
      widget.onAvatarChanged?.call(_profileData);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _preferredNameController.dispose();
    _nameFocusNode.dispose();
    _preferredNameFocusNode.dispose();
    super.dispose();
  }

  Color get _bg =>
      widget.isDarkMode ? const Color(0xFF242018) : const Color(0xFFFDFDFD);
  Color get _textPrimary =>
      widget.isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      widget.isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    // Aug 19 2026: removed the KeyboardActions wrapper. Both fields here
    // (Your name, Preferred name) are single-line and already wired to
    // the real iOS keyboard's own Done/Next key via textInputAction +
    // onSubmitted -- no custom bar needed. D Von's direct ask after the
    // package swap didn't fix the underlying symptoms on any of the three
    // screens: go back to first principles instead of a third package
    // attempt. Native keyboard actions can't desync from the keyboard,
    // because they ARE the keyboard.
    return Container(
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
            'Edit Profile',
            style: GoogleFonts.nunitoSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: _openAvatarPicker,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ProfileAvatarWidget(
                    profileData: _profileData,
                    displayName: widget.displayName,
                    size: 72,
                    borderColor: const Color(0xFF5DA399),
                    borderWidth: 2,
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5DA399),
                        shape: BoxShape.circle,
                        border: Border.all(color: _bg, width: 2),
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            focusNode: _nameFocusNode,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).requestFocus(_preferredNameFocusNode),
            style: GoogleFonts.nunitoSans(fontSize: 18, color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Your name',
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
            controller: _preferredNameController,
            focusNode: _preferredNameFocusNode,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            style: GoogleFonts.nunitoSans(fontSize: 18, color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Preferred name (optional)',
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
          _buildDateField(
            label: 'Birthday (optional)',
            icon: Icons.cake_rounded,
            iconColor: const Color(0xFFE05C5C),
            value: _birthday,
            onTap: () => _pickDate(isBirthday: true),
          ),
          const SizedBox(height: 12),
          _buildDateField(
            label: 'Anniversary (optional)',
            icon: Icons.favorite_rounded,
            iconColor: const Color(0xFFD4AA00),
            value: _anniversary,
            onTap: () => _pickDate(isBirthday: false),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isSaving
                  ? null
                  : () async {
                      if (_nameController.text.trim().isEmpty) return;
                      setState(() => _isSaving = true);
                      await widget.onSave(
                        _nameController.text.trim(),
                        _preferredNameController.text.trim(),
                        _birthday,
                        _anniversary,
                      );
                      if (mounted) Navigator.pop(context);
                    },
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
        ],
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required IconData icon,
    required Color iconColor,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    final hasValue = value != null;
    final displayText = hasValue
        ? '${_monthName(value.month)} ${value.day}'
        : label;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFE8E0D0), width: 1.5),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                displayText,
                style: GoogleFonts.nunitoSans(
                  fontSize: 16,
                  fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                  color: hasValue ? _textPrimary : const Color(0xFFB0A898),
                ),
              ),
            ),
            if (hasValue)
              GestureDetector(
                onTap: () => setState(() {
                  if (label.contains('Birthday')) {
                    _birthday = null;
                  } else {
                    _anniversary = null;
                  }
                }),
                child: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Color(0xFFB0A898),
                ),
              )
            else
              const Icon(
                Icons.calendar_today_rounded,
                size: 16,
                color: Color(0xFFB0A898),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate({required bool isBirthday}) async {
    final now = DateTime.now();
    final initial = isBirthday
        ? (_birthday ?? DateTime(now.year - 60, 1, 1))
        : (_anniversary ?? DateTime(now.year - 10, 1, 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: isBirthday ? 'Select Birthday' : 'Select Anniversary',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF5DA399),
            onPrimary: Colors.white,
            surface: Color(0xFFFDFDFD),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isBirthday) {
          _birthday = picked;
        } else {
          _anniversary = picked;
        }
      });
    }
  }

  String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}

class _EditNestSheet extends StatefulWidget {
  const _EditNestSheet({
    required this.nestName,
    required this.isDarkMode,
    required this.onSave,
  });
  final String nestName;
  final bool isDarkMode;
  final Future<void> Function(String) onSave;

  @override
  State<_EditNestSheet> createState() => _EditNestSheetState();
}

class _EditNestSheetState extends State<_EditNestSheet> {
  late TextEditingController _nestController;
  final FocusNode _nestFieldFocusNode = FocusNode();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nestController = TextEditingController(text: widget.nestName);
  }

  @override
  void dispose() {
    _nestController.dispose();
    _nestFieldFocusNode.dispose();
    super.dispose();
  }

  Color get _bg =>
      widget.isDarkMode ? const Color(0xFF242018) : const Color(0xFFFDFDFD);
  Color get _textPrimary =>
      widget.isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      widget.isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    // Standing on Aug 15's double-checkmark fix: this used to suppress the
    // parent screen's ambient KeyboardDoneBarOverlay while this field was
    // focused, since single-line fields relied on the native "Done" key
    // for dismissal. As of Aug 16, D Von decided every field should use
    // the exact same custom bar app-wide, single-line or multi-line --
    // no more relying on the native key's styling to happen to look
    // similar. This field now uses TextInputAction.go (a plain text
    // label, not a checkmark) so the only checkmark on screen is ever
    // the custom bar's. Tap-anywhere-in-the-sheet stays as a backup way
    // to dismiss the keyboard, same as before.
    // Aug 16: modals opened via showModalBottomSheet render as their own
    // separate layer ON TOP of the screen behind them -- relying on that
    // parent screen's ambient KeyboardDoneBarOverlay never actually
    // worked correctly for them, since the bar lives in a layer BELOW
    // this modal. Depending on whether this modal's own content happened
    // to leave a gap down to the keyboard, the parent's bar either showed
    // through disconnected from this modal's own buttons, or (here) was
    // fully covered and invisible. Wrapping this modal's own content in
    // KeyboardDoneBar makes the bar genuinely part of THIS layer instead.
    // Aug 19 2026: removed the KeyboardActions wrapper (and the
    // keyboard_actions package attempt before it). Nest name is a
    // single-line field, already wired to the real iOS keyboard's own
    // Done key via textInputAction: TextInputAction.go +
    // onSubmitted: unfocus() -- no custom bar needed at all. D Von's
    // direct ask after the package swap didn't fix the underlying
    // symptoms on any of the three screens: go back to first principles.
    // Native keyboard actions can't desync from the keyboard, because
    // they ARE the keyboard.
    return GestureDetector(
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
            'Rename Your Nest',
            style: GoogleFonts.nunitoSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nestController,
            focusNode: _nestFieldFocusNode,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            style: GoogleFonts.nunitoSans(fontSize: 18, color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Nest name',
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
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isSaving
                  ? null
                  : () async {
                      if (_nestController.text.trim().isEmpty) return;
                      setState(() => _isSaving = true);
                      await widget.onSave(_nestController.text.trim());
                      if (mounted) Navigator.pop(context);
                    },
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
                      'Save Name',
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
    );
  }
}

// ── Family Members Sheet ────────────────────────────────────────

class _FamilyMembersSheet extends StatefulWidget {
  const _FamilyMembersSheet({
    required this.members,
    required this.isNestOwner,
    required this.isDarkMode,
    required this.onRemoveMember,
  });

  final List<Map<String, dynamic>> members;
  final bool isNestOwner;
  final bool isDarkMode;
  final void Function(String memberId) onRemoveMember;

  @override
  State<_FamilyMembersSheet> createState() => _FamilyMembersSheetState();
}

class _FamilyMembersSheetState extends State<_FamilyMembersSheet> {
  Color get _bg =>
      widget.isDarkMode ? const Color(0xFF242018) : const Color(0xFFFDFDFD);
  Color get _cardBg =>
      widget.isDarkMode ? const Color(0xFF2E2820) : const Color(0xFFFAF7F2);
  Color get _cardBorder =>
      widget.isDarkMode ? const Color(0xFF3D3428) : const Color(0xFFE8E0D0);
  Color get _textPrimary =>
      widget.isDarkMode ? const Color(0xFFF5EDD8) : const Color(0xFF2C2417);
  Color get _textSecondary =>
      widget.isDarkMode ? const Color(0xFFB8A888) : const Color(0xFF6B5E4E);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
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
          // Title
          Row(
            children: [
              Text(
                'Family Members',
                style: GoogleFonts.nunitoSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF5DA399).withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${widget.members.length} members',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF5DA399),
                  ),
                ),
              ),
            ],
          ),
          if (widget.isNestOwner) ...[
            const SizedBox(height: 6),
            Text(
              'Tap a member to manage their access',
              style: GoogleFonts.nunitoSans(
                fontSize: 12,
                color: _textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Members list
          if (widget.members.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No family members have joined yet.',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 14,
                    color: _textSecondary,
                  ),
                ),
              ),
            )
          else
            ...widget.members.map((member) {
              return GestureDetector(
                onTap: widget.isNestOwner
                    ? () => _showMemberOptions(context, member)
                    : null,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _cardBorder, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      // Avatar
                      ProfileAvatarWidget(
                        avatarUrl: member['avatarUrl'] as String?,
                        displayName: member['name'] as String,
                        size: 44,
                      ),
                      const SizedBox(width: 14),
                      // Name & relationship
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              member['name'] as String,
                              style: GoogleFonts.nunitoSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _textPrimary,
                              ),
                            ),
                            Text(
                              member['relationship'] as String,
                              style: GoogleFonts.nunitoSans(
                                fontSize: 12,
                                color: _textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Only Nest Owner sees the manage chevron
                      if (widget.isNestOwner)
                        Icon(
                          Icons.more_vert_rounded,
                          color: _textSecondary,
                          size: 20,
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

  void _showMemberOptions(BuildContext context, Map<String, dynamic> member) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE8E0D0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            // Member info header
            Row(
              children: [
                ProfileAvatarWidget(
                  avatarUrl: member['avatarUrl'] as String?,
                  displayName: member['name'] as String,
                  size: 48,
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member['name'] as String,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                      ),
                    ),
                    Text(
                      member['relationship'] as String,
                      style: GoogleFonts.nunitoSans(
                        fontSize: 13,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: Color(0xFFE8E0D0), height: 1),
            const SizedBox(height: 16),
            // Remove from Nest option
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx); // close options sheet
                widget.onRemoveMember(member['id'] as String);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFC0392B).withAlpha(10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFC0392B).withAlpha(40),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.person_remove_rounded,
                      color: Color(0xFFC0392B),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Remove from Nest',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFC0392B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Cancel
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _cardBorder, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.nunitoSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
