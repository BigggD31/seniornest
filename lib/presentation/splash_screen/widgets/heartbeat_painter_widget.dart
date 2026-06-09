import 'package:flutter/material.dart';
import 'dart:math' as math;

class HeartbeatPainterWidget extends CustomPainter {
  HeartbeatPainterWidget({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final glowPaint = Paint()
      ..color = color.withAlpha(64)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final path = _buildHeartbeatPath(size);
    final totalLength = _estimatePathLength(size);
    final visibleLength = totalLength * progress;

    final metrics = path.computeMetrics().toList();
    final visiblePath = Path();
    double accumulated = 0;

    for (final metric in metrics) {
      if (accumulated >= visibleLength) break;
      final remaining = visibleLength - accumulated;
      final extract = metric.extractPath(0, math.min(remaining, metric.length));
      visiblePath.addPath(extract, Offset.zero);
      accumulated += metric.length;
    }

    canvas.drawPath(visiblePath, glowPaint);
    canvas.drawPath(visiblePath, paint);

    // Draw moving dot at the tip
    if (progress < 1.0 && metrics.isNotEmpty) {
      final tipMetric = metrics.first;
      final tipLength = math.min(visibleLength, tipMetric.length);
      final tangent = tipMetric.getTangentForOffset(tipLength);
      if (tangent != null) {
        final dotPaint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        canvas.drawCircle(tangent.position, 4, dotPaint);
      }
    }
  }

  Path _buildHeartbeatPath(Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;
    final mid = h / 2;

    // Baseline
    path.moveTo(0, mid);
    path.lineTo(w * 0.25, mid);
    // First small bump
    path.lineTo(w * 0.30, mid - h * 0.12);
    path.lineTo(w * 0.35, mid);
    // Big heartbeat spike
    path.lineTo(w * 0.42, mid + h * 0.08);
    path.lineTo(w * 0.47, mid - h * 0.45);
    path.lineTo(w * 0.52, mid + h * 0.35);
    path.lineTo(w * 0.57, mid - h * 0.15);
    path.lineTo(w * 0.62, mid);
    // Trailing baseline
    path.lineTo(w, mid);

    return path;
  }

  double _estimatePathLength(Size size) {
    return size.width * 1.8;
  }

  @override
  bool shouldRepaint(HeartbeatPainterWidget oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
