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

  // Checks whether the signed-in user currently has access. Lifetime/promo
  // entitlements never expire; regular subscriptions are checked against
  // their estimated expiry. No row at all means never subscribed.
  Future<bool> _isCurrentlyEntitled() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
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
      final userId = Supabase.instance.client.auth.currentUser?.id;
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

      final hasOnboarded = prefs.getBool('has_onboarded') ?? false;
      final isSignedIn = AuthService.isSignedIn;

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
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    // SizedBox.shrink() paints nothing at all -- no background color -- so
    // while _resolveInitialRoute()'s async work (auth check, entitlement
    // check, nest membership check) is still running, Flutter's raw
    // default canvas showed through instead of any real background. On a
    // cold start (including the OS fully suspending and relaunching the
    // app, which looks identical to a fresh launch from here) that's a
    // visible black screen before the real UI ever paints. Wrapped in a
    // ValueListenableBuilder so it matches the resolved dark/light setting
    // as soon as that's available, rather than an unthemed default.
    if (!_ready) {
      return ValueListenableBuilder<bool>(
        valueListenable: appDarkModeNotifier,
        builder: (context, isDark, child) {
          return Directionality(
            textDirection: TextDirection.ltr,
            child: ColoredBox(
              color: isDark ? const Color(0xFF1A1712) : Colors.white,
            ),
          );
        },
      );
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
