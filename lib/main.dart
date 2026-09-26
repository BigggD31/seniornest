import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import './core/app_export.dart';
import './core/app_state.dart';
import './routes/app_routes.dart';
import './presentation/favs_screen/favs_screen.dart';
import './presentation/send_screen/send_screen.dart';
import './presentation/legacy_screen/legacy_screen.dart';
import './presentation/safety_screen/safety_screen.dart';
import './presentation/setup_screen/setup_screen.dart';
import './presentation/main_tab_shell/main_tab_shell.dart';
import './services/auth_service.dart';
import './services/supabase_service.dart';
import './services/push_service.dart';
import './services/activity_badge_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import './widgets/custom_error_widget.dart';
import './widgets/branded_transition_screen.dart';
import './presentation/splash_screen/splash_screen.dart';
import './presentation/splash_screen/branded_intro_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  try {
    await SupabaseService.initialize();
  } catch (e) {
    debugPrint('Failed to initialize Supabase: $e');
  }

  // Push notifications: Firebase must be initialized before anything
  // calls FirebaseMessaging.instance (PushService does, later, once a
  // signed-in session is confirmed). Non-fatal if this fails or if the
  // native config file isn't in place yet -- the rest of the app must
  // never be blocked by push setup being incomplete.
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Failed to initialize Firebase: $e');
    // Sep 12 2026: this catch was completely silent -- if Firebase init
    // ever fails, every later call to FirebaseMessaging.instance
    // (PushService.registerDeviceToken) fails right along with it,
    // before ever reaching iOS's actual permission API. That's
    // consistent with what D Von found: zero device tokens ever
    // registered, on any account, on any build, and no "Notifications"
    // row ever appearing in iOS Settings for this app at all -- which
    // only happens if the permission request never actually fires.
    // Logging this (fire-and-forget, matches the existing ROLE_DEBUG
    // pattern in save_messages_prompt_screen.dart) so the next real
    // device test tells us definitively whether this is where it's
    // breaking, instead of guessing again.
    try {
      await Supabase.instance.client.from('temp_debug_logs').insert({
        'tag': 'PUSH_DEBUG_FIREBASE_INIT',
        'message': 'Firebase.initializeApp() threw: $e',
      });
    } catch (_) {}
  }

  // Load persisted text size before first frame
  try {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? 'senior';
    final defaultSize = role == 'senior' ? 'Large' : 'Normal';
    final savedSize = prefs.getString('text_size') ?? defaultSize;
    appTextScaleNotifier.value = textSizeToScale(savedSize);
  } catch (_) {}

  bool hasShownError = false;

  // 🚨 CRITICAL: Custom error handling - DO NOT REMOVE
  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (!hasShownError) {
      hasShownError = true;

      // Reset flag after 3 seconds to allow error widget on new screens
      Future.delayed(Duration(seconds: 5), () {
        hasShownError = false;
      });

      return CustomErrorWidget(errorDetails: details);
    }
    return SizedBox.shrink();
  };

  // 🚨 CRITICAL: Device orientation lock - DO NOT REMOVE
  if (!kIsWeb) {
    Future.wait([
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    ]).then((value) {
      runApp(MyApp());
    });
  } else {
    runApp(MyApp());
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription? _sub;
  String _initialRoute = AppRoutes.splashScreen;
  bool _ready = false;
  // Aug 21 2026: D Von's direct ask -- grandma should be the literal
  // first thing on screen, unconditionally, for a genuinely new device,
  // with nothing in front of her at all, not even briefly. This is
  // resolved separately from (and much faster than) _ready/_resolveInitialRoute
  // below -- it's a single local boolean read, no network involved, so
  // it settles in milliseconds rather than however long the full
  // sign-in/entitlement/membership resolution takes. null = not
  // resolved yet (the only moment anything placeholder-like shows);
  // false = a device that's onboarded before, skip the intro sequence
  // entirely and fall through to the existing gated flow below, exactly
  // as before; true = never onboarded, show the intro sequence right
  // now, not gated behind _ready at all.
  bool? _shouldShowIntro;

  void _initDeepLinks() async {
    final appLinks = AppLinks();
    _sub = appLinks.uriLinkStream.listen((uri) {
      Supabase.instance.client.auth.getSessionFromUrl(uri);
    });
  }

  Future<void> _resolveShouldShowIntro() async {
    final prefs = await SharedPreferences.getInstance();
    // Aug 21 2026: fixed a real, deeper mistake -- this used to read
    // has_onboarded, which turned out to NOT be a "has this device ever
    // launched before" flag at all. It's account-scoped: it's already in
    // AuthService's account-switch clearing list, and it's also
    // deliberately reset to false elsewhere (banned-account handling in
    // save_messages_prompt_screen.dart). So every sign-out, account
    // switch, or account deletion reset it -- and the intro sequence
    // came back on the next launch, even on a device that had genuinely
    // seen it many times before. has_seen_intro_sequence is a new,
    // separate, deliberately device-scoped flag -- NOT included in any
    // account-clearing list anywhere, set exactly once the first time
    // the intro sequence actually finishes (see IntroSequenceScreen's
    // onComplete below), and never reset after that for any reason.
    final hasSeenIntro = prefs.getBool('has_seen_intro_sequence') ?? false;
    if (mounted) setState(() => _shouldShowIntro = !hasSeenIntro);
  }

  @override
  void initState() {
    super.initState();
    _resolveShouldShowIntro();
    _resolveInitialRoute();
    // _initDeepLinks(); // Removed: native Apple Sign-In doesn't need deep links
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // Polls briefly for the persisted Supabase session to finish restoring
  // after a cold start. A single fixed-length wait (this session's earlier
  // fix) wasn't long enough in all cases -- confirmed by testing: reopening
  // the app within ~5 seconds of closing it still hit the race and briefly
  // showed the subscribe screen, while waiting 30+ seconds before reopening
  // did not. That gap points to variable-length work (token refresh, a
  // cold network path) sometimes taking longer than a fixed short wait
  // can cover, not a wrong mechanism -- so this polls in short intervals
  // up to a real ceiling instead of guessing one fixed number.
  Future<String?> _waitForRestoredUserId() async {
    var userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) return userId;
    const pollInterval = Duration(milliseconds: 250);
    const maxWait = Duration(milliseconds: 2500);
    var waited = Duration.zero;
    while (waited < maxWait) {
      await Future.delayed(pollInterval);
      waited += pollInterval;
      userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) return userId;
    }
    return null;
  }

  // A subscription with no expiry recorded (lifetime/VIP) never expires;
  // everything else is checked against its expires_at against now, and
  // their estimated expiry. No row at all means never subscribed.
  //
  // Aug 27 2026: was checking ONLY the currently signed-in user's own
  // subscriptions row -- meaning family members, who are never expected
  // to personally pay (per the app's own onboarding text: "the person
  // who creates the Nest is the Nest Owner and pays the subscription"),
  // would get sent to the paywall themselves despite the actual Nest
  // Owner already having an active subscription covering everyone.
  // Confirmed via direct code read this was the real, live behavior --
  // nothing anywhere checked the owner's status on a member's behalf.
  // This is also the reason Nest Succession couldn't work correctly:
  // succession changes who nests.created_by points to, but the old
  // per-user-only check would never notice that change meant anything.
  //
  // Fixed: still checks the signed-in person's own subscription first
  // (fast path for the common case, and correctly preserves anyone who
  // personally redeemed their own VIP code independent of nest
  // ownership) -- only if that comes back empty does it look up who
  // actually owns their nest and check that person's subscription
  // instead. A newly-transferred owner who hasn't subscribed yet is
  // correctly NOT covered by either check, by design -- that's exactly
  // the signal that sends them to the subscribe screen after succession.
  Future<bool> _isCurrentlyEntitled(SharedPreferences prefs) async {
    try {
      final userId = await _waitForRestoredUserId();
      if (userId == null) return false;

      if (await _hasActiveSubscriptionRow(userId)) return true;

      final nestId = prefs.getString('nest_id') ?? '';
      if (nestId.isEmpty) return false;
      final nest = await Supabase.instance.client
          .from('nests')
          .select('created_by')
          .eq('id', nestId)
          .maybeSingle();
      final ownerId = nest?['created_by'] as String?;
      if (ownerId == null || ownerId == userId) return false;
      return await _hasActiveSubscriptionRow(ownerId);
    } catch (e) {
      debugPrint('ENTITLEMENT_CHECK_ERROR: $e');
      // Fail open on a network/error blip rather than locking someone out
      // due to a connectivity hiccup at launch.
      return true;
    }
  }

  // Aug 27 2026: was a direct table select, which only works for a
  // person's OWN row -- confirmed via RLS check that subscriptions only
  // allows auth.uid() = user_id, so this would have silently returned
  // nothing for every family member checking their nest owner's status,
  // making the whole fix above a no-op for the exact population it's
  // meant to help. Uses the same SECURITY DEFINER RPC pattern already
  // proven for the ban checks -- returns only a boolean, never exposes
  // anyone's actual subscription details to someone who isn't them.
  Future<bool> _hasActiveSubscriptionRow(String userId) async {
    final result = await Supabase.instance.client
        .rpc('is_user_entitled', params: {'p_user_id': userId});
    return result == true;
  }

  // Confirms the locally cached nest_id is still a real membership in
  // Supabase. A removed member's device keeps its old cached nest_id --
  // this is what actually catches that instead of trusting the cache.
  Future<bool> _hasValidNestMembership(SharedPreferences prefs) async {
    try {
      final userId = await _waitForRestoredUserId();
      final nestId = prefs.getString('nest_id') ?? '';
      if (userId == null || nestId.isEmpty) return false;
      final row = await Supabase.instance.client
          .from('nest_members')
          .select('nest_id')
          .eq('nest_id', nestId)
          .eq('user_id', userId)
          .maybeSingle();
      return row != null;
    } catch (e) {
      debugPrint('NEST_MEMBERSHIP_CHECK_ERROR: $e');
      // Fail open on a network/error blip, same reasoning as the
      // entitlement check -- don't lock someone out over connectivity.
      return true;
    }
  }

  // Sep 11 2026: added alongside the _resolveInitialRoute fix above --
  // looks up whether the signed-in user already has a real nest
  // membership on the server, for the case where local cache (a fresh
  // install or a new device) has none at all. Picks the OLDEST
  // membership on purpose: the exact bug this closes had already left
  // some real accounts with several nests -- the earliest one is the
  // one most likely to be the person's real, original nest rather than
  // one of the accidental duplicates. Restores just enough local state
  // for the rest of the app to treat this as an ordinary returning user.
  Future<bool> _tryRestoreServerMembership(
    SharedPreferences prefs,
    String userId,
  ) async {
    try {
      final rows = await Supabase.instance.client
          .from('nest_members')
          .select('nest_id, joined_at, nests(name, invite_code, created_by)')
          .eq('user_id', userId)
          .order('joined_at', ascending: true)
          .limit(1);
      if (rows.isEmpty) return false;
      final row = rows.first;
      final nestId = row['nest_id'] as String?;
      final nest = row['nests'] as Map<String, dynamic>?;
      if (nestId == null || nest == null) return false;

      await prefs.setString('nest_id', nestId);
      final nestName = nest['name'] as String?;
      if (nestName != null && nestName.isNotEmpty) {
        await prefs.setString('nest_name', nestName);
      }
      final inviteCode = nest['invite_code'] as String?;
      if (inviteCode != null && inviteCode.isNotEmpty) {
        await prefs.setString('invite_code', inviteCode);
      }
      final createdBy = nest['created_by'] as String?;
      await prefs.setBool('joined_via_invite', createdBy != userId);
      await prefs.setBool('has_onboarded', true);
      await prefs.setBool('onboarding_complete', true);
      return true;
    } catch (e) {
      debugPrint('SERVER_MEMBERSHIP_RESTORE_ERROR: $e');
      // Fail CLOSED here, unlike the entitlement/membership checks above
      // -- if a real membership can't be confirmed, falling through to
      // the existing roleChoiceScreen path is the safe default, not
      // silently trusting an unconfirmed restore.
      return false;
    }
  }

  Future<void> _resolveInitialRoute() async {
    // Sep 26 2026: timed the same way save_messages_prompt_screen.dart's
    // post-signup gate already times its own version of this -- captured
    // before any of the real work below, so the minimum-display check at
    // the bottom of this function measures the actual wall-clock time this
    // screen has been on screen, not just the async work's own duration.
    final routeResolveStartTime = DateTime.now();
    var isSignedInForWarmEntranceTiming = false;
    try {
      // Must run before anything else in this function, including the
      // dark_mode read two lines down -- detects a genuine account switch
      // on this device (e.g. the app was relaunched under a different
      // persisted session) and wipes every locally cached piece of
      // account-specific data before it can be applied stale.
      await AuthService.clearStaleAccountDataIfUserChanged();

      final prefs = await SharedPreferences.getInstance();

      // Aug 31 2026: this used to be ~100 lines resolving each notifier
      // inline, one at a time -- extracted to a shared function
      // (app_state.dart's resolveAppNotifiersFromPrefs) so the exact same
      // resolution logic can also run on a warm account switch, not just
      // here at cold start. See that function's comment for the full
      // reasoning (Pre-Ship Audit 1: cross-session state).
      await resolveAppNotifiersFromPrefs(prefs);

      final hasOnboarded = prefs.getBool('has_onboarded') ?? false;
      // This is the TRUE origin of the subscribe-screen flash and the
      // "Home flashes twice" jitter, not just the entitlement check below.
      // AuthService.isSignedIn is a raw, instant, unprotected read of
      // currentUser -- checked here BEFORE _waitForRestoredUserId() ever
      // gets a chance to run downstream. On a fast reopen, if the session
      // hasn't finished restoring at this exact synchronous instant, this
      // was false even for an actually-signed-in person, sending the whole
      // branch below to the splashScreen route instead -- which ALSO ran
      // its own independent, competing session check on mount
      // (splash_screen.dart's _checkExistingSession), with no entitlement
      // check of its own, and its own navigation to Home. Two uncoordinated
      // deciders racing against each other, each capable of navigating on
      // their own, is why the visible sequence was different every time
      // depending on which one's timing won. Awaiting the restored session
      // HERE, at the actual point of origin, means this branch is decided
      // correctly the first time and splash_screen's competing path (fixed
      // separately) never has a real session left to find.
      // Sep 11 2026: check the real session instantly, first, regardless
      // of hasOnboarded. Supabase's own session (iOS Keychain) can
      // survive a fresh app install/reinstall while SharedPreferences
      // (where has_onboarded lives) cannot -- so a real, already-
      // onboarded returning user on a new device, or after a reinstall/
      // TestFlight update, was previously assumed to have "definitely
      // never signed in" purely because hasOnboarded was false locally,
      // and got routed to the brand-new-user splash/intro sequence
      // instead. Confirmed directly: two real accounts hit exactly this
      // path today. This instant check costs nothing (currentUser is a
      // synchronous read) and resolves that case correctly without
      // touching the polling wait below at all.
      final instantUserId = Supabase.instance.client.auth.currentUser?.id;
      final isSignedIn = instantUserId != null
          ? true
          : hasOnboarded
              ? await _waitForRestoredUserId() != null
              // Aug 21 2026: D Von's wife saw a 5-6s black screen before the
              // grandmother photo on her first-ever launch. Root cause: this
              // wait polls for up to 2.5s waiting for a session to restore --
              // legitimately needed for a RETURNING user whose session might
              // still be loading, but on a device that has never onboarded at
              // all, there is definitively no session that could ever be
              // found, so the full 2.5s always ran to completion for nothing.
              // hasOnboarded is already read locally and instantly just above
              // -- skipping the wait when it's false only affects devices
              // that have never signed in before, exactly the population
              // about to see the intro sequence anyway. Anyone who HAS
              // onboarded before still gets the full wait, completely
              // unchanged, so the original fix this protects stays intact.
              // The instant check above now catches the one real gap this
              // left (a Keychain-restored session with no local flag) before
              // ever reaching this fallback.
              : false;
      // Sep 26 2026: only the warm, already-signed-in relaunch is what
      // was flashing -- a genuinely new/signed-out device still lands on
      // splash_screen (or the intro sequence) exactly as fast as it
      // always has, unchanged.
      isSignedInForWarmEntranceTiming = isSignedIn;

      if (isSignedIn && hasOnboarded) {
        // Signed in and onboarded -- but only let them straight into the
        // app if they're currently entitled. Previously this went straight
        // to Home regardless of subscription status, since nothing
        // anywhere checked it.
        final entitled = await _isCurrentlyEntitled(prefs);
        if (!entitled) {
          _initialRoute = AppRoutes.subscribeNestScreen;
        } else {
          // Also verify the cached nest_id is still a real membership.
          // Previously, removing someone from a nest only deleted their
          // Supabase row -- their own device still had "signed in +
          // onboarded" cached locally, so they'd sail straight back into
          // the nest they were just removed from. This re-checks the real
          // membership every launch instead of trusting stale local state.
          final stillAMember = await _hasValidNestMembership(prefs);
          if (stillAMember) {
            _initialRoute = AppRoutes.familyFeedScreen;
          } else {
            await prefs.remove('nest_id');
            await prefs.setBool('has_onboarded', false);
            await prefs.setBool('onboarding_complete', false);
            // Also clear the cached invite code state -- there are a few
            // other screens (onboarding, save-messages-prompt) that will
            // silently re-join a nest from a cached invite code with no
            // awareness of whether this person was just removed. Since the
            // invite code itself is never invalidated after use, clearing
            // it here is what actually closes that loophole, rather than
            // patching each of those rejoin code paths individually.
            await prefs.remove('invite_code');
            await prefs.setBool('joined_via_invite', false);
            _initialRoute = AppRoutes.roleChoiceScreen;
          }
        }
      } else if (isSignedIn && !hasOnboarded) {
        // Sep 11 2026: previously assumed "signed in, but no
        // has_onboarded flag locally" always meant a genuinely brand-new
        // user, and sent them straight into onboarding. Paired with the
        // instant-session-check fix above, this is the other half of the
        // same real gap: a real, already-onboarded returning user on a
        // new device or after a reinstall has no local cache to prove
        // it, and got routed into onboarding -- where completing it (even
        // by quickly tapping through screens that look like ordinary
        // loading) creates a brand-new duplicate nest and overwrites
        // their real profile name. Confirmed via direct DB query: two
        // real accounts had exactly this happen today. Now checks the
        // server directly for an actual existing nest_members row before
        // ever assuming "new" -- a real membership found there is
        // restored locally and sent straight to their feed, skipping
        // onboarding entirely. Only someone with no server-side
        // membership either still goes to roleChoiceScreen.
        final restoredUserId = instantUserId ?? await _waitForRestoredUserId();
        final restored = restoredUserId != null
            ? await _tryRestoreServerMembership(prefs, restoredUserId)
            : false;
        if (restored) {
          await resolveAppNotifiersFromPrefs(prefs);
          _initialRoute = AppRoutes.familyFeedScreen;
        } else {
          _initialRoute = AppRoutes.roleChoiceScreen;
        }
      } else {
        // Not signed in → start at splash screen (original first screen)
        _initialRoute = AppRoutes.splashScreen;
      }
      // Fire-and-forget -- covers a returning, already-signed-in launch.
      // A brand new sign-in (any of the four onboarding flows) is
      // covered separately, at the point onboarding actually completes
      // (save_messages_prompt_screen.dart), since this function only
      // ever runs once, at cold start.
      if (isSignedIn) {
        PushService.registerDeviceToken();
        ActivityBadgeService.initialize();
      }
    } catch (_) {
      _initialRoute = AppRoutes.splashScreen;
    }
    // Aug 21 2026: removed the artificial minDisplayDuration wait here for
    // the NOT-signed-in/intro-photo path. It existed to keep the OLD gold
    // logo screen visible for a consistent minimum time regardless of
    // connection speed -- but that gate no longer shows that screen, it
    // shows the grandmother photo now, and the real IntroSequenceScreen
    // (once _ready flips) starts its own fresh timer on the same image.
    // An artificial wait here would only add a guaranteed extra pause
    // plus a visible timer-restart before that real, interactive slide
    // ever got a chance to begin -- exactly the stutter D Von was seeing.
    // That reasoning never applied to a WARM, already-signed-in relaunch
    // though -- that path never shows the intro photos at all (see
    // _shouldShowIntro), so there's no second timer to double up with.
    // Sep 26 2026: on build 264, that warm path had gotten fast enough
    // (cache warm, no real network wait) that this branded logo screen
    // was only on screen for 0.5-1s, reading as a flash rather than an
    // intentional brand moment -- D Von's direct ask. This restores a
    // floor under that one case only, using the same shared constant the
    // post-signup gate in save_messages_prompt_screen.dart already
    // enforces the same way (see that file's _navigateToHome), so both
    // "moments the branded logo carries the whole screen" now agree.
    // Crucially, this is a floor UNDER real resolution, not a fixed
    // delay in place of it -- _initialRoute above is already fully
    // resolved (sign-in, entitlement, nest membership, notifiers all
    // seeded) by the time this runs, so extending the logo's visibility
    // never releases to a skeleton/placeholder Home underneath it; it
    // only means Home is fully painted and waiting behind the logo for
    // whatever's left of the 2.5s, instead of swapping in the instant
    // resolution finishes.
    if (isSignedInForWarmEntranceTiming) {
      final elapsed = DateTime.now().difference(routeResolveStartTime);
      if (elapsed < BrandedTransitionScreen.minDisplayDuration) {
        await Future.delayed(BrandedTransitionScreen.minDisplayDuration - elapsed);
      }
    }
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    // Aug 21 2026: D Von's direct ask -- grandma should be the literal
    // first thing on screen for a new device, unconditionally, with
    // nothing in front of her at all, not even briefly. _shouldShowIntro
    // resolves separately and much faster than _ready below (a single
    // local boolean read, no network) -- once it's known true, the intro
    // sequence starts showing immediately, without waiting for the rest
    // of _resolveInitialRoute() to finish.
    //
    // Important correction from an earlier version of this: this does
    // NOT hardcode where the intro leads afterward. has_seen_intro_sequence
    // is a brand new flag, so it reads false on EVERY device that's ever
    // used this app before today too -- including an already fully
    // signed-in device. Hardcoding the destination to the plain pitch
    // screen would have sent an existing, signed-in user to the
    // marketing pitch instead of their actual nest on this one
    // transitional launch. Instead, the intro's builder callback below
    // consults the real, genuinely resolved _ready/_initialRoute once
    // the photos finish -- exactly the same destination a returning user
    // would get, just reached after the intro instead of before it. The
    // intro screens themselves (grandma, family photo) don't read any of
    // the app-wide notifiers _resolveInitialRoute() sets, and by the
    // time someone's actually watched or tapped through both photos,
    // that resolution has almost always already finished in the
    // background regardless.
    if (_shouldShowIntro == true) {
      return _buildRealApp(
        home: IntroSequenceScreen(
          imagePaths: const [
            'assets/images/splash_hero_1.png',
            'assets/images/splash_hero_2.png',
          ],
          builder: (context) {
            if (!_ready) {
              // Resolution genuinely isn't done yet even though both
              // photos finished -- rare, given resolution runs the whole
              // time the photos are on screen, but handled gracefully:
              // same gold logo bridges the gap, not a different or
              // jarring placeholder. This rebuilds automatically once
              // _ready flips, via the same setState in
              // _resolveInitialRoute().
              return const BrandedTransitionScreen();
            }
            // Resolves to whatever _resolveInitialRoute() genuinely
            // concluded -- the real pitch screen for a genuinely new
            // sign-out, but a returning-yet-never-seen-the-intro
            // device's own nest, subscribe screen, or role choice
            // exactly as it would have gotten without the intro at all.
            // Built directly here (already inside this MaterialApp's own
            // Navigator/theme scope via home:), not as a second nested
            // MaterialApp. Uses _resolveRouteWidget rather than a direct
            // AppRoutes.routes[...] lookup -- found while double-checking
            // this that familyFeedScreen (a very common destination for
            // an already-signed-in device) isn't in that static map at
            // all, it's one of six screens handled separately via
            // onGenerateRoute below. A direct lookup would have thrown a
            // null-check crash for exactly that common case.
            return _resolveRouteWidget(_initialRoute, context);
          },
        ),
      );
    }
    if (_shouldShowIntro == null || !_ready) {
      // Aug 21 2026: D Von's direct correction -- restored the real gold
      // logo (BrandedTransitionScreen) here, not a plain gradient. The
      // gradient was only ever meant to replace the BLACK flash that
      // happened specifically because a real photo needed to decode
      // behind a black-background Scaffold -- it was never meant to
      // replace the logo everywhere else in the app. This screen draws
      // the logo with code (shapes and gradients, no image file, nothing
      // to decode), so that black-flash problem never applied here in
      // the first place -- this can safely show instantly, exactly as
      // it always did before any of today's changes.
      //
      // This now only shows for two much narrower cases than before:
      // (1) the brief moment before _shouldShowIntro itself is known (a
      // single local read, milliseconds) and (2) a RETURNING device
      // (_shouldShowIntro == false) waiting on the full sign-in/
      // entitlement/membership resolution -- which never shows the
      // intro photos at all, exactly as before.
      return const BrandedTransitionScreen();
    }
    return _buildRealApp(initialRoute: _initialRoute);
  }

  // Aug 21 2026: shared by the intro sequence's post-photos destination
  // and (implicitly, via the same six-screen list) onGenerateRoute below.
  // _initialRoute can be any of the four values _resolveInitialRoute()
  // assigns (splashScreen, roleChoiceScreen, subscribeNestScreen,
  // familyFeedScreen) -- the first three are in AppRoutes.routes, but
  // familyFeedScreen (a very common destination for an already-signed-in
  // device) is only handled via onGenerateRoute's switch, not the static
  // map. Checks the static map first, falls back to the same six-screen
  // switch onGenerateRoute uses, so this never crashes regardless of
  // which of the two systems the resolved route actually lives in.
  // Sep 24 2026: familyFeedScreen means "go to Home" by name -- but
  // appActiveTabNotifier is a persistent, session-wide value, so without
  // this reset, navigating here while the notifier is sitting on some
  // other tab (e.g. after using Setup) opens the shell showing that other
  // tab instead of Home. Confirmed bug: adding a family member via Setup
  // was landing back on Setup instead of Home for exactly this reason.
  Widget _openShellOnHome() {
    appActiveTabNotifier.value = 0;
    return const MainTabShell();
  }

  Widget _resolveRouteWidget(String routeName, BuildContext context) {
    final staticBuilder = AppRoutes.routes[routeName];
    if (staticBuilder != null) return staticBuilder(context);
    final Widget? page = switch (routeName) {
      // Sep 24 2026: familyFeedScreen is the one route name every real
      // entry point (sign-out, onboarding completion, message-save
      // prompts, subscribe-screen return) actually targets -- now opens
      // MainTabShell, which keeps all six tabs alive, instead of the bare
      // screen. The other five mappings below are unreachable dead code
      // as of this change (confirmed via grep -- only messages_inbox_screen.dart
      // references them, and that screen itself is unreachable from
      // anywhere in the current app) but left as a defensive fallback.
      AppRoutes.familyFeedScreen => _openShellOnHome(),
      AppRoutes.sendScreen => const SendScreen(),
      AppRoutes.legacyScreen => const LegacyScreen(),
      AppRoutes.favsScreen => const FavsScreen(),
      AppRoutes.safetyScreen => const SafetyScreen(),
      AppRoutes.setupScreen => const SetupScreen(),
      _ => null,
    };
    // Shouldn't happen -- _initialRoute is always one of the known
    // values above -- but falls back to the plain pitch screen rather
    // than crashing if something unexpected ever reaches this.
    return page ?? const SplashScreen();
  }

  Widget _buildRealApp({String? initialRoute, Widget? home}) {
    assert(
      (initialRoute == null) != (home == null),
      'Provide exactly one of initialRoute or home',
    );
    // Sep 23 2026: found on Android's very first genuinely fresh
    // install/emulator (Claude Code, overnight) -- a brand-new device
    // that's never set has_seen_intro_sequence calls this with `home`
    // set to the intro screens, while routes below is always passed
    // unconditionally and includes an entry for the exact key '/'
    // (AppRoutes.initial). Flutter's MaterialApp explicitly forbids
    // providing both `home` and a routes entry for '/' at the same
    // time -- an assertion failure, not a soft warning. Purely a gap in
    // the shared Dart code, never exercised before since no test
    // account on any platform had ever hit a truly fresh install with
    // this flag unset until last night's first-ever clean Android
    // emulator. Same standing risk on iOS for the identical rare case,
    // just never actually triggered there yet.
    // Fix: when `home` is in use, pass a copy of the routes map with
    // only the '/' key removed -- every other named route stays
    // available for when initialRoute is used instead, on every other
    // call to this same function.
    final effectiveRoutes = home != null
        ? (Map<String, WidgetBuilder>.from(AppRoutes.routes)
          ..remove(AppRoutes.initial))
        : AppRoutes.routes;
    return Sizer(
      builder: (context, orientation, screenType) {
        return ValueListenableBuilder<bool>(
          valueListenable: appDarkModeNotifier,
          builder: (context, isDark, child) {
            return ValueListenableBuilder<double>(
              valueListenable: appTextScaleNotifier,
              builder: (context, scale, child) {
                return MaterialApp(
                  title: 'seniornest',
                  theme: AppTheme.lightTheme,
                  darkTheme: AppTheme.darkTheme,
                  themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
                  // 🚨 CRITICAL: NEVER REMOVE OR MODIFY
                  builder: (context, child) {
                    return MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    );
                  },
                  // 🚨 END CRITICAL SECTION
                  debugShowCheckedModeBanner: false,
                  routes: effectiveRoutes,
                  // App-wide fade + gentle lift transition for all six
                  // bottom-nav screens (Aug 5 2026), replacing whatever
                  // each screen's platform default happened to be. D Von
                  // tested this in isolation on Favs first and confirmed
                  // he wants it as the standard everywhere.
                  onGenerateRoute: (settings) {
                    final Widget? page = switch (settings.name) {
                      // Sep 24 2026: see the matching comment in
                      // _resolveRouteWidget above.
                      AppRoutes.familyFeedScreen => _openShellOnHome(),
                      AppRoutes.sendScreen => const SendScreen(),
                      AppRoutes.legacyScreen => const LegacyScreen(),
                      AppRoutes.favsScreen => const FavsScreen(),
                      AppRoutes.safetyScreen => const SafetyScreen(),
                      AppRoutes.setupScreen => const SetupScreen(),
                      _ => null,
                    };
                    if (page == null) return null;
                    return PageRouteBuilder(
                      settings: settings,
                      transitionDuration: const Duration(milliseconds: 350),
                      reverseTransitionDuration:
                          const Duration(milliseconds: 350),
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          page,
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                        // True simultaneous crossfade -- previously this was
                        // staged (old page fades out over the first 30% of
                        // the duration, THEN the new page fades in over the
                        // remaining 70%), which read as two distinct events
                        // with a gap in the middle rather than one smooth
                        // motion. Now both curves span the FULL duration so
                        // the outgoing and incoming page dissolve into each
                        // other at the same time. A themed backdrop
                        // Container (matching the live light/dark scaffold
                        // color) sits underneath both layers so even where
                        // they briefly overlap, it never reveals a flash of
                        // the platform's default white -- which is what
                        // read as a "bright light" shock in a dark room.
                        final incomingCurve = CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeInOut,
                        );
                        final outgoingCurve = CurvedAnimation(
                          parent: secondaryAnimation,
                          curve: Curves.easeInOut,
                        );
                        return Container(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: FadeTransition(
                            opacity: Tween<double>(
                              begin: 1.0,
                              end: 0.0,
                            ).animate(outgoingCurve),
                            child: FadeTransition(
                              opacity: incomingCurve,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.015),
                                  end: Offset.zero,
                                ).animate(incomingCurve),
                                child: child,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                  initialRoute: initialRoute,
                  home: home,
                );
              },
            );
          },
        );
      },
    );
  }
}
