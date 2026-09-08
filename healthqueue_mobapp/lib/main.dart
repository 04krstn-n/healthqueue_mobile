import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
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

  // Safe to call even if Firebase isn't configured yet in the native
  // project (see PushNotificationService.initialize's try/catch) — the
  // rest of the app keeps working either way.
  await PushNotificationService.initialize();

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const MyApp(),
    ),
  );
}
