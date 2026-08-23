import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'state/app_state.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    debugPrint('.env not found — using fallback API base URL');
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const MyApp(),
    ),
  );
}
