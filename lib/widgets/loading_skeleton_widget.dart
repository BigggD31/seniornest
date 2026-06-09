import 'package:flutter/material.dart';

class LoadingSkeletonWidget extends StatefulWidget {
  const LoadingSkeletonWidget({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 12,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  State<LoadingSkeletonWidget> createState() => _LoadingSkeletonWidgetState();
}

class _LoadingSkeletonWidgetState extends State<LoadingSkeletonWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _animation = Tween<double>(
      begin: -0.5,
      end: 1.5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHighest;
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              colors: [base, base.withAlpha(128), base],
              stops: [
                (_animation.value - 0.3).clamp(0.0, 1.0),
                _animation.value.clamp(0.0, 1.0),
                (_animation.value + 0.3).clamp(0.0, 1.0),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        );
      },
    );
  }
}

class FeedSkeletonWidget extends StatelessWidget {
  const FeedSkeletonWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: List.generate(3, (index) => _buildCardSkeleton()),
      ),
    );
  }

  Widget _buildCardSkeleton() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFAF7F2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8E0D0), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const LoadingSkeletonWidget(
                  width: 44,
                  height: 44,
                  borderRadius: 22,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LoadingSkeletonWidget(
                      width: 120,
                      height: 14,
                      borderRadius: 7,
                    ),
                    const SizedBox(height: 6),
                    LoadingSkeletonWidget(
                      width: 80,
                      height: 12,
                      borderRadius: 6,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            const LoadingSkeletonWidget(
              width: double.infinity,
              height: 16,
              borderRadius: 8,
            ),
            const SizedBox(height: 8),
            const LoadingSkeletonWidget(
              width: 200,
              height: 14,
              borderRadius: 7,
            ),
          ],
        ),
      ),
    );
  }
}
