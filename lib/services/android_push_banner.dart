import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android only. Firebase shows no banner for a push that arrives while the
/// app is open on Android (iOS handles this through
/// setForegroundNotificationPresentationOptions). This forwards each such
/// push to MainActivity, which shows it on the "seniornest_alerts" channel,
/// and routes a tap on that banner to the same tab-opening handler used for
/// background pushes. Never called on iOS.
class AndroidPushBanner {
  static const MethodChannel _channel = MethodChannel('seniornest/notify');
  static bool _started = false;

  static void start(void Function(RemoteMessage message) onTap) {
    if (_started) return;
    _started = true;

    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      _channel.invokeMethod('show', {
        'title': notification.title ?? '',
        'body': notification.body ?? '',
        'type': message.data['type'],
      }).catchError((e) {
        debugPrint('ANDROID_PUSH_BANNER show error: $e');
      });
    });

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'tapped' && call.arguments is String) {
        onTap(RemoteMessage(data: {'type': call.arguments as String}));
      }
    });
  }
}
