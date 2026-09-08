import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Must be a top-level (or static) function, not a class method — this is
/// a Firebase SDK requirement, since it runs on a separate isolate when a
/// push arrives while the app is fully terminated or backgrounded. The
/// @pragma keeps it from being tree-shaken out of the release build.
///
/// This can stay minimal: as long as the server sends a `notification`
/// block (see hq-server's services/pushService.js), Android/iOS display it
/// in the system tray automatically with zero app code needed for that —
/// this handler only matters if extra background data-processing is ever
/// needed later.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Push notifications — this is what actually reaches a patient while the
/// app is backgrounded or fully closed. The app previously only had
/// in-app notifications fetched via GET /notifications, which meant
/// nothing was visible until the patient next opened the app themselves.
class PushNotificationService {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Call once, early in main() — sets up Firebase, permissions, and the
  /// foreground-message display path (background/terminated delivery is
  /// handled by the OS automatically once Firebase is initialized).
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await Firebase.initializeApp();
    } catch (e) {
      // Most likely cause: google-services.json / GoogleService-Info.plist
      // hasn't been added to the native project yet (see setup notes).
      // Fail soft — the rest of the app must keep working even if push
      // was never configured.
      debugPrint('Firebase init failed (push notifications disabled): $e');
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    // Foreground messages do NOT show a system banner on either platform
    // by default — FCM only auto-displays while backgrounded/terminated.
    // Without this listener, a push arriving while the patient has the
    // app open would be silently dropped instead of shown at all.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification == null) return;
      _local.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'hq_default_channel',
            'HealthQueue+ Notifications',
            channelDescription: 'Queue calls, appointment updates, and alerts',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    });
  }

  /// Fetches the current device's FCM token and sends it to the server so
  /// pushes can actually be targeted at this device. Call once right
  /// after login/registration/session-restore succeeds — a token fetched
  /// before that point has no logged-in account to attach it to yet.
  static Future<void> registerToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await ApiService.registerFcmToken(token);
      }
    } catch (e) {
      debugPrint('Failed to register FCM token: $e');
    }

    // The token can rotate (reinstall, Firebase-side refresh) — keep the
    // server in sync whenever that happens, not just once at login.
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      ApiService.registerFcmToken(newToken).catchError((_) => false);
    });
  }

  /// Clears the token server-side on logout, so a stale token left on a
  /// shared/reinstalled device doesn't keep receiving pushes meant for
  /// this account after someone else logs in on it.
  static Future<void> clearToken() async {
    try {
      await ApiService.registerFcmToken('');
    } catch (_) {}
  }
}
