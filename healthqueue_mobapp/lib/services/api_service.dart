import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_config.dart';

/// Central API service for hq-mobapp-v2.
/// Base URL is resolved by [ApiConfig] — see that file to point this at
/// your Heroku server via a .env file.
class ApiService {
  static String get baseUrl => ApiConfig.baseUrl;

  static const _storage  = FlutterSecureStorage();
  static const _tokenKey = 'hq_jwt_token';

  // ── Timeouts ──────────────────────────────────────────────────────────────
  // Mutating requests (POST/PUT that create records) get a LONGER timeout
  // and NO retries — retrying a POST would create duplicate records on the server.
  static const _mutateTimeout = Duration(seconds: 20); // join queue, book appt
  static const _readTimeout   = Duration(seconds: 12); // GET requests
  static const _maxRetry      = 2;                     // only for GET requests

  // ── Token helpers ─────────────────────────────────────────────────────────
  static Future<void>    saveToken(String t)  async => _storage.write(key: _tokenKey, value: t);
  static Future<String?> getToken()           async => _storage.read(key: _tokenKey);
  static Future<void>    clearToken()         async => _storage.delete(key: _tokenKey);

  static Future<Map<String, String>> _authHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ── Retry wrapper — GET requests ONLY ────────────────────────────────────
  // IMPORTANT: Never retry POST/PUT that create data — it causes duplicates.
  static Future<http.Response> _withRetry(
    Future<http.Response> Function() call, {
    int retries = _maxRetry,
  }) async {
    for (int i = 0; i <= retries; i++) {
      try {
        final res = await call().timeout(_readTimeout);
        // 429 — rate limited: back off exponentially, then retry
        if (res.statusCode == 429) {
          if (i == retries) return res; // return and let caller handle it
          final wait = Duration(seconds: (i + 1) * 5); // 5s, 10s, 15s...
          await Future.delayed(wait);
          continue;
        }
        return res;
      } on TimeoutException {
        if (i == retries) throw Exception('Connection timed out. Please check your network.');
        await Future.delayed(Duration(seconds: i + 1));
      } on SocketException {
        if (i == retries) throw Exception('No internet connection. Please check your network.');
        await Future.delayed(Duration(seconds: i + 1));
      }
    }
    throw Exception('Request failed after $retries retries.');
  }

  // ── Single-shot wrapper — POST/PUT that CREATE records ────────────────────
  // No retry. Longer timeout. If it times out, tell the user to check their
  // queue/appointments screen before trying again — the record may have been
  // created successfully on the server.
  static Future<http.Response> _once(
    Future<http.Response> Function() call,
  ) async {
    try {
      return await call().timeout(_mutateTimeout);
    } on TimeoutException {
      throw Exception(
        'The request timed out. Please check your queue or appointments screen — '
        'your action may have been processed. If not, try again.',
      );
    } on SocketException {
      throw Exception('No internet connection. Please check your network.');
    }
  }

