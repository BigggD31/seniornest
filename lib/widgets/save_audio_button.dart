import 'package:flutter/material.dart';

import '../services/save_media_service.dart';

/// Small download icon for audio players. Saves a private copy of the
/// recording to the person's phone through the Files picker.
class SaveAudioButton extends StatefulWidget {
  const SaveAudioButton({
    super.key,
    required this.url,
    this.color = const Color(0xFF412402),
    this.size = 22,
  });

  final String url;
  final Color color;
  final double size;

  @override
  State<SaveAudioButton> createState() => _SaveAudioButtonState();
}

class _SaveAudioButtonState extends State<SaveAudioButton> {
  bool _busy = false;

  Future<void> _save() async {
    if (_busy || widget.url.isEmpty) return;
    setState(() => _busy = true);
    final result = await SaveMediaService.saveAudioToFiles(widget.url);
    if (!mounted) return;
    setState(() => _busy = false);
    final message = switch (result) {
      SaveMediaResult.saved => 'Recording saved',
      SaveMediaResult.failed => 'Could not save this recording. Please try again.',
      _ => '',
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
    if (widget.url.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _save,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: _busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.color,
                  ),
                )
              : Icon(Icons.download_rounded, color: widget.color, size: widget.size),
        ),
      ),
    );
  }
}
