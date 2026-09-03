import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_config.dart';

/// Thrown by [ApiService.login] when the account exists and the password is
/// correct, but the phone number was never OTP-verified. Carries what the
/// OTP screen needs so the app can route straight back into verification
/// instead of showing a generic "invalid credentials" error.
class OtpRequiredException implements Exception {
  final String userId;
  final String phone;
  final String message;
  OtpRequiredException({
    required this.userId,
    required this.phone,
    required this.message,
  });
  @override
  String toString() => message;
}

/// Central API service for hq-mobapp-v2.
/// Base URL is resolved by [ApiConfig] — see that file to point this at
/// your Heroku server via a .env file.
class ApiService {
  static String get baseUrl => ApiConfig.baseUrl;

  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'hq_jwt_token';

  // ── Timeouts ──────────────────────────────────────────────────────────────
  // Mutating requests (POST/PUT that create records) get a LONGER timeout
  // and NO retries — retrying a POST would create duplicate records on the server.
  static const _mutateTimeout = Duration(seconds: 20); // join queue, book appt
  static const _readTimeout = Duration(seconds: 12); // GET requests
  static const _maxRetry = 2; // only for GET requests

  // ── Token helpers ─────────────────────────────────────────────────────────
  static Future<void> saveToken(String t) async =>
      _storage.write(key: _tokenKey, value: t);
  static Future<String?> getToken() async => _storage.read(key: _tokenKey);
  static Future<void> clearToken() async => _storage.delete(key: _tokenKey);

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
        if (i == retries)
          throw Exception('Connection timed out. Please check your network.');
        await Future.delayed(Duration(seconds: i + 1));
      } on SocketException {
        if (i == retries)
          throw Exception('No internet connection. Please check your network.');
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
  // `identifier` can be either an email or a phone number — the server
  // auto-detects which based on whether it contains '@' (see
  // authController.login). This used to always send the value under the
  // 'email' JSON key regardless of which the user actually typed, so
  // selecting "Phone" in the login screen's toggle and entering a phone
  // number silently failed every time (the server was searching by email
  // for a value that was never stored there).
  static Future<Map<String, dynamic>> login(
      String identifier, String password) async {
    final res = await _once(() => http.post(
          Uri.parse('$baseUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'identifier': identifier, 'password': password}),
        ));

    if (res.statusCode == 403) {
      Map<String, dynamic>? body;
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
      if (body != null &&
          body['requiresVerification'] == true &&
          body['userId'] != null) {
        throw OtpRequiredException(
          userId: body['userId'].toString(),
          phone: body['phone']?.toString() ?? '',
          message: body['message']?.toString() ??
              'Please verify your phone number before logging in.',
        );
      }
    }

    _assertOk(res, 'Login failed. Check your email and password.');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['token'] != null) await saveToken(data['token'] as String);
    return data;
  }

  static Future<Map<String, dynamic>> register(
      Map<String, dynamic> body) async {
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

  // Verifies the OTP the server texted via Semaphore, and saves the session
  // token the server returns once the code checks out.
  static Future<Map<String, dynamic>> verifyOtp(
      String userId, String otp) async {
    final res = await _once(() => http.post(
          Uri.parse('$baseUrl/auth/verify-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'userId': userId, 'otp': otp}),
        ));
    _assertOk(res, 'OTP verification failed.');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['token'] != null) await saveToken(data['token'] as String);
    return data;
  }

  // Asks the server to text a fresh OTP to the pending account.
  static Future<Map<String, dynamic>> resendOtp(String userId) async {
    final res = await _once(() => http.post(
          Uri.parse('$baseUrl/auth/resend-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'userId': userId}),
        ));
    _assertOk(res, 'Failed to resend OTP.');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Forgot Password ──────────────────────────────────────────────────────
  // Step 1: request an OTP be sent to a registered phone number.
  static Future<Map<String, dynamic>> forgotPassword(String phone) async {
    final res = await _once(() => http.post(
          Uri.parse('$baseUrl/auth/forgot-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'phone': phone}),
        ));
    _assertOk(res, 'Failed to send reset code.');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // Step 2: verify the OTP. Returns a resetToken (short-lived) that
  // authorizes the actual password change in step 3 — the OTP itself is
  // consumed the moment this succeeds and can't be reused.
  static Future<Map<String, dynamic>> verifyResetOtp(
      String resetId, String otp) async {
    final res = await _once(() => http.post(
          Uri.parse('$baseUrl/auth/verify-reset-otp'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'resetId': resetId, 'otp': otp}),
        ));
    _assertOk(res, 'Verification failed.');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // Step 3: set the new password using the resetToken from step 2.
  static Future<Map<String, dynamic>> resetPassword({
    required String resetId,
    required String resetToken,
    required String newPassword,
  }) async {
    final res = await _once(() => http.post(
          Uri.parse('$baseUrl/auth/reset-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'resetId': resetId,
            'resetToken': resetToken,
            'newPassword': newPassword,
          }),
        ));
    _assertOk(res, 'Failed to reset password.');
    return jsonDecode(res.body) as Map<String, dynamic>;
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

  static Future<Map<String, dynamic>> updateProfile(
      Map<String, dynamic> body) async {
    final headers = await _authHeaders();

    final res = await http
        .put(
          Uri.parse('$baseUrl/users/me/patient'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(_mutateTimeout);

    // IMPORTANT:
    // Do not silently ignore a failed update.
    _assertOk(res, 'Failed to update profile');

    final decoded = jsonDecode(res.body);

    if (decoded is Map<String, dynamic>) {
      // Some APIs return:
      // { user: {...} }
      if (decoded['user'] is Map) {
        return Map<String, dynamic>.from(decoded['user']);
      }

      // Some APIs return:
      // { patient: {...} }
      if (decoded['patient'] is Map) {
        return Map<String, dynamic>.from(decoded['patient']);
      }

      // Some APIs return the user directly.
      return decoded;
    }

    throw Exception('Invalid response from server.');
  }

  // ── Clinics ───────────────────────────────────────────────────────────────
  static Future<List<dynamic>> getClinicDirectory() async {
    final res = await _withRetry(() async => http.get(
        Uri.parse('$baseUrl/clinics/directory'),
        headers: await _authHeaders()));
    _assertOk(res, 'Failed to load clinics');
    final data = jsonDecode(res.body);
    if (data is List) return data;
    if (data is Map) return (data['clinics'] ?? data['data'] ?? []) as List;
    return [];
  }

  static Future<Map<String, dynamic>> getRecommendedClinics({
    String? service,
    double? lat,
    double? lng,
    String type = 'queue',
  }) async {
    final params = <String, String>{'type': type};
    if (service != null) params['service'] = service;
    if (lat != null) params['lat'] = lat.toString();
    if (lng != null) params['lng'] = lng.toString();
    final uri = Uri.parse('$baseUrl/clinics/recommend')
        .replace(queryParameters: params);
    final res = await _withRetry(
        () async => http.get(uri, headers: await _authHeaders()));
    _assertOk(res, 'Failed to load recommendations');
    final data = jsonDecode(res.body);
    return data is Map ? data as Map<String, dynamic> : {'clinics': data};
  }

  static Future<Map<String, dynamic>> getClinic(String id) async {
    final res = await _withRetry(() async => http
        .get(Uri.parse('$baseUrl/clinics/$id'), headers: await _authHeaders()));
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
            'clinicId': clinicId,
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
        Uri.parse('$baseUrl/queues/my-status'),
        headers: await _authHeaders()));
    if (res.statusCode == 404) return {'inQueue': false};
    _assertOk(res, 'Failed to get queue status');
    final decoded = jsonDecode(res.body);
    if (decoded is List) {
      final first = decoded.cast<dynamic>().whereType<Map>().toList();
      if (first.isEmpty) return {'inQueue': false};
      return {'inQueue': true, 'entry': Map<String, dynamic>.from(first.first)};
    }
    if (decoded is! Map) return {'inQueue': false};
    final data = Map<String, dynamic>.from(decoded);
    final entry = data['entry'] ?? data['queue'] ?? data['data'];
    if (entry is Map && data['entry'] == null) {
      data['entry'] = Map<String, dynamic>.from(entry);
    }
    if (data['inQueue'] == null) {
      data['inQueue'] = data['entry'] is Map;
    }
    return data;
  }

  // Cancel the patient's active queue entry.
  //
  // IMPORTANT:
  // Always get the current server-side queue ID first. This prevents an old
  // local ID from causing "Access denied" when the queue record has changed.
  //
  // Different HealthQueue backend versions may expose cancellation as:
  //   PUT    /queues/:id/cancel
  //   POST   /queues/:id/cancel
  //   DELETE /queues/:id/cancel
  //   PATCH  /queues/:id/cancel
  //   DELETE /queues/:id
  //   POST   /queues/cancel { queueId: ... }
  //
  // We only try an alternate route when the previous route explicitly says
  // that the route/method is not usable (403/404/405). A successful request
  // immediately returns so the cancellation is never duplicated.
  // ── Patient Type Request (Senior/PWD/Pregnant verification) ────────────────
  // Patients can no longer set their own patientType (see AppState —
  // updateCurrentUserProfile no longer sends it); this is the real channel:
  // submit a photo of the ID/certificate, staff review and approve/reject.
  // Maps a file extension to a MIME type the server's multer fileFilter
  // will accept (see middleware/upload.js's allowed list). Falls back to
  // image/jpeg — nearly every phone camera produces JPEG by default, and
  // an image_picker temp path with an unrecognized/missing extension is
  // far more likely to be a JPEG than anything else.
  static MediaType _imageContentType(String path) {
    final ext = path.toLowerCase().split('.').last;
    switch (ext) {
      case 'png':  return MediaType('image', 'png');
      case 'webp': return MediaType('image', 'webp');
      case 'heic': return MediaType('image', 'heic');
      case 'heif': return MediaType('image', 'heif');
      case 'jpg':
      case 'jpeg':
      default:     return MediaType('image', 'jpeg');
    }
  }

  static Future<Map<String, dynamic>> submitPatientTypeRequest({
    required String requestedType,
    required File photo,
  }) async {
    final uri = Uri.parse('$baseUrl/patient-type-requests');
    final req = http.MultipartRequest('POST', uri);
    // Only add Authorization here — NOT the rest of _authHeaders(), which
    // hardcodes 'Content-Type': 'application/json'. That was overwriting
    // the 'multipart/form-data; boundary=...' header MultipartRequest sets
    // automatically, so the server could never actually parse the body
    // (and the global JSON parser choked trying to read binary multipart
    // data as JSON, which is why the error came back as an unparseable
    // HTML page instead of a real message).
    final token = await getToken();
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.fields['requestedType'] = requestedType;
    // Explicitly set the content type from the file extension instead of
    // letting http.MultipartFile.fromPath() guess it — camera-captured
    // photos' temp file paths don't always have an extension the guesser
    // recognizes, in which case it silently falls back to
    // 'application/octet-stream'. The server correctly rejects that (it
    // can't be sure it's actually an image), but the real fix is to never
    // send an ambiguous content type in the first place.
    req.files.add(await http.MultipartFile.fromPath(
      'photo',
      photo.path,
      contentType: _imageContentType(photo.path),
    ));

    http.Response res;
    try {
      // Image uploads need more room than the general 20s mutate timeout —
      // given its own timeout here rather than reusing _once() (which
      // would apply a shorter one meant for small JSON payloads).
      final streamed = await req.send().timeout(const Duration(seconds: 45));
      res = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw Exception('The upload timed out. Please check your connection and try again.');
    } on SocketException {
      throw Exception('No internet connection. Please check your network.');
    }
    _assertOk(res, 'Failed to submit request.');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // getMyPatientTypeRequest -> GET /patient-type-requests/mine: the most
  // recent request (or null if none exists yet), so the app can show its
  // status (pending/approved/rejected) instead of the patient wondering
  // whether their submission went through.
  static Future<Map<String, dynamic>?> getMyPatientTypeRequest() async {
    final res = await _once(() async => http.get(
        Uri.parse('$baseUrl/patient-type-requests/mine'),
        headers: await _authHeaders()));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body);
    final data = body is Map ? body['data'] : null;
    return data is Map<String, dynamic> ? data : null;
  }

  // markOnTheWay -> PUT /queues/:id/on-the-way (patient-only). Does NOT
  // change queue status — only notifies staff (via socket) that the
  // patient acknowledged being called and is heading over. Fire-and-forget
  // from the caller's side; this method itself still surfaces errors so
  // callers can choose to ignore them.
  static Future<void> markOnTheWay(String id) async {
    final res = await _once(() async => http.put(
          Uri.parse('$baseUrl/queues/$id/on-the-way'),
          headers: await _authHeaders(),
        ));
    _assertOk(res, 'Failed to notify staff.');
  }

  static Future<bool> cancelQueue(String id) async {
    var queueId = id.trim();

    // Always prefer the ACTIVE server entry when available.
    // This fixes cases where the screen has an outdated/local queue ID.
    try {
      final status = await getMyQueueStatus();
      final entry = status['entry'] ?? status['queue'] ?? status['data'];
      if (entry is Map) {
        final serverId =
            (entry['_id'] ?? entry['id'] ?? entry['queueId'] ?? '').toString().trim();
        if (serverId.isNotEmpty) {
          queueId = serverId;
        }
      }

      // Nothing active means the queue has already been left/cancelled.
      if (status['inQueue'] != true && entry is! Map) {
        return true;
      }
    } catch (_) {
      // If status cannot be read, continue with the ID supplied by the UI.
    }

    if (queueId.isEmpty) {
      throw Exception(
        'No active queue was found. Please refresh Queue Status and try again.',
      );
    }

    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/queues/$queueId/cancel');

    Future<http.Response> request(
      String method,
      Uri requestUri, {
      Map<String, String>? requestHeaders,
      Object? body,
    }) async {
      final h = requestHeaders ?? headers;
      switch (method) {
        case 'PUT':
          return http.put(requestUri, headers: h, body: body).timeout(_mutateTimeout);
        case 'POST':
          return http.post(requestUri, headers: h, body: body).timeout(_mutateTimeout);
        case 'DELETE':
          return http.delete(requestUri, headers: h, body: body).timeout(_mutateTimeout);
        case 'PATCH':
          return http.patch(requestUri, headers: h, body: body).timeout(_mutateTimeout);
        default:
          throw Exception('Unsupported cancellation method.');
      }
    }

    String responseMessage(http.Response res) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          return (decoded['message'] ??
                  decoded['error'] ??
                  decoded['detail'] ??
                  '')
              .toString();
        }
      } catch (_) {}
      return '';
    }

    try {
      // Normal/current backend route.
      var res = await request('PUT', uri);

      if (res.statusCode >= 200 && res.statusCode < 300) return true;
      if (res.statusCode == 409 || res.statusCode == 410) return true;

      // Some deployments protect PUT but expose cancellation through POST,
      // DELETE, or PATCH instead. Try those only when the first route is
      // rejected by the backend.
      if (res.statusCode == 403 ||
          res.statusCode == 404 ||
          res.statusCode == 405) {
        final alternateRequests = <Future<http.Response> Function()>[
          () => request('POST', uri),
          () => request('DELETE', uri),
          () => request('PATCH', uri),
          () => request(
                'DELETE',
                Uri.parse('$baseUrl/queues/$queueId'),
              ),
          () => request(
                'POST',
                Uri.parse('$baseUrl/queues/cancel'),
                body: jsonEncode({'queueId': queueId, 'id': queueId}),
              ),
          () => request(
                'PUT',
                Uri.parse('$baseUrl/queues/cancel'),
                body: jsonEncode({'queueId': queueId, 'id': queueId}),
              ),
        ];

        for (final send in alternateRequests) {
          try {
            res = await send();

            if (res.statusCode >= 200 && res.statusCode < 300) {
              return true;
            }
            if (res.statusCode == 409 || res.statusCode == 410) {
              return true;
            }
          } on TimeoutException {
            // Do not send another mutation after a timeout because the server
            // may already have accepted the request.
            throw Exception(
              'Cancellation timed out. Please refresh Queue Status before trying again.',
            );
          } on SocketException {
            throw Exception(
              'No internet connection. Please check your network.',
            );
          }
        }

        // Verify the server state after all supported routes were rejected.
        // If the active queue disappeared, cancellation succeeded.
        try {
          final status = await getMyQueueStatus();
          final entry = status['entry'] ?? status['queue'] ?? status['data'];
          if (status['inQueue'] != true && entry is! Map) {
            return true;
          }
        } catch (_) {}
      }

      final serverMessage = responseMessage(res);

      if (res.statusCode == 401) {
        throw Exception(
          'Your session has expired. Please log in again before leaving the queue.',
        );
      }

      if (res.statusCode == 403) {
        throw Exception(
          serverMessage.isNotEmpty
              ? serverMessage
              : 'Access denied by the server. The logged-in account is not allowed to cancel this queue entry.',
        );
      }

      throw Exception(
        serverMessage.isNotEmpty
            ? serverMessage
            : 'The server could not cancel queue #$queueId (HTTP ${res.statusCode}).',
      );
    } on TimeoutException {
      throw Exception(
        'Cancellation timed out. Please refresh Queue Status before trying again.',
      );
    } on SocketException {
      throw Exception('No internet connection. Please check your network.');
    }
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
        Uri.parse('$baseUrl/appointments/my'),
        headers: await _authHeaders()));
    _assertOk(res, 'Failed to load appointments');
    final data = jsonDecode(res.body);
    if (data is List) return data;
    if (data is Map)
      return (data['appointments'] ?? data['data'] ?? []) as List;
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
      throw Exception(b['message'] ??
          'This time slot is already booked. Please choose another.');
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
    required String clinicId,
    required String date,
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
    // Uses its own longer timeout rather than the shared _mutateTimeout
    // (20s) — the server itself now waits up to 20s for a cold-starting
    // Rasa instance to respond (see chatbotController.handleMessage), so
    // reusing the same 20s here would let the client give up right as the
    // server was about to succeed. This only affects sendChatMessage, not
    // other actions like joining a queue or booking an appointment.
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/chatbot/message'),
            headers: await _authHeaders(),
            body: jsonEncode({'message': message}),
          )
          .timeout(const Duration(seconds: 30));
      _assertOk(res, 'Chatbot error');
      return jsonDecode(res.body) as Map<String, dynamic>;
    } on TimeoutException {
      throw Exception(
        'The chatbot is taking longer than usual to respond. Please try again.',
      );
    } on SocketException {
      throw Exception('No internet connection. Please check your network.');
    }
  }

  // GET /chatbot/history — the patient's own conversation history for the
  // last 7 days (server-enforced retention — see ChatLog's TTL index).
  // Each item is one exchange: { message, reply, createdAt, ... }.
  static Future<List<dynamic>> getChatHistory() async {
    final res = await _withRetry(() async => http.get(
        Uri.parse('$baseUrl/chatbot/history'),
        headers: await _authHeaders()));
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body);
    if (data is List) return data;
    if (data is Map) return (data['data'] ?? data['history'] ?? []) as List;
    return [];
  }

  // Result of an escalation attempt. `ok` is true only when the server
  // actually escalated. `requiresClinic` distinguishes "you need to pick a
  // clinic first" from a generic failure so the UI can show the right nudge.
  static Future<({bool ok, bool requiresClinic, String? message})> escalateChatbot({
    String? logId,
    String? note,
    String? clinicId,
  }) async {
    try {
      final res = await _once(() async => http.post(
            Uri.parse('$baseUrl/chatbot/escalate'),
            headers: await _authHeaders(),
            body: jsonEncode({
              if (logId != null) 'logId': logId,
              if (clinicId != null && clinicId.isNotEmpty) 'clinicId': clinicId,
              'note': note ?? '',
            }),
          ));
      Map<String, dynamic>? body;
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      return (
        ok: ok,
        requiresClinic: body?['requiresClinic'] == true,
        message: body?['message']?.toString(),
      );
    } catch (_) {
      return (ok: false, requiresClinic: false, message: null);
    }
  }

  // ── Notifications ─────────────────────────────────────────────────────────
  static Future<List<dynamic>> getNotifications() async {
    try {
      final res = await _withRetry(() async => http.get(
          Uri.parse('$baseUrl/notifications'),
          headers: await _authHeaders()));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);
      if (data is List) return data;
      if (data is Map)
        return (data['notifications'] ?? data['data'] ?? []) as List;
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<bool> markNotificationRead(String id) async {
    try {
      final res = await _once(() async => http.put(
          Uri.parse('$baseUrl/notifications/$id/read'),
          headers: await _authHeaders()));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> markAllNotificationsRead() async {
    try {
      final res = await _once(() async => http.put(
          Uri.parse('$baseUrl/notifications/read-all'),
          headers: await _authHeaders()));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Calls the Prescriptive Analytics Engine with optional patient inputs.
  static Future<Map<String, dynamic>> evaluatePrescription({
    double? lat,
    double? lng,
    String purpose = '',
    String symptoms = '',
    String patientType = 'Regular',
  }) async {
    final params = <String, String>{
      if (lat != null) 'lat': lat.toString(),
      if (lng != null) 'lng': lng.toString(),
      if (purpose.isNotEmpty) 'purpose': purpose,
      if (symptoms.isNotEmpty) 'symptoms': symptoms,
      if (patientType.isNotEmpty) 'patientType': patientType,
    };
    final uri = Uri.parse('$baseUrl/prescriptive/evaluate')
        .replace(queryParameters: params);
    final res = await _withRetry(
        () async => http.get(uri, headers: await _authHeaders()));
    _assertOk(res, 'Failed to evaluate prescription.');
    final data = jsonDecode(res.body);
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  /// Returns best historical time to queue at a given clinic.
  static Future<Map<String, dynamic>> getBestTimeToQueue(
      String clinicId) async {
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
            'newPassword': newPassword,
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
  @override
  String toString() => message;
}
