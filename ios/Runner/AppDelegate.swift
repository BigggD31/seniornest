import Flutter
import UIKit
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Sep 14 2026: this app initializes Firebase from Dart (main.dart's
    // Firebase.initializeApp()), not natively here in AppDelegate. Confirmed
    // via research: that ordering has a real, documented gap in
    // firebase_messaging -- native plugin registration happens before
    // Dart ever runs, so the plugin's own automatic check for whether to
    // call registerForRemoteNotifications() can run before Firebase is
    // actually configured, see that it isn't ready, and skip it --
    // permanently, with no retry once Firebase does get configured a
    // moment later. That produces exactly what device testing showed:
    // requestPermission() genuinely returns authorized, but
    // getAPNSToken() never resolves, no matter how long you wait,
    // because registerForRemoteNotifications() itself was simply never
    // called. Calling it directly and unconditionally here removes the
    // dependency on that automatic detection entirely -- this is safe to
    // call before permission is granted (it's a no-op until it is) and
    // is the pattern Apple's own DTS engineers point to for exactly this
    // symptom.
    DispatchQueue.main.async {
      UIApplication.shared.registerForRemoteNotifications()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Forward the APNs token to Firebase Messaging explicitly, rather than
  // relying solely on method swizzling to intercept this callback --
  // same reasoning as above, and harmless even on a device where
  // swizzling also happens to work correctly.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    return super.application(app, open: url, options: options)
  }
}
