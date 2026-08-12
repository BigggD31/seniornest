import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import './core/app_export.dart';
import './core/app_state.dart';
import './routes/app_routes.dart';
import './presentation/favs_screen/favs_screen.dart';
import './presentation/family_feed_screen/family_feed_screen.dart';
import './presentation/send_screen/send_screen.dart';
import './presentation/legacy_screen/legacy_screen.dart';
import './presentation/safety_screen/safety_screen.dart';
import './presentation/setup_screen/setup_screen.dart';
import './services/auth_service.dart';
import './services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import './widgets/custom_error_widget.dart';
import './widgets/branded_transition_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  try {
    await SupabaseService.initialize();
  } catch (e) {
    debugPrint('Failed to initialize Supabase: $e');
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

  void _initDeepLinks() async {
    final appLinks = AppLinks();
    _sub = appLinks.uriLinkStream.listen((uri) {
      Supabase.instance.client.auth.getSessionFromUrl(uri);
    });
  }

  @override
  void initState() {
    super.initState();
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
  Future<bool> _isCurrentlyEntitled() async {
    try {
      final userId = await _waitForRestoredUserId();
      if (userId == null) return false;
      final row = await Supabase.instance.client
          .from('subscriptions')
          .select('status, expires_at')
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) return false;
      if (row['status'] == 'lifetime') return true;
      final expiresAt = row['expires_at'] as String?;
      if (expiresAt == null) return false;
      return DateTime.parse(expiresAt).isAfter(DateTime.now());
    } catch (e) {
      debugPrint('ENTITLEMENT_CHECK_ERROR: $e');
      // Fail open on a network/error blip rather than locking someone out
      // due to a connectivity hiccup at launch.
      return true;
    }
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

  Future<void> _resolveInitialRoute() async {
    final startTime = DateTime.now();
    try {
      // Must run before anything else in this function, including the
      // dark_mode read two lines down -- detects a genuine account switch
      // on this device (e.g. the app was relaunched under a different
      // persisted session) and wipes every locally cached piece of
      // account-specific data before it can be applied stale.
      await AuthService.clearStaleAccountDataIfUserChanged();

      final prefs = await SharedPreferences.getInstance();
      // Load persisted dark mode preference; if never set, follow system brightness
      final savedDarkMode = prefs.getBool('dark_mode');
      if (savedDarkMode != null) {
        appDarkModeNotifier.value = savedDarkMode;
      } else {
        // Default: follow system setting (light by default on most devices)
        final brightness =
            SchedulerBinding.instance.platformDispatcher.platformBrightness;
        appDarkModeNotifier.value = brightness == Brightness.dark;
      }

      // Resolved once here, before any screen ever builds -- see the
      // comment on appNestNameNotifier in app_state.dart for the full
      // reasoning. Once someone has named their nest, every screen should
      // show that name instantly, every time, with zero wait regardless
      // of connection speed.
      final savedNestName = prefs.getString('nest_name');
      if (savedNestName != null && savedNestName.isNotEmpty) {
        appNestNameNotifier.value = savedNestName;
      }

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
      final isSignedIn = await _waitForRestoredUserId() != null;

      if (isSignedIn && hasOnboarded) {
        // Signed in and onboarded -- but only let them straight into the
        // app if they're currently entitled. Previously this went straight
        // to Home regardless of subscription status, since nothing
        // anywhere checked it.
        final entitled = await _isCurrentlyEntitled();
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
        // Signed in but not yet onboarded → resume onboarding from role choice
        _initialRoute = AppRoutes.roleChoiceScreen;
      } else {
        // Not signed in → start at splash screen (original first screen)
        _initialRoute = AppRoutes.splashScreen;
      }
    } catch (_) {
      _initialRoute = AppRoutes.splashScreen;
    }
    final elapsed = DateTime.now().difference(startTime);
    // Confirmed the actual remaining complaint after the subscribe-screen
    // race itself was fixed: display duration was inconsistent -- a fast
    // connection could resolve everything in a couple hundred
    // milliseconds, barely long enough to register, while a slow one
    // could take much longer. This applies to every reopen regardless of
    // how long the app was in the background -- a second, an hour, a day
    // -- since nothing in this app signs someone out on its own; only an
    // explicit sign-out does that.
    if (elapsed < BrandedTransitionScreen.minDisplayDuration) {
      await Future.delayed(BrandedTransitionScreen.minDisplayDuration - elapsed);
    }
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    // Previously this showed only a plain solid color matching dark/light
    // mode (this session's earlier fix for the black-screen flash). Now
    // shows the actual approved branded transition screen instead, so a
    // cold start (including the OS fully suspending and relaunching the
    // app, which looks identical to a fresh launch from here) reads as an
    // intentional "loading" moment rather than a blank flash.
    if (!_ready) {
      return const BrandedTransitionScreen();
    }
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
                  routes: AppRoutes.routes,
                  // App-wide fade + gentle lift transition for all six
                  // bottom-nav screens (Aug 5 2026), replacing whatever
                  // each screen's platform default happened to be. D Von
                  // tested this in isolation on Favs first and confirmed
                  // he wants it as the standard everywhere.
                  onGenerateRoute: (settings) {
                    final Widget? page = switch (settings.name) {
                      AppRoutes.familyFeedScreen => const FamilyFeedScreen(),
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
                  initialRoute: _initialRoute,
                );
              },
            );
          },
        );
      },
    );
  }
}
