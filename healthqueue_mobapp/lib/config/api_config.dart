import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Single source of truth for hq-mobapp-v2's API base URL.
///
/// Resolution order:
///   1. `API_BASE_URL` from `.env` (recommended — works for local, staging, prod)
///   2. Platform-aware localhost fallback, but ONLY in debug builds
///   3. [prodFallbackUrl] below — set this to your Heroku app URL
///
/// To point the app at your Heroku server, create a `.env` file at the
/// project root (next to pubspec.yaml) containing:
///
///   API_BASE_URL=https://<your-heroku-app-name>.herokuapp.com/api
///
/// (Note the trailing /api — this app's ApiService appends paths like
/// `/auth/login` directly onto baseUrl, unlike some other hq clients.)
class ApiConfig {
  ApiConfig._();

  /// Hard fallback used only if no .env is present and this isn't a debug
  /// build. Update this to your real Heroku URL + /api.
  static const String prodFallbackUrl =
      'https://REPLACE_WITH_YOUR_HEROKU_APP.herokuapp.com/api';

  static String get baseUrl {
    if (dotenv.isInitialized) {
      final envUrl = dotenv.env['API_BASE_URL'];
      if (envUrl != null && envUrl.trim().isNotEmpty) {
        return envUrl.trim().replaceAll(RegExp(r'/+$'), '');
      }
    }

    if (kDebugMode) {
      if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:4000/api';
      if (!kIsWeb && Platform.isIOS) return 'http://127.0.0.1:4000/api';
    }

    return prodFallbackUrl;
  }
}
