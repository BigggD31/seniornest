import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// Opens a full-screen image viewer.
/// Supports landscape auto-rotation, close button (X top-right), and back gesture.
void openFullscreenImage({
  required BuildContext context,
  required String imageUrl,
  String semanticLabel = '',
  bool isDarkMode = false,
}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => _FullscreenImagePage(
        imageUrl: imageUrl,
        semanticLabel: semanticLabel,
      ),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

/// Opens a full-screen video viewer.
/// Supports landscape auto-rotation, close button (X top-right), and back gesture.
void openFullscreenVideo({
  required BuildContext context,
  required String videoUrl,
  bool isDarkMode = false,
}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => _FullscreenVideoPage(videoUrl: videoUrl),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

// ── Full-screen Image Page ─────────────────────────────────────────────────

class _FullscreenImagePage extends StatefulWidget {
  const _FullscreenImagePage({
    required this.imageUrl,
    required this.semanticLabel,
  });

  final String imageUrl;
  final String semanticLabel;

  @override
  State<_FullscreenImagePage> createState() => _FullscreenImagePageState();
}

class _FullscreenImagePageState extends State<_FullscreenImagePage> {
  @override
  void initState() {
    super.initState();
    // Allow all orientations so device auto-rotates to landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Restore portrait-only and system UI on close
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _close();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Pinch-to-zoom image
            Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Image.network(
                  widget.imageUrl,
                  fit: BoxFit.contain,
                  semanticLabel: widget.semanticLabel,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white54),
                    );
                  },
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(
                      Icons.broken_image_rounded,
                      color: Colors.white38,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
            // Close button — top-right
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 16,
              child: _CloseButton(onTap: _close),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Full-screen Video Page ─────────────────────────────────────────────────

class _FullscreenVideoPage extends StatefulWidget {
  const _FullscreenVideoPage({required this.videoUrl});

  final String videoUrl;

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    // Allow landscape for video
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );
      await controller.initialize();
      if (mounted) {
        setState(() {
          _controller = controller;
          _initialized = true;
        });
        controller.play();
      }
    } catch (_) {
      // Video failed to load — show error state
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  void _togglePlayPause() {
    if (_controller == null) return;
    setState(() {
      _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _close();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _toggleControls,
          child: Stack(
            children: [
              // Video or loading/error state
              Center(
                child: _initialized && _controller != null
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.rotationY(3.14159),
                        child: AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        ),
                      )
                    : const CircularProgressIndicator(color: Colors.white54),
              ),
              // Overlay controls
              if (_showControls) ...[
                // Gradient overlay for readability
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withAlpha(140),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withAlpha(140),
                        ],
                        stops: const [0.0, 0.2, 0.75, 1.0],
                      ),
                    ),
                  ),
                ),
                // Close button — top-right
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  right: 16,
                  child: _CloseButton(onTap: _close),
                ),
                // Play/pause button — center
                if (_initialized)
                  Center(
                    child: GestureDetector(
                      onTap: _togglePlayPause,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(140),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _controller!.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                  ),
                // Progress bar — bottom
                if (_initialized)
                  Positioned(
                    bottom: MediaQuery.of(context).padding.bottom + 24,
                    left: 20,
                    right: 20,
                    child: VideoProgressIndicator(
                      _controller!,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Color(0xFF5DA399),
                        bufferedColor: Colors.white38,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared Close Button ────────────────────────────────────────────────────

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(160),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
      ),
    );
  }
}
