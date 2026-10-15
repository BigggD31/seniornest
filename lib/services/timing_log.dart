/// Oct 15 2026: the temporary sign-in timing diagnostic has been switched
/// off for release. The calls are kept (as harmless no-ops) so no other
/// screen needed to change; nothing is recorded or sent anywhere.
class TimingLog {
  static void begin(String flow) {}

  static void mark(String step) {}
}
