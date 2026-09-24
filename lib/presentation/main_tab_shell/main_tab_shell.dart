import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../family_feed_screen/family_feed_screen.dart';
import '../send_screen/send_screen.dart';
import '../legacy_screen/legacy_screen.dart';
import '../safety_screen/safety_screen.dart';
import '../favs_screen/favs_screen.dart';
import '../setup_screen/setup_screen.dart';

/// Sep 24 2026: replaces the old model where every bottom-nav tap called
/// Navigator.pushReplacementNamed and destroyed + rebuilt the destination
/// screen from scratch -- the confirmed root cause (via git archaeology,
/// see engineering-learnings.md) behind both the Aug 6 animation-replay
/// bug and the flash-of-placeholder pattern reported since. All six tab
/// screens are direct IndexedStack children here, built once and kept
/// alive for the life of the app process; only the active one is visible.
/// Each screen keeps its own Scaffold/AppNavigation exactly as before --
/// this widget doesn't have its own Scaffold, and doesn't touch any
/// screen's internals beyond how _onNavTap decides to switch tabs (see the
/// matching Sep 24 2026 comment in family_feed_screen.dart and the other
/// five screens).
///
/// Tab switches happen by writing to appActiveTabNotifier (app_state.dart)
/// instead of navigating -- this widget just listens and swaps which
/// child IndexedStack shows.
class MainTabShell extends StatefulWidget {
  const MainTabShell({super.key});

  @override
  State<MainTabShell> createState() => _MainTabShellState();
}

class _MainTabShellState extends State<MainTabShell> {
  // Built once and never recreated -- this list existing at all is the
  // point. IndexedStack keeps every child mounted regardless of which is
  // visible, so each screen's own state (controllers, loaded data,
  // realtime subscriptions) survives every tab switch instead of being
  // torn down and rebuilt.
  static const List<Widget> _tabs = [
    FamilyFeedScreen(),
    SendScreen(),
    LegacyScreen(),
    SafetyScreen(),
    FavsScreen(),
    SetupScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: appActiveTabNotifier,
      builder: (context, activeIndex, _) {
        return IndexedStack(
          index: activeIndex,
          children: _tabs,
        );
      },
    );
  }
}
