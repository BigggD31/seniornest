import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;

/// Oct 5 2026: lets the person frame their profile photo before it is saved.
/// Drag to move, pinch to zoom; whatever is inside the circle is what shows
/// as their avatar. Returns JPEG bytes (square, 320px) or null if cancelled.
///
/// Pure Dart (InteractiveViewer + RepaintBoundary) -- no native plugin.
class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  final GlobalKey _captureKey = GlobalKey();
  bool _saving = false;

  static const int _outputSize = 320;

  Future<void> _useThisPhoto() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary = _captureKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final pixelRatio = _outputSize / boundary.size.width;
      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('no pixel data');
      final decoded = img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: data.buffer,
        numChannels: 4,
      );
      final jpg = img.encodeJpg(decoded, quality: 85);
      if (mounted) Navigator.pop(context, Uint8List.fromList(jpg));
    } catch (e) {
      debugPrint('AVATAR_CROP_ERROR: $e');
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't crop that photo. Please try again.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final side = MediaQuery.of(context).size.width - 32;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _saving ? null : () => Navigator.pop(context, null),
        ),
        title: Text(
          'Move and zoom',
          style: GoogleFonts.nunitoSans(
              fontWeight: FontWeight.w700, color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            SizedBox(
              width: side,
              height: side,
              child: Stack(
                children: [
                  RepaintBoundary(
                    key: _captureKey,
                    child: ColoredBox(
                      color: Colors.black,
                      child: InteractiveViewer(
                        minScale: 1,
                        maxScale: 6,
                        boundaryMargin: EdgeInsets.zero,
                        child: SizedBox(
                          width: side,
                          height: side,
                          child: Image.memory(
                            widget.imageBytes,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Circle guide: dims everything outside the circle. Not part
                  // of the captured area (it sits outside the RepaintBoundary).
                  IgnorePointer(
                    child: CustomPaint(
                      size: Size(side, side),
                      painter: _CircleGuidePainter(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Drag to move. Pinch to zoom.',
              style: GoogleFonts.nunitoSans(
                  color: Colors.white70, fontSize: 14),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _saving ? null : _useThisPhoto,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5DA399),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: Colors.white),
                        )
                      : Text(
                          'Use this photo',
                          style: GoogleFonts.nunitoSans(
                              fontSize: 17, fontWeight: FontWeight.w700),
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

class _CircleGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final circle = Path()
      ..addOval(Rect.fromCircle(
          center: size.center(Offset.zero), radius: size.width / 2));
    final outside = Path.combine(PathOperation.difference, full, circle);
    canvas.drawPath(outside, Paint()..color = Colors.black54);
    canvas.drawPath(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
