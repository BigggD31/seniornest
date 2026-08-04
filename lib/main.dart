import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import './core/app_export.dart';
import './core/app_state.dart';
import './routes/app_routes.dart';
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

  Future<void> _resolveInitialRoute() async {
    try {
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
        _initialRoute = entitled
            ? AppRoutes.familyFeedScreen
            : AppRoutes.subscribeNestScreen;
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
    if (!_ready) return const SizedBox.shrink();
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
