import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppNavigation extends StatefulWidget {
  const AppNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  State<AppNavigation> createState() => _AppNavigationState();
}

class _AppNavigationState extends State<AppNavigation>
    with SingleTickerProviderStateMixin {
  late AnimationController _dotController;

  @override
  void initState() {
    super.initState();
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
  }

  @override
  void dispose() {
    _dotController.dispose();
    super.dispose();
  }

  static const List<_NavItem> _items = [
    _NavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    ),
    _NavItem(
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
      label: 'Messages',
    ),
    _NavItem(
      icon: Icons.auto_stories_outlined,
      activeIcon: Icons.auto_stories_rounded,
      label: 'Legacy',
    ),
    _NavItem(
      icon: Icons.shield_outlined,
      activeIcon: Icons.shield_rounded,
      label: 'Safety',
    ),
    _NavItem(
      icon: Icons.favorite_outline_rounded,
      activeIcon: Icons.favorite_rounded,
      label: 'Favs',
    ),
    _NavItem(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: 'Setup',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFFDFDFD);
    final borderColor = isDark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFE8E0D0);

    return Material(
      color: bgColor,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(top: BorderSide(color: borderColor, width: 1)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 17),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_items.length, (index) {
                final isActive = index == widget.currentIndex;
                return _NavItemWidget(
                  item: _items[index],
                  isActive: isActive,
                  onTap: () => widget.onTap(index),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItemWidget extends StatefulWidget {
  const _NavItemWidget({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_NavItemWidget> createState() => _NavItemWidgetState();
}

class _NavItemWidgetState extends State<_NavItemWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _dotAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _dotAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    if (widget.isActive) _controller.forward();
  }

  @override
  void didUpdateWidget(_NavItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _controller.forward();
    } else if (!widget.isActive && oldWidget.isActive) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = const Color(0xFF5DA399);
    final inactiveColor = theme.brightness == Brightness.dark
        ? const Color(0xFFE0E0E0)
        : theme.colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 58,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Center(
                    child: Icon(
                      widget.isActive
                          ? widget.item.activeIcon
                          : widget.item.icon,
                      size: 24,
                      color: widget.isActive ? activeColor : inactiveColor,
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                SizedBox(
                  height: 14,
                  child: Text(
                    widget.item.label,
                    style: GoogleFonts.nunitoSans(
                      fontSize: 9,
                      fontWeight: widget.isActive
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: widget.isActive ? activeColor : inactiveColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 11),
                // Fixed-size dot indicator — opacity animates, size never changes
                SizedBox(
                  width: 5,
                  height: 5,
                  child: Opacity(
                    opacity: _dotAnim.value,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: activeColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}
