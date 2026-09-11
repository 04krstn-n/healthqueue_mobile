import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'state/app_state.dart';
import 'services/push_notification_service.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    debugPrint('.env not found — using fallback API base URL');
  }

  // The device log showed every GoogleMap instance in this app falling
  // back to Android's older "LEGACY" renderer ("No TextureView found.
  // Likely using the LEGACY renderer."). The modern renderer must be
  // explicitly requested in Dart, before any GoogleMap widget is built —
  // there's no manifest setting for this. Must run before runApp() below,
  // and only on Android (this API doesn't exist on other platforms).
  if (Platform.isAndroid) {
    try {
      final mapsImplementation = GoogleMapsFlutterPlatform.instance;
      if (mapsImplementation is GoogleMapsFlutterAndroid) {
        await mapsImplementation.initializeWithRenderer(
          AndroidMapRenderer.latest,
        );
      }
    } catch (e) {
      debugPrint('Could not request latest Maps renderer: $e');
    }
  }

  // PushNotificationService.initialize() already fails soft internally
  // for Firebase.initializeApp() itself — but wrap the whole call here too
  // as a second line of defense. Anything else that throws inside it
  // (Firebase Messaging permission requests, local-notification channel
  // setup, etc.) must NEVER be allowed to stop runApp() from executing
  // below — that would leave the app on a permanent black screen with no
  // UI and no visible error, since Flutter's own error display needs
  // runApp() to have already run.
  try {
    await PushNotificationService.initialize();
  } catch (e) {
    debugPrint('Push notification setup failed, continuing without it: $e');
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const MyApp(),
    ),
  );
}