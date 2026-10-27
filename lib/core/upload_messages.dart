/// Plain-language messages for failed media uploads (1.05).
///
/// Before this, a failed upload showed the raw error text to the person
/// ("Save error: StorageException(...)"). These helpers turn that into
/// something a grandparent can read and act on. The raw error is still
/// printed to the console by the callers for debugging.

/// Largest single file the server accepts (Supabase global limit, set to
/// 500 MB on Oct 26 2026). App-side caps must never exceed this.
const int kServerMaxUploadBytes = 500 * 1024 * 1024;

/// True when [error] looks like the server rejecting the file for size.
bool looksLikeTooLargeError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('413') ||
      text.contains('payload too large') ||
      text.contains('too large') ||
      text.contains('exceeded the maximum') ||
      text.contains('maximum allowed size');
}

/// Message shown when saving or sending a file did not work.
String friendlyUploadError(Object error) {
  if (looksLikeTooLargeError(error)) {
    return 'That file is too large to save. Try a shorter recording or '
        'a smaller file.';
  }
  return "We couldn't save that just now. Please check your connection "
      'and try again.';
}

/// Message shown before uploading when a file is over [kServerMaxUploadBytes].
String tooLargeBeforeUploadMessage() {
  return 'That recording is too large to save. Try recording a shorter '
      'story, or save it in two parts.';
}