  // ── Error parser ──────────────────────────────────────────────────────────
  static void _assertOk(http.Response res, String fallback) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    String msg = fallback;
    try {
      final e = jsonDecode(res.body);
      msg = e['message'] ?? e['error'] ?? fallback;
    } catch (_) {}
    throw Exception(msg);
  }

  // ── Auth ──────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await _once(() => http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    ));
    _assertOk(res, 'Login failed. Check your email and password.');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['token'] != null) await saveToken(data['token'] as String);
    return data;
  }

  static Future<Map<String, dynamic>> register(Map<String, dynamic> body) async {
    final res = await _once(() => http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ));
    _assertOk(res, 'Registration failed.');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['token'] != null) await saveToken(data['token'] as String);
    return data;
  }

  static Future<Map<String, dynamic>> getMe() async {
    final res = await _withRetry(() async =>
        http.get(Uri.parse('$baseUrl/auth/me'), headers: await _authHeaders()));
    _assertOk(res, 'Failed to fetch profile');
    final data = jsonDecode(res.body);
    return (data is Map && data['user'] != null)
        ? data['user'] as Map<String, dynamic>
        : data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> body) async {
    // Server mounts this under /users/me/patient (userRoutes.js), not /users/profile.
    final res = await _once(() async => http.put(
      Uri.parse('$baseUrl/users/me/patient'),
      headers: await _authHeaders(),
      body: jsonEncode(body),
    ));
    _assertOk(res, 'Failed to update profile');
    final data = jsonDecode(res.body);
    return (data is Map && data['user'] != null)
        ? data['user'] as Map<String, dynamic>
        : data as Map<String, dynamic>;
  }

  // ── Clinics ───────────────────────────────────────────────────────────────
  static Future<List<dynamic>> getClinicDirectory() async {
    final res = await _withRetry(
        () async => http.get(Uri.parse('$baseUrl/clinics/directory'),
            headers: await _authHeaders()));
    _assertOk(res, 'Failed to load clinics');
    final data = jsonDecode(res.body);
    if (data is List) return data;
    if (data is Map)  return (data['clinics'] ?? data['data'] ?? []) as List;
    return [];
  }

  static Future<Map<String, dynamic>> getRecommendedClinics({
    String? service, double? lat, double? lng, String type = 'queue',
  }) async {
    final params = <String, String>{'type': type};
    if (service != null) params['service'] = service;
    if (lat != null)     params['lat']     = lat.toString();
    if (lng != null)     params['lng']     = lng.toString();
    final uri = Uri.parse('$baseUrl/clinics/recommend')
        .replace(queryParameters: params);
    final res = await _withRetry(
        () async => http.get(uri, headers: await _authHeaders()));
    _assertOk(res, 'Failed to load recommendations');
    final data = jsonDecode(res.body);
    return data is Map ? data as Map<String, dynamic> : {'clinics': data};
  }

  static Future<Map<String, dynamic>> getClinic(String id) async {
    final res = await _withRetry(() async => http.get(
        Uri.parse('$baseUrl/clinics/$id'), headers: await _authHeaders()));
    _assertOk(res, 'Failed to load clinic');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Queue — _once() for all writes ───────────────────────────────────────
  static Future<Map<String, dynamic>> joinQueue({
    required String clinicId,
    required String serviceName,
    String? notes,
  }) async {
    final res = await _once(() async => http.post(
      Uri.parse('$baseUrl/queues/join'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'clinicId':    clinicId,
        'serviceName': serviceName,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      }),
    ));
    // 409 = already in queue — surface the existing entry to the UI
    if (res.statusCode == 409) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw QueueConflictException(
        body['message'] ?? 'You are already in a queue.',
        existingEntry: body['existingEntry'] as Map<String, dynamic>?,
      );
    }
    _assertOk(res, 'Failed to join queue.');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // GET — safe to retry
  static Future<Map<String, dynamic>> getMyQueueStatus() async {
    final res = await _withRetry(() async => http.get(
        Uri.parse('$baseUrl/queues/my-status'), headers: await _authHeaders()));
    if (res.statusCode == 404) return {'inQueue': false};
    _assertOk(res, 'Failed to get queue status');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // PUT cancel — idempotent, safe to retry
  static Future<bool> cancelQueue(String id) async {
    final res = await _withRetry(() async => http.put(
        Uri.parse('$baseUrl/queues/$id/cancel'),
        headers: await _authHeaders()));
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  static Future<Map<String, dynamic>> getQueueMetrics(String clinicId) async {
    final res = await _withRetry(() async => http.get(
      Uri.parse('$baseUrl/queues/metrics?clinicId=$clinicId'),
      headers: await _authHeaders(),
    ));
    if (res.statusCode != 200) return {};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Appointments — _once() for all writes ────────────────────────────────
  static Future<List<dynamic>> getMyAppointments() async {
    final res = await _withRetry(() async => http.get(
        Uri.parse('$baseUrl/appointments/my'), headers: await _authHeaders()));
    _assertOk(res, 'Failed to load appointments');
    final data = jsonDecode(res.body);
    if (data is List) return data;
    if (data is Map)  return (data['appointments'] ?? data['data'] ?? []) as List;
    return [];
  }

  static Future<Map<String, dynamic>> bookAppointment(
      Map<String, dynamic> body) async {
    final res = await _once(() async => http.post(
      Uri.parse('$baseUrl/appointments'),
      headers: await _authHeaders(),
      body: jsonEncode(body),
    ));
    if (res.statusCode == 409) {
      final b = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(
          b['message'] ?? 'This time slot is already booked. Please choose another.');
    }
    _assertOk(res, 'Failed to book appointment.');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // PUT cancel — idempotent, safe to retry
  static Future<bool> cancelAppointment(String id) async {
    final res = await _withRetry(() async => http.put(
        Uri.parse('$baseUrl/appointments/$id/cancel'),
        headers: await _authHeaders()));
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  static Future<List<dynamic>> getAvailableSlots({
    required String clinicId, required String date,
  }) async {
    final res = await _withRetry(() async => http.get(
      Uri.parse('$baseUrl/appointments/available-slots'
          '?clinicId=$clinicId&date=$date'),
      headers: await _authHeaders(),
    ));
    if (res.statusCode == 404) return [];
    _assertOk(res, 'Failed to load slots');
    final data = jsonDecode(res.body);
    if (data is List) return data;
    if (data is Map) {
      return (data['available'] ?? data['slots'] ?? data['data'] ?? []) as List;
    }
    return [];
  }

  // ── Chatbot ───────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> sendChatMessage(String message) async {
    final res = await _once(() async => http.post(
      Uri.parse('$baseUrl/chatbot/message'),
      headers: await _authHeaders(),
      body: jsonEncode({'message': message}),
    ));
    _assertOk(res, 'Chatbot error');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<bool> escalateChatbot({String? note}) async {
    try {
      final res = await _once(() async => http.post(
        Uri.parse('$baseUrl/chatbot/escalate'),
        headers: await _authHeaders(),
        body: jsonEncode({'note': note ?? ''}),
      ));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) { return false; }
  }

  // ── Notifications ─────────────────────────────────────────────────────────
  static Future<List<dynamic>> getNotifications() async {
    try {
      final res = await _withRetry(() async => http.get(
          Uri.parse('$baseUrl/notifications'), headers: await _authHeaders()));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);
      if (data is List) return data;
      if (data is Map) return (data['notifications'] ?? data['data'] ?? []) as List;
      return [];
    } catch (_) { return []; }
  }

  static Future<bool> markNotificationRead(String id) async {
    try {
      final res = await _once(() async => http.put(
          Uri.parse('$baseUrl/notifications/$id/read'),
          headers: await _authHeaders()));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) { return false; }
  }

  static Future<bool> markAllNotificationsRead() async {
    try {
      final res = await _once(() async => http.put(
          Uri.parse('$baseUrl/notifications/read-all'),
          headers: await _authHeaders()));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) { return false; }
  }

  /// Calls the Prescriptive Analytics Engine with optional patient inputs.
  static Future<Map<String, dynamic>> evaluatePrescription({
    double? lat,
    double? lng,
    String  purpose     = '',
    String  symptoms    = '',
    String  patientType = 'Regular',
  }) async {
    final params = <String, String>{
      if (lat != null) 'lat': lat.toString(),
      if (lng != null) 'lng': lng.toString(),
      if (purpose.isNotEmpty)     'purpose':     purpose,
      if (symptoms.isNotEmpty)    'symptoms':    symptoms,
      if (patientType.isNotEmpty) 'patientType': patientType,
    };
    final uri = Uri.parse('$baseUrl/prescriptive/evaluate')
        .replace(queryParameters: params);
    final res = await _withRetry(() async =>
        http.get(uri, headers: await _authHeaders()));
    _assertOk(res, 'Failed to evaluate prescription.');
    final data = jsonDecode(res.body);
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  /// Returns best historical time to queue at a given clinic.
  static Future<Map<String, dynamic>> getBestTimeToQueue(String clinicId) async {
    final res = await _withRetry(() async => http.get(
        Uri.parse('$baseUrl/prescriptive/best-time/$clinicId'),
        headers: await _authHeaders()));
    _assertOk(res, 'Failed to load best-time data.');
    final data = jsonDecode(res.body);
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  static Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    // Server mounts this under /users/change-password (userRoutes.js), not /auth/change-password.
    final res = await _once(() async => http.put(
      Uri.parse('$baseUrl/users/change-password'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword':     newPassword,
      }),
    ));
    _assertOk(res, 'Failed to update password.');
  }
}

// ── Custom exceptions ─────────────────────────────────────────────────────────
class QueueConflictException implements Exception {
  final String message;
  final Map<String, dynamic>? existingEntry;
  const QueueConflictException(this.message, {this.existingEntry});
  @override String toString() => message;
}
