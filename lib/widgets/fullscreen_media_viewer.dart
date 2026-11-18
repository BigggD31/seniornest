import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../services/save_media_service.dart';

/// Opens a full-screen image viewer.
/// Supports landscape auto-rotation, close button (X top-right), and back gesture.
void openFullscreenImage({
  required BuildContext context,
  required String imageUrl,
  String semanticLabel = '',
  bool isDarkMode = false,
}) {
  openFullscreenImages(
    context: context,
    imageUrls: [imageUrl],
    semanticLabel: semanticLabel,
    isDarkMode: isDarkMode,
  );
}

/// Nov 17 2026: full-screen viewer for a post with several photos. Swipe
/// left/right between them; the counter shows "2 of 4" and Save saves the
/// photo on screen. With one photo it looks and behaves as it always did.
void openFullscreenImages({
  required BuildContext context,
  required List<String> imageUrls,
  int initialIndex = 0,
  String semanticLabel = '',
  bool isDarkMode = false,
}) {
  if (imageUrls.isEmpty) return;
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => _FullscreenImagePage(
        imageUrls: imageUrls,
        initialIndex: initialIndex.clamp(0, imageUrls.length - 1),
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
  bool isRecordedVideo = false,
}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => _FullscreenVideoPage(
        videoUrl: videoUrl,
        isRecordedVideo: isRecordedVideo,
      ),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

// ── Full-screen Image Page ─────────────────────────────────────────────────

class _FullscreenImagePage extends StatefulWidget {
  const _FullscreenImagePage({
    required this.imageUrls,
    required this.initialIndex,
    required this.semanticLabel,
  });

  final List<String> imageUrls;
  final int initialIndex;
  final String semanticLabel;

  @override
  State<_FullscreenImagePage> createState() => _FullscreenImagePageState();
}

class _FullscreenImagePageState extends State<_FullscreenImagePage> {
  late final PageController _pageController;
  late int _index;
  // While a photo is pinched in, swiping would fight the zoom pan, so
  // page-swiping is switched off until it is back to normal size.
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
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
    _pageController.dispose();
    // Restore portrait-only and system UI on close
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final urls = widget.imageUrls;
    final multi = urls.length > 1;
    return WillPopScope(
      onWillPop: () async {
        _close();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Swipeable, pinch-to-zoom photos
            PageView.builder(
              controller: _pageController,
              itemCount: urls.length,
              physics: _zoomed
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => _ZoomableImage(
                url: urls[i],
                semanticLabel: widget.semanticLabel,
                onZoomChanged: (z) {
                  if (i == _index && z != _zoomed) {
                    setState(() => _zoomed = z);
                  }
                },
              ),
            ),
            // Save to phone — top-left (saves the photo on screen)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              child: _SaveButton(
                key: ValueKey(urls[_index]),
                url: urls[_index],
                isVideo: false,
              ),
            ),
            if (multi)
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(160),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_index + 1} of ${urls.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (multi)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 20,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < urls.length; i++)
                        Container(
                          width: i == _index ? 9 : 8,
                          height: i == _index ? 9 : 8,
                          margin: const EdgeInsets.symmetric(horizontal: 3.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _index
                                ? Colors.white
                                : Colors.white38,
                          ),
                        ),
                    ],
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

/// One photo in the swipe viewer: pinch to zoom, reports when it is zoomed.
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({
    required this.url,
    required this.semanticLabel,
    required this.onZoomChanged,
  });

  final String url;
  final String semanticLabel;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final TransformationController _tc = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _tc.addListener(_onChanged);
  }

  void _onChanged() {
    final z = _tc.value.getMaxScaleOnAxis() > 1.02;
    if (z != _zoomed) {
      _zoomed = z;
      widget.onZoomChanged(z);
    }
  }

  @override
  void dispose() {
    _tc.removeListener(_onChanged);
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InteractiveViewer(
        transformationController: _tc,
        minScale: 0.8,
        maxScale: 4.0,
        child: Image.network(
          widget.url,
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
    );
  }
}

// ── Full-screen Video Page ─────────────────────────────────────────────────

class _FullscreenVideoPage extends StatefulWidget {
  const _FullscreenVideoPage({
    required this.videoUrl,
    this.isRecordedVideo = false,
  });

  final String videoUrl;
  final bool isRecordedVideo;

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
                    ? AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: widget.isRecordedVideo
                            ? Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.rotationY(3.14159),
                                child: VideoPlayer(_controller!),
                              )
                            : VideoPlayer(_controller!),
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
                // Save to phone — top-left
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 16,
                  child: _SaveButton(url: widget.videoUrl, isVideo: true),
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


// ── Save to phone button ───────────────────────────────────────────────────

class _SaveButton extends StatefulWidget {
  const _SaveButton({super.key, required this.url, required this.isVideo});

  final String url;
  final bool isVideo;

  @override
  State<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<_SaveButton> {
  bool _busy = false;

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await SaveMediaService.saveToPhotos(
      widget.url,
      isVideo: widget.isVideo,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    final what = widget.isVideo ? 'video' : 'photo';
    final message = switch (result) {
      SaveMediaResult.saved => 'Saved to your Photos',
      SaveMediaResult.denied =>
        'Allow SeniorNest to add to Photos in Settings to save this $what',
      SaveMediaResult.failed => 'Could not save this $what. Please try again.',
      SaveMediaResult.cancelled => '',
    };
    if (message.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _save,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(160),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: _busy
            ? const Padding(
                padding: EdgeInsets.all(11),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.download_rounded, color: Colors.white, size: 22),
      ),
    );
  }
}
