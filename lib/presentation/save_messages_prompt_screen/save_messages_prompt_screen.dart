import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../routes/app_routes.dart';
import '../profile_photo_picker_screen/profile_photo_picker_screen.dart' show kProfilePhotoKey, kProfilePhotoOwnerKey;
import '../../services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:math';
import '../splash_screen/widgets/nest_logo_widget.dart';
import '../../widgets/keyboard_done_bar.dart';
import '../../widgets/branded_transition_screen.dart';

class SaveMessagesPromptScreen extends StatefulWidget {
  const SaveMessagesPromptScreen({super.key});

  @override
  State<SaveMessagesPromptScreen> createState() =>
      _SaveMessagesPromptScreenState();
}

class _SaveMessagesPromptScreenState extends State<SaveMessagesPromptScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  bool _isLoading = false;
  bool _isAuthLoading = false;
  // True for the whole duration of _navigateToHome's post-auth setup work
  // (profile upsert, nest lookup/creation, subscription check) -- not just
  // the OAuth handshake itself, which is all _isAuthLoading ever covered.
  // That gap (2-4 seconds, no spinner) was what looked like the app had
  // silently failed after tapping Google/Apple/email sign-in.
  bool _isNavigatingHome = false;
  StreamSubscription? _authSub;
  String? _authError;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null && args['signInMode'] == true) {
        _showCreateAccountSheet();
      }
    });
    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    _animController.forward();

    // Listen for successful auth (native Apple Sign-In)
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      // Navigation handled by onSuccess callback — not here
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _continueAsGuest() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_guest', true);
    await prefs.setBool('onboarding_complete', true);
    await prefs.setBool('first_load', true);
    await prefs.setBool('has_onboarded', true);

    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.familyFeedScreen,
        arguments: {'role': prefs.getString('user_role') ?? 'senior'},
      );
    }
  }

  Future<void> _navigateToHome({String? userId}) async {
    if (mounted) setState(() => _isNavigatingHome = true);
    final navigateStartTime = DateTime.now();

    // Capture this fresh signup's own just-entered values BEFORE the wipe
    // below, so they can be restored right after it. nest_name, nest_id,
    // invite_code, and joined_via_invite are account-scoped and correctly
    // wiped by clearStaleAccountDataIfUserChanged now (auth_service.dart)
    // -- previously they were excluded from that wipe entirely, which is
    // exactly why stale values kept independently resurfacing as "cross
    // contamination" in different screens all night, even after each
    // individual display bug got patched. This is the one genuinely
    // legitimate exception to that: a brand-new signup enters these
    // values in senior_onboarding_screen/family_onboarding_screen BEFORE
    // they've ever authenticated, then authenticates and reaches this
    // exact function -- which is the very first moment a real user id
    // exists to compare against, so it's also the first moment the wipe
    // below can possibly fire for them. Without restoring these specific
    // four immediately after, wiping here would erase what they just
    // typed moments before this same flow uses it, a few lines down.
    final preWipePrefs = await SharedPreferences.getInstance();
    final preWipeNestName = preWipePrefs.getString('nest_name');
    final preWipeNestId = preWipePrefs.getString('nest_id');
    final preWipeInviteCode = preWipePrefs.getString('invite_code');
    final preWipeJoinedViaInvite = preWipePrefs.getBool('joined_via_invite');

    // Must run before anything else that reads account-scoped data --
    // detects a genuine account switch on this device and wipes every
    // locally cached piece of account-specific data before it can be read
    // stale. This is the single root-cause fix for what were previously
    // several separate bugs (dark mode, user role, nest name all bleeding
    // between accounts on the same device) sharing one cause: local prefs
    // with no connection to which account set them.
    await AuthService.clearStaleAccountDataIfUserChanged(knownUserId: userId);

    final prefs = await SharedPreferences.getInstance();
    if (preWipeNestName != null) await prefs.setString('nest_name', preWipeNestName);
    if (preWipeNestId != null) await prefs.setString('nest_id', preWipeNestId);
    if (preWipeInviteCode != null) await prefs.setString('invite_code', preWipeInviteCode);
    if (preWipeJoinedViaInvite != null) await prefs.setBool('joined_via_invite', preWipeJoinedViaInvite);

    await prefs.setBool('onboarding_complete', true);
    await prefs.setBool('first_load', true);
    await prefs.setBool('has_onboarded', true);

    // Small delay to ensure Supabase auth session is fully established
    await Future.delayed(const Duration(milliseconds: 500));

    // Always update profile first regardless of whether nest exists
    final supabaseClient = Supabase.instance.client;
    final checkUserId = userId ?? supabaseClient.auth.currentUser?.id;
    if (checkUserId != null) {
      try {
        // For returning users: read from Supabase first to get real data
        // This prevents stale SharedPreferences from overwriting Supabase
        final existingProfile = await supabaseClient
            .from('user_profiles')
            .select('display_name, preferred_name, role, relation_type, avatar_url')
            .eq('id', checkUserId)
            .maybeSingle();

        String name = prefs.getString('display_name') ?? '';
        String preferredName = prefs.getString('preferred_name') ?? '';
        String role = prefs.getString('user_role') ?? 'senior';
        String relationshipType = prefs.getString('relationship') ?? '';
        // Set below if local cache has an avatar Supabase is missing --
        // see self-heal push logic further down.
        String? avatarToPush;

        if (existingProfile != null) {
          final supabaseName = existingProfile['display_name'] as String? ?? '';
          final supabasePreferredName = existingProfile['preferred_name'] as String? ?? '';
          final supabaseRole = existingProfile['role'] as String? ?? '';
          final supabaseRelation = existingProfile['relation_type'] as String? ?? '';
          // If Supabase already has real data, use it (returning user)
          if (supabaseName.isNotEmpty) {
            name = supabaseName;
            await prefs.setString('display_name', name);
          }
          if (supabasePreferredName.isNotEmpty) {
            preferredName = supabasePreferredName;
            await prefs.setString('preferred_name', preferredName);
          }
          if (supabaseRole.isNotEmpty && supabaseRole != 'senior') {
            role = supabaseRole;
            await prefs.setString('user_role', role);
          }
          if (supabaseRelation.isNotEmpty) {
            relationshipType = supabaseRelation;
            await prefs.setString('relation_type', supabaseRelation);
            await prefs.setString('relationship', supabaseRelation);
          }
          // Avatar cache is unconditionally synced to Supabase (the source
          // of truth) on every sign-in -- not just when there's a new value
          // to write. Previously this only ever ADDED a fresh avatar and
          // never CLEARED a stale one, so switching accounts on the same
          // device (especially skipping the in-app Sign Out button) could
          // leave the previous user's avatar cached indefinitely under the
          // new account.
          final avatarUrl = existingProfile['avatar_url'] as String? ?? '';
          if (avatarUrl.isNotEmpty) {
            await prefs.setString(kProfilePhotoKey, avatarUrl);
            await prefs.setString(kProfilePhotoOwnerKey, checkUserId);
            print('PROFILE_PHOTO: restored from Supabase for user $checkUserId');
          } else {
            // Supabase shows no avatar -- but that can legitimately mean
            // "hasn't synced yet" right after picking one during this same
            // onboarding session, not "this user genuinely has none". Only
            // clear the local cache if it actually belongs to a DIFFERENT
            // user (a real account switch); otherwise trust what's already
            // cached for this same user rather than destroying a fresh pick.
            final cachedOwnerId = prefs.getString(kProfilePhotoOwnerKey);
            if (cachedOwnerId != null && cachedOwnerId != checkUserId) {
              await prefs.remove(kProfilePhotoKey);
              await prefs.remove(kProfilePhotoOwnerKey);
              print('PROFILE_PHOTO: cached avatar belonged to a different user -- cleared stale cache');
            } else if (cachedOwnerId == checkUserId || cachedOwnerId == null) {
              // Self-heal: local cache has an avatar but Supabase doesn't.
              // cachedOwnerId is commonly null here -- NOT because the data
              // is ownerless/stale, but because the avatar was picked
              // *during onboarding, before this account existed*. The
              // picker only tags an owner id when a signed-in user is
              // already present at pick time (see profile_photo_picker_screen
              // .dart _saveAndReturn); picking an avatar as one of the first
              // onboarding steps -- before the final "create account" step
              // -- leaves it untagged. Since sign-out always clears both
              // kProfilePhotoKey and kProfilePhotoOwnerKey together, any
              // local avatar data with no owner tag can only be a fresh,
              // not-yet-claimed pick from the current device session --
              // safe to attribute to whichever account is completing
              // sign-up/sign-in right now. This was the actual gap causing
              // build 140's avatar fix not to fire at all: the old check
              // required an exact owner match and silently did nothing when
              // cachedOwnerId was null instead of treating it as claimable.
              final localAvatar = prefs.getString(kProfilePhotoKey);
              if (localAvatar != null && localAvatar.isNotEmpty) {
                avatarToPush = localAvatar;
                await prefs.setString(kProfilePhotoOwnerKey, checkUserId);
                print('PROFILE_PHOTO: local cache has an avatar Supabase is missing -- will push it up');
              } else {
                print('PROFILE_PHOTO: no Supabase avatar yet for user $checkUserId, and no local cache either');
              }
            }
          }
        }

        // Only write to Supabase if we have real data to write
        if (name.isNotEmpty || avatarToPush != null) {
          // email is a NOT NULL column. Postgres validates NOT NULL on the
          // candidate row for INSERT ... ON CONFLICT DO UPDATE *before* it
          // checks for a conflict, even when a matching row already exists —
          // so upsert() fails without this regardless of whether the profile
          // row was already created by the signup trigger.
          //
          // Confirmed via live Supabase logs (Aug 3, 2026) that this raced
          // and threw "null value in column email ... violates not-null
          // constraint" at least once -- currentUser?.email can genuinely
          // be empty for a brief moment right after auth completes. Retry
          // once after a short delay instead of silently dropping the field
          // and letting the whole upsert fail.
          String userEmail = supabaseClient.auth.currentUser?.email ?? '';
          if (userEmail.isEmpty) {
            await Future.delayed(const Duration(milliseconds: 400));
            userEmail = supabaseClient.auth.currentUser?.email ?? '';
          }
          final updateData = <String, dynamic>{
            'id': checkUserId,
            if (userEmail.isNotEmpty) 'email': userEmail,
            if (name.isNotEmpty) 'display_name': name,
            if (name.isNotEmpty) 'full_name': name,
            if (name.isNotEmpty) 'role': role,
          };
          if (preferredName.isNotEmpty) {
            updateData['preferred_name'] = preferredName;
          }
          if (relationshipType.isNotEmpty) {
            updateData['relation_type'] = relationshipType.toLowerCase();
          }
          if (avatarToPush != null) {
            updateData['avatar_url'] = avatarToPush;
          }
          // Sync birthday/anniversary to Supabase too -- these used to be
          // local-device-only, which meant they silently bled across
          // accounts on a shared test device and never reached other nest
          // members at all (celebrations are meant to be nest-wide).
          final localBirthday = prefs.getString('birthday');
          final localAnniversary = prefs.getString('anniversary');
          if (localBirthday != null) {
            updateData['birthday'] = localBirthday;
          }
          if (localAnniversary != null) {
            updateData['anniversary'] = localAnniversary;
          }
          if (userEmail.isEmpty) {
            // Still empty after the retry. Skip the write entirely rather
            // than let Postgres reject it -- but log loudly, since a silent
            // failure here is exactly what hid this bug for a week.
            print('PROFILE_UPSERT_ERROR: no email available for user $checkUserId after retry -- skipping upsert to avoid NOT NULL violation');
          } else {
            // Upsert (not update) — the profile row may not exist yet for a
            // brand new signup now that the auto-create trigger is removed.
            // An update() on a nonexistent row silently affects zero rows.
            await supabaseClient.from('user_profiles').upsert(updateData);
            print('NEST_DEBUG: profile upserted at top of _navigateToHome${avatarToPush != null ? ' (including self-heal avatar push)' : ''}');
          }
        }
      } catch (e, st) {
        print('NEST_DEBUG: profile update error = $e');
        print('NEST_DEBUG: profile update stack = $st');
      }
    }

    // If user already has a valid nest, skip nest creation and go straight to Home Feed
    if (checkUserId != null) {
      try {
        final existingMembership = await supabaseClient
            .from('nest_members')
            .select('nest_id')
            .eq('user_id', checkUserId)
            .maybeSingle();
        if (existingMembership != null) {
          final existingNestId = existingMembership['nest_id'] as String;
          await prefs.setString('nest_id', existingNestId);
          if (mounted) {
            Navigator.pushNamedAndRemoveUntil(
              context,
              '/family-feed-screen',
              (route) => false,
              arguments: {'role': prefs.getString('user_role') ?? 'senior'},
            );
          }
          return;
        }
      } catch (_) {}
    }

    // Create nest in Supabase now that auth session is ready
    final supabase = Supabase.instance.client;
    final effectiveUserId = userId ?? supabase.auth.currentUser?.id;
    print('NEST_DEBUG: _navigateToHome effectiveUserId = $effectiveUserId');

    if (effectiveUserId != null) {
      // Deferred VIP redemption -- the code was only validated (not
      // consumed) back at splash/role-choice, before this account existed.
      // This is the ONLY place in the entire app where a first-time signup
      // actually gets a real Supabase auth session (save_messages_prompt_
      // screen.dart's Google/Apple/email handlers) -- senior_onboarding_
      // screen and family_onboarding_screen both run BEFORE that session
      // exists for a brand-new user, so their own copies of this exact
      // redemption call (gated on userId != null) were always dead code
      // for a fresh signup. That's the actual reason the VIP badge never
      // appeared: redeem_vip_code was simply never being called at all.
      final cachedVipCode = prefs.getString('vip_code');
      if (cachedVipCode != null && cachedVipCode.isNotEmpty) {
        try {
          await supabase.rpc('redeem_vip_code', params: {
            'p_code': cachedVipCode,
            'p_user_id': effectiveUserId,
          });
          await prefs.remove('vip_code');
        } catch (e) {
          debugPrint('VIP_REDEMPTION_ERROR: $e');
        }
      }

      // We already confirmed via the database above that this user has no
      // existing nest membership — clear any stale local nest_id left over
      // from a different account previously signed in on this same device.
      await prefs.remove('nest_id');
      final existingNestId = prefs.getString('nest_id') ?? '';
      if (existingNestId.isEmpty) {
        try {
          final name = prefs.getString('display_name') ?? '';
          final preferredNestName = prefs.getString('preferred_name') ?? '';
          final role = prefs.getString('user_role') ?? 'senior';
          final userEmail = supabase.auth.currentUser?.email ?? '';
          final relationshipType = prefs.getString('relationship') ?? '';
          final nestProfileUpdate = <String, dynamic>{
            'id': effectiveUserId,
            if (userEmail.isNotEmpty) 'email': userEmail,
            'display_name': name,
            'full_name': name,
            'role': role,
          };
          if (relationshipType.isNotEmpty) {
            nestProfileUpdate['relation_type'] = relationshipType.toLowerCase();
          }
          if (preferredNestName.isNotEmpty) {
            nestProfileUpdate['preferred_name'] = preferredNestName;
          }
          final localBirthday2 = prefs.getString('birthday');
          final localAnniversary2 = prefs.getString('anniversary');
          if (localBirthday2 != null) {
            nestProfileUpdate['birthday'] = localBirthday2;
          }
          if (localAnniversary2 != null) {
            nestProfileUpdate['anniversary'] = localAnniversary2;
          }
          await supabase.from('user_profiles').upsert(nestProfileUpdate);
          print('NEST_DEBUG: profile upserted');

          // A user who came in through an invite code (family member joining
          // an existing senior's nest) must NEVER hit the "create new nest"
          // path below — the code in their 'invite_code' pref is the code
          // they TYPED to find that existing nest, not a fresh code for a
          // new one. Reusing it in a nests INSERT collides on the
          // nests_invite_code_key unique constraint, since that code
          // already belongs to the nest they're trying to join.
          final joinedViaInvite = prefs.getBool('joined_via_invite') ?? false;
          final typedInviteCode = prefs.getString('invite_code') ?? '';

          if (joinedViaInvite && typedInviteCode.isNotEmpty) {
            final lookupResult = await supabase.rpc(
              'lookup_nest_by_invite_code',
              params: {'p_code': typedInviteCode.toUpperCase()},
            );
            final nestResponse = (lookupResult is List && lookupResult.isNotEmpty)
                ? lookupResult.first as Map<String, dynamic>
                : null;

            if (nestResponse != null) {
              final nestId = nestResponse['id'] as String;

              // Real, deterministic ban check -- replaces the earlier
              // fragile account-age heuristic. Google/Apple/email sign-in
              // all funnel through this same function for BOTH a brand-new
              // signup and a returning sign-in, and a removed member's
              // device still has 'joined_via_invite' and the old
              // 'invite_code' cached locally (removal happens on the
              // OWNER's device and touches nothing here). This checks
              // whether THIS specific person was specifically removed from
              // THIS specific nest -- a real record, not a guess based on
              // how old the account looks.
              bool isBanned = false;
              try {
                final banCheck = await supabase.rpc(
                  'is_user_banned_from_nest',
                  params: {'p_nest_id': nestId, 'p_user_id': effectiveUserId},
                );
                isBanned = banCheck == true;
              } catch (e) {
                print('BAN_CHECK_ERROR: $e');
              }

              if (isBanned) {
                await prefs.remove('nest_id');
                await prefs.remove('invite_code');
                await prefs.setBool('joined_via_invite', false);
                // Splash screen has its own auto-navigation logic that runs
                // on load and would otherwise race against this banner --
                // resetting these two flags is what makes it safely skip
                // that logic and just show the normal splash screen instead.
                await prefs.setBool('has_onboarded', false);
                await prefs.setBool('onboarding_complete', false);
                if (mounted) {
                  // Previously this called showSnackBar() then immediately
                  // cleared the entire navigation stack with
                  // pushNamedAndRemoveUntil -- which tears down the very
                  // screen hosting that SnackBar before it ever really
                  // appears. That's why the red message kept vanishing.
                  // Now the message is passed as an argument to the
                  // destination screen, which shows it once it's actually
                  // settled and staying on screen.
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/splash-screen',
                    (route) => false,
                    arguments: {
                      'bannerMessage':
                          'This invite is no longer valid for your account. Please ask the nest owner for a new invite.',
                    },
                  );
                }
                return;
              }

              await prefs.setString('nest_id', nestId);
              await supabase.from('nest_members').upsert({
                'nest_id': nestId,
                'user_id': effectiveUserId,
              });
              print('NEST_DEBUG: joined existing nest = $nestId');
            } else {
              print('NEST_DEBUG: invite code not found = $typedInviteCode');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('DEBUG: could not find nest for invite code $typedInviteCode'),
                    duration: const Duration(seconds: 10),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          } else {
            // Owner path — always generate a fresh code, never reuse a
            // cached one. The comment above this block already said "never
            // reuse a typed one," but the code used to check prefs first
            // and reuse whatever was cached if it happened to match the
            // NEST###### format -- which is exactly what a PREVIOUS
            // account's invite code would also look like. D Von hit this
            // for real (Aug 16): signing out of the senior account and
            // into a family-owner signup reused the senior nest's own
            // still-cached invite code, colliding on the nests_invite_code_key
            // unique constraint since that code already belonged to the
            // senior's nest. Now always fresh, and retries on an actual DB
            // collision too (a 6-digit space is finite; better to handle a
            // genuine collision gracefully than assume fresh generation
            // alone is bulletproof forever as the nest count grows).
            final nestName = prefs.getString('nest_name') ?? 'My Family';
            String? nestId;
            for (int attempt = 0; attempt < 5 && nestId == null; attempt++) {
              final digits = (100000 + Random().nextInt(900000)).toString();
              final inviteCode = 'NEST$digits';
              try {
                await supabase.from('nests').insert({
                  'name': nestName,
                  'created_by': effectiveUserId,
                  'invite_code': inviteCode,
                });
                await prefs.setString('invite_code', inviteCode);
                final nestResponse = await supabase
                    .from('nests')
                    .select('id')
                    .eq('created_by', effectiveUserId)
                    .eq('invite_code', inviteCode)
                    .single();
                nestId = nestResponse['id'] as String;
              } on PostgrestException catch (e) {
                if (e.code == '23505') {
                  // Collision on this specific code -- try again with a
                  // freshly generated one.
                  continue;
                }
                rethrow;
              }
            }
            if (nestId == null) {
              throw Exception('Could not generate a unique invite code after 5 attempts');
            }
            await prefs.setString('nest_id', nestId);
            print('NEST_DEBUG: nest created = $nestId');

            // Add as member
            await supabase.from('nest_members').upsert({
              'nest_id': nestId,
              'user_id': effectiveUserId,
            });
            print('NEST_DEBUG: nest_member added');
          }
        } catch (e) {
          print('NEST_DEBUG: error = $e');
          // Previously this only showed the SnackBar and let execution fall
          // through to the Home navigation below regardless -- meaning a
          // failed nest creation (e.g. an invite-code collision) still sent
          // the person to Home with no valid nest_id at all, silently
          // broken. senior_onboarding_screen already stops navigation on
          // this same failure; this redundant fallback path here didn't
          // match that, and was the reason a broken account could still
          // reach Home instead of staying put with a visible error.
          if (mounted) {
            setState(() {
              _isLoading = false;
              _isNavigatingHome = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('DEBUG: nest creation failed - $e'),
                duration: const Duration(seconds: 10),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      } else {
        print('NEST_DEBUG: nest already exists = $existingNestId');
      }
    } else {
      print('NEST_DEBUG: effectiveUserId still null in _navigateToHome');
    }

    if (mounted) {
      final elapsed = DateTime.now().difference(navigateStartTime);
      if (elapsed < BrandedTransitionScreen.minDisplayDuration) {
        await Future.delayed(BrandedTransitionScreen.minDisplayDuration - elapsed);
      }
    }
    if (mounted) {
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.familyFeedScreen,
        arguments: {'role': prefs.getString('user_role') ?? 'senior'},
      );
    }
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────
  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isAuthLoading = true;
      _authError = null;
    });
    final result = await AuthService.signInWithGoogle();
    if (!mounted) return;
    setState(() => _isAuthLoading = false);

    if (result.isCancelled) return;
    if (!result.isSuccess) {
      setState(() => _authError = result.errorMessage);
      return;
    }
    await _navigateToHome(userId: result.user?.id);
  }

  // ── Apple Sign-In ─────────────────────────────────────────────────────────
  Future<void> _handleAppleSignIn() async {
    setState(() {
      _isAuthLoading = true;
      _authError = null;
    });
    final result = await AuthService.signInWithApple();
    if (!mounted) return;
    setState(() => _isAuthLoading = false);

    if (result.isCancelled) return;
    if (!result.isSuccess) {
      setState(() => _authError = result.errorMessage);
      return;
    }
    await _navigateToHome(userId: result.user?.id);
  }

  // ── Email form ────────────────────────────────────────────────────────────
  void _showEmailAuthSheet({bool isSignIn = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EmailAuthSheet(
        isSignIn: isSignIn,
        onSuccess: ({String? userId}) {
          Navigator.pop(ctx);
          _navigateToHome(userId: userId);
        },
      ),
    );
  }

  // ── Auth bottom sheet ─────────────────────────────────────────────────────
  void _showCreateAccountSheet() {
    setState(() => _authError = null);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AuthOptionsSheet(
        isAuthLoading: _isAuthLoading,
        authError: _authError,
        onGoogleTap: () {
          Navigator.pop(ctx);
          _handleGoogleSignIn();
        },
        onAppleTap: () {
          Navigator.pop(ctx);
          _handleAppleSignIn();
        },
        onEmailSignUp: () {
          Navigator.pop(ctx);
          _showEmailAuthSheet(isSignIn: false);
        },
        onEmailSignIn: () {
          Navigator.pop(ctx);
          _showEmailAuthSheet(isSignIn: true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;

    // Shown for the whole duration of _navigateToHome's post-auth setup
    // work, not just the OAuth handshake -- see _isNavigatingHome above.
    if (_isNavigatingHome) {
      return const Scaffold(body: BrandedTransitionScreen());
    }

    // This screen is reached via pushReplacementNamed from either onboarding
    // flow, which removes that screen from the navigation stack entirely --
    // a plain Navigator.pop(context) here would have nothing to return to.
    // D Von reported being unable to get back off this screen at all; the
    // fix is to explicitly re-navigate to whichever onboarding screen sent
    // us here, tagged via the 'cameFrom' route argument set at both call
    // sites (senior_onboarding_screen.dart, family_onboarding_screen.dart).
    final args = ModalRoute.of(context)?.settings.arguments
        as Map<String, dynamic>?;
    final cameFrom = args?['cameFrom'] as String?;

    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFD),
      body: Stack(
        children: [
          Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFDFDFD), Color(0xFFF5F0E8)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? 60 : 28,
                vertical: 32,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isTablet ? 500 : 420),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        NestLogoWidget(size: isTablet ? 160.0 : 140.0),
                        SizedBox(height: isTablet ? 36 : 28),
                        // Main question
                        Text(
                          'Would you like to save your messages and stories?',
                          style: GoogleFonts.nunitoSans(
                            fontSize: isTablet ? 26 : 22,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF2C2417),
                            height: 1.3,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        // Warning card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3CD),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFD4AA00).withAlpha(120),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Color(0xFFD4AA00),
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Without creating an account, all your messages, stories, and activity will be lost when you close the app.',
                                  style: GoogleFonts.nunitoSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF5C4A00),
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 36),
                        // Auth error (shown if auth fails before sheet opens)
                        if (_authError != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0F0),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE05C5C).withAlpha(80),
                              ),
                            ),
                            child: Text(
                              _authError!,
                              style: GoogleFonts.nunitoSans(
                                fontSize: 13,
                                color: const Color(0xFFC0392B),
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        // Create Free Account button
                        SizedBox(
                          width: double.infinity,
                          height: 58,
                          child: ElevatedButton(
                            onPressed: (_isLoading || _isAuthLoading)
                                ? null
                                : _showCreateAccountSheet,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF5DA399),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 2,
                            ),
                            child: _isAuthLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.person_add_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Create Free Account',
                                        style: GoogleFonts.nunitoSans(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Sign-up options hint
                        Text(
                          'Sign up with Google, Apple, or email & password',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 13,
                            color: const Color(0xFF9E8E7E),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        // Continue as Guest button
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: OutlinedButton(
                            onPressed: (_isLoading || _isAuthLoading)
                                ? null
                                : _continueAsGuest,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: Color(0xFFCCC0B0),
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Color(0xFF5DA399),
                                    ),
                                  )
                                : Text(
                                    'Continue as Guest',
                                    style: GoogleFonts.nunitoSans(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF6B5E4E),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'You can always create an account later from your profile.',
                          style: GoogleFonts.nunitoSans(
                            fontSize: 12,
                            color: const Color(0xFFA8A090),
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: isTablet ? 60 : 20,
            child: GestureDetector(
              onTap: () {
                Navigator.pushReplacementNamed(
                  context,
                  cameFrom == 'senior'
                      ? AppRoutes.seniorOnboardingScreen
                      : AppRoutes.familyOnboardingScreen,
                );
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF5DA399).withAlpha(31),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFF5DA399),
                  size: 22,
                ),
              ),
            ),
          ),
          const KeyboardDoneBarOverlay(),
        ],
      ),
    );
  }
}

