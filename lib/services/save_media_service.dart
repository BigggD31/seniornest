import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

enum SaveMediaResult { saved, denied, failed }

/// Saves a photo or video from a family nest to this device's Photos library.
/// This is a private copy for the person who tapped it -- nothing is sent
/// anywhere, there is no share sheet involved.
class SaveMediaService {
  static String _extension(String url, String fallback) {
    final path = Uri.tryParse(url)?.path ?? '';
    final dot = path.lastIndexOf('.');
    if (dot == -1 || path.length - dot > 6) return fallback;
    return path.substring(dot + 1).toLowerCase();
  }

  static Future<SaveMediaResult> saveToPhotos(
    String url, {
    required bool isVideo,
  }) async {
    File? file;
    try {
      if (!await Gal.hasAccess(toAlbum: false)) {
        final granted = await Gal.requestAccess(toAlbum: false);
        if (!granted) return SaveMediaResult.denied;
      }
      final dir = await getTemporaryDirectory();
      final ext = _extension(url, isVideo ? 'mp4' : 'jpg');
      final path =
          '${dir.path}/seniornest_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await Dio().download(url, path);
      file = File(path);
      if (isVideo) {
        await Gal.putVideo(path);
      } else {
        await Gal.putImage(path);
      }
      return SaveMediaResult.saved;
    } on GalException catch (e) {
      debugPrint('SAVE_MEDIA_GAL_ERROR: ${e.type}');
      return e.type == GalExceptionType.accessDenied
          ? SaveMediaResult.denied
          : SaveMediaResult.failed;
    } catch (e) {
      debugPrint('SAVE_MEDIA_ERROR: $e');
      return SaveMediaResult.failed;
    } finally {
      try {
        if (file != null && await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
}
