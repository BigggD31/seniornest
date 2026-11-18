import 'package:flutter/material.dart';

import 'custom_image_widget.dart';
import 'fullscreen_media_viewer.dart';

/// Nov 17 2026: swipeable photos for a post that has more than one. The next
/// photo peeks in from the right so people can tell there is more; a "1 / 4"
/// badge and dots show where you are. Tapping a photo opens the full-screen
/// swipe viewer on that photo.
class PhotoCarousel extends StatefulWidget {
  const PhotoCarousel({
    super.key,
    required this.urls,
    required this.height,
    required this.semanticLabel,
    required this.isDarkMode,
    this.radius,
  });

  final List<String> urls;
  final double height;
  final String semanticLabel;
  final bool isDarkMode;
  // Corner shape of each photo; defaults to 12 all round.
  final BorderRadius? radius;

  @override
  State<PhotoCarousel> createState() => PhotoCarouselState();
}

class PhotoCarouselState extends State<PhotoCarousel> {
  final PageController _controller = PageController(viewportFraction: 0.9);
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: widget.height,
          child: PageView.builder(
            controller: _controller,
            padEnds: false,
            itemCount: urls.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => openFullscreenImages(
                    context: context,
                    imageUrls: urls,
                    initialIndex: i,
                    semanticLabel: widget.semanticLabel,
                    isDarkMode: widget.isDarkMode,
                  ),
                  child: ClipRRect(
                    borderRadius: widget.radius ?? BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomImageWidget(
                          imageUrl: urls[i],
                          width: double.infinity,
                          height: widget.height,
                          fit: BoxFit.cover,
                          semanticLabel: widget.semanticLabel,
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(150),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${i + 1} / ${urls.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: 'Photo ${_index + 1} of ${urls.length}',
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
                        ? const Color(0xFFD4AA00)
                        : (widget.isDarkMode
                            ? const Color(0xFF4A4234)
                            : const Color(0xFFD9CDB4)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