// ── Auth Options Bottom Sheet ─────────────────────────────────────────────────
class _AuthOptionsSheet extends StatelessWidget {
  const _AuthOptionsSheet({
    required this.isAuthLoading,
    required this.authError,
    required this.onGoogleTap,
    required this.onAppleTap,
    required this.onEmailSignUp,
    required this.onEmailSignIn,
  });

  final bool isAuthLoading;
  final String? authError;
  final VoidCallback onGoogleTap;
  final VoidCallback onAppleTap;
  final VoidCallback onEmailSignUp;
  final VoidCallback onEmailSignIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFDF9F4),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).padding.bottom + 32,
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
                color: const Color(0xFFDDD5C8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Create your account',
            style: GoogleFonts.nunitoSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF2C2417),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your messages and stories will be saved securely.',
            style: GoogleFonts.nunitoSans(
              fontSize: 13,
              color: const Color(0xFF9E8E7E),
            ),
          ),
          const SizedBox(height: 20),
          // Google button
          _buildSocialButton(
            onTap: isAuthLoading ? null : onGoogleTap,
            icon: SizedBox(
              width: 20,
              height: 20,
              child: CustomPaint(painter: _GoogleLogoPainter()),
            ),
            label: 'Continue with Google',
            bgColor: Colors.white,
            borderColor: const Color(0xFFDDD5C8),
            textColor: const Color(0xFF2C2417),
          ),
          const SizedBox(height: 8),
          // Apple button
          _buildSocialButton(
            onTap: isAuthLoading ? null : onAppleTap,
            icon: const Icon(Icons.apple, color: Colors.white, size: 20),
            label: 'Continue with Apple',
            bgColor: const Color(0xFF1C1C1E),
            borderColor: const Color(0xFF1C1C1E),
            textColor: Colors.white,
          ),
          const SizedBox(height: 8),
          // Email button
          _buildSocialButton(
            onTap: isAuthLoading ? null : onEmailSignUp,
            icon: const Icon(
              Icons.email_outlined,
              color: Color(0xFF5DA399),
              size: 20,
            ),
            label: 'Sign up with Email',
            bgColor: const Color(0xFF5DA399),
            borderColor: const Color(0xFF5DA399),
            textColor: Colors.white,
          ),
          const SizedBox(height: 14),
          // Sign in link
          Center(
            child: GestureDetector(
              onTap: isAuthLoading ? null : onEmailSignIn,
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.nunitoSans(
                    fontSize: 13,
                    color: const Color(0xFF9E8E7E),
                  ),
                  children: [
                    const TextSpan(text: 'Already have an account? '),
                    TextSpan(
                      text: 'Sign In',
                      style: GoogleFonts.nunitoSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF5DA399),
                        decoration: TextDecoration.underline,
                        decorationColor: const Color(0xFF5DA399),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialButton({
    required VoidCallback? onTap,
    required Widget icon,
    required String label,
    required Color bgColor,
    required Color borderColor,
    required Color textColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.nunitoSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Google logo painter ───────────────────────────────────────────────────────
class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double r = size.width / 2;

    final colors = [
      (const Color(0xFF4285F4), -0.1, 0.5),
      (const Color(0xFF34A853), 0.5, 1.1),
      (const Color(0xFFFBBC05), 1.1, 1.6),
      (const Color(0xFFEA4335), 1.6, 2.2),
    ];

    for (final c in colors) {
      final paint = Paint()
        ..color = c.$1
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.18;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.72),
        c.$2 * 3.14159,
        (c.$3 - c.$2) * 3.14159,
        false,
        paint,
      );
    }

    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(cx, cy - size.height * 0.18, r, size.height * 0.36),
      whitePaint,
    );

    final bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(cx, cy - size.height * 0.18, r * 0.72, size.height * 0.36),
      bluePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Email Auth Bottom Sheet ───────────────────────────────────────────────────
class _EmailAuthSheet extends StatefulWidget {
  const _EmailAuthSheet({required this.isSignIn, required this.onSuccess});
  final bool isSignIn;
  final Function({String? userId}) onSuccess;

  @override
  State<_EmailAuthSheet> createState() => _EmailAuthSheetState();
}

class _EmailAuthSheetState extends State<_EmailAuthSheet> {
  late bool _isSignIn;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _isSignIn = widget.isSignIn;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter your email and password.');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (!_isSignIn && password != _confirmPasswordController.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = _isSignIn
        ? await AuthService.signInWithEmail(email: email, password: password)
        : await AuthService.signUpWithEmail(email: email, password: password);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!result.isSuccess) {
      setState(() => _error = result.errorMessage);
      return;
    }

    // Pass user ID directly from signup response
    final userId = result.user?.id;
    print('NEST_DEBUG: signup response userId = ' + (userId ?? 'NULL'));
    widget.onSuccess(userId: userId);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFDF9F4),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
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
                  color: const Color(0xFFDDD5C8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _isSignIn ? 'Welcome back 👋' : 'Create your account',
              style: GoogleFonts.nunitoSans(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF2C2417),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _isSignIn
                  ? 'Sign in to your SeniorNest account.'
                  : 'Set up your family nest in minutes.',
              style: GoogleFonts.nunitoSans(
                fontSize: 13,
                color: const Color(0xFF9E8E7E),
              ),
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFE05C5C).withAlpha(80),
                  ),
                ),
                child: Text(
                  _error!,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 13,
                    color: const Color(0xFFC0392B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            // Email field
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                color: const Color(0xFF2C2417),
              ),
              decoration: InputDecoration(
                hintText: 'Email address',
                hintStyle: GoogleFonts.nunitoSans(
                  fontSize: 15,
                  color: const Color(0xFFBBAA99),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFDDD5C8)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFDDD5C8)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(0xFF5DA399),
                    width: 2,
                  ),
                ),
                prefixIcon: const Icon(
                  Icons.email_outlined,
                  color: Color(0xFF9E8E7E),
                  size: 20,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Password field
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: GoogleFonts.nunitoSans(
                fontSize: 15,
                color: const Color(0xFF2C2417),
              ),
              decoration: InputDecoration(
                hintText: 'Password',
                hintStyle: GoogleFonts.nunitoSans(
                  fontSize: 15,
                  color: const Color(0xFFBBAA99),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFDDD5C8)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFDDD5C8)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(0xFF5DA399),
                    width: 2,
                  ),
                ),
                prefixIcon: const Icon(
                  Icons.lock_outline_rounded,
                  color: Color(0xFF9E8E7E),
                  size: 20,
                ),
                suffixIcon: GestureDetector(
                  onTap: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  child: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFF9E8E7E),
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'Minimum 6 characters',
                style: GoogleFonts.nunitoSans(
                  fontSize: 12,
                  color: const Color(0xFF9E8E7E),
                ),
              ),
            ),
            if (!_isSignIn) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                style: GoogleFonts.nunitoSans(
                  fontSize: 15,
                  color: const Color(0xFF2C2417),
                ),
                decoration: InputDecoration(
                  hintText: 'Confirm password',
                  hintStyle: GoogleFonts.nunitoSans(
                    fontSize: 15,
                    color: const Color(0xFFBBAA99),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFDDD5C8)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFDDD5C8)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Color(0xFF5DA399),
                      width: 2,
                    ),
                  ),
                  prefixIcon: const Icon(
                    Icons.lock_outline_rounded,
                    color: Color(0xFF9E8E7E),
                    size: 20,
                  ),
                  suffixIcon: GestureDetector(
                    onTap: () => setState(() =>
                        _obscureConfirmPassword = !_obscureConfirmPassword),
                    child: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: const Color(0xFF9E8E7E),
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  'Minimum 6 characters',
                  style: GoogleFonts.nunitoSans(
                    fontSize: 12,
                    color: const Color(0xFF9E8E7E),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            // Submit button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5DA399),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _isSignIn ? 'Sign In' : 'Create Account',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            // Toggle sign-in / sign-up
            Center(
              child: GestureDetector(
                onTap: () => setState(() {
                  _isSignIn = !_isSignIn;
                  _error = null;
                }),
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.nunitoSans(
                      fontSize: 13,
                      color: const Color(0xFF9E8E7E),
                    ),
                    children: [
                      TextSpan(
                        text: _isSignIn
                            ? "Don't have an account? "
                            : 'Already have an account? ',
                      ),
                      TextSpan(
                        text: _isSignIn ? 'Sign Up' : 'Sign In',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF5DA399),
                          decoration: TextDecoration.underline,
                          decorationColor: const Color(0xFF5DA399),
                        ),
                      ),
                    ],
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
