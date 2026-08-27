import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/queue_socket_service.dart';
import '../models/appointment_models.dart';
import '../models/queue_models.dart';
import '../models/chat_models.dart';
import '../models/user_models.dart';

class AppState extends ChangeNotifier {
  /* ─────────────────────────────────────────────────────────
     AUTH
  ───────────────────────────────────────────────────────── */

  AppUser? _currentUser;
  bool _isAuthLoading = false;
  bool _isLoading = false;

  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isAuthLoading => _isAuthLoading;
  bool get isLoading => _isAuthLoading || _isLoading;

  Future<bool> restoreSession() async {
    final token = await ApiService.getToken();

    if (token == null || token.isEmpty) {
      return false;
    }

    try {
      final data = await ApiService.getMe();

      _currentUser = _userFromMap(data);

      await Future.wait([
        fetchAppointments(),
        fetchQueueStatus(),
      ]);

      notifyListeners();
      return true;
    } catch (_) {
      await ApiService.clearToken();
      _currentUser = null;
      notifyListeners();
      return false;
    }
  }

  Future<void> login({
    required String identifier,
    required String password,
  }) async {
    _isAuthLoading = true;
    notifyListeners();

    try {
      final data = await ApiService.login(
        identifier,
        password,
      );

      _currentUser = _userFromMap(
        data['user'] ?? data,
      );

      await Future.wait([
        fetchAppointments(),
        fetchQueueStatus(),
      ]);
    } finally {
      _isAuthLoading = false;
      notifyListeners();
    }
  }

  /* ─────────────────────────────────────────────────────────
     REGISTER
  ───────────────────────────────────────────────────────── */

  Future<void> register(Map<String, dynamic> body) async {
    _isLoading = true;
    notifyListeners();

    final oldToken = await ApiService.getToken();

    // IMPORTANT:
    // Remove old patient's token before registering.
    await ApiService.clearToken();

    try {
      final data = await ApiService.register(body);

      final newToken = await ApiService.getToken();

      if (newToken == null || newToken.isEmpty) {
        final email = body['email']?.toString().trim() ?? '';
        final password = body['password']?.toString() ?? '';

        if (email.isNotEmpty && password.isNotEmpty) {
          final loginData = await ApiService.login(
            email,
            password,
          );

          _currentUser = _userFromMap(
            loginData['user'] ?? loginData,
            fallback: body,
          );
        } else {
          _currentUser = _userFromMap(
            data['user'] ?? data,
            fallback: body,
          );
        }
      } else {
        _currentUser = _userFromMap(
          data['user'] ?? data,
          fallback: body,
        );
      }

      await Future.wait([
        fetchAppointments(),
        fetchQueueStatus(),
      ]);

      // The register/login response above may not carry every profile
      // field (e.g. dateOfBirth lives on the Patient record, not on every
      // server version's register/login payload). Pull /auth/me once the
      // session is established so the Profile screen shows the real,
      // server-side value rather than whatever subset came back locally.
      await refreshProfile();
    } catch (e) {
      // Restore old token only when registration failed.
      if (oldToken != null && await ApiService.getToken() == null) {
        await ApiService.saveToken(oldToken);
      }

      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Step 1 of phone-verified registration: creates the (unverified) account
  // and has the server text an OTP via Semaphore. Returns the server's raw
  // response (userId, message, and devOtp when running in SMS-mock mode) so
  // the OTP screen can show it — otherwise a mock-mode registration leaves
  // the user staring at an OTP field with no way to know the code.
  Future<Map<String, dynamic>> beginRegistration(Map<String, dynamic> body) async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.register(body);
      final userId = data['userId']?.toString();
      if (userId == null || userId.isEmpty) {
        throw Exception('Registration succeeded but no user ID was returned.');
      }
      return data;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Step 2: verifies the OTP against the server, then logs the now-verified
  // patient in using the token the server returns.
  Future<void> completeRegistration({
    required String userId,
    required String otp,
    required Map<String, dynamic> fallback,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.verifyOtp(userId, otp);
      _currentUser = _userFromMap(data['user'] ?? data, fallback: fallback);

      await Future.wait([
        fetchAppointments(),
        fetchQueueStatus(),
      ]);

      // verify-otp's response only carries the bare User record (no
      // dateOfBirth, etc.) — the `fallback` above covers most cases, but
      // relies on this screen instance having collected the original form
      // data. When it hasn't (e.g. resuming verification for an account
      // that registered earlier, then came back through Login), fallback
      // is empty and dateOfBirth would otherwise be lost until some later
      // refresh. Pulling /auth/me here guarantees the Profile screen has
      // the real, server-side value the moment registration finishes.
      await refreshProfile();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> resendOtp(String userId) =>
      ApiService.resendOtp(userId);

  Future<void> registerUser({
    required String fullName,
    required String email,
    required String phone,
    required DateTime dob,
    String gender = '',
    required String password,
  }) async {
    await register({
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'dateOfBirth': dob.toIso8601String(),
      'gender': gender,
      'password': password,
      'role': 'patient',
    });
  }

  /* ─────────────────────────────────────────────────────────
     USER CONVERSION
  ───────────────────────────────────────────────────────── */

  AppUser _userFromMap(
    dynamic u, {
    Map<String, dynamic>? fallback,
    AppUser? existing,
  }) {
    final m = u is Map ? Map<String, dynamic>.from(u) : <String, dynamic>{};

    final f = fallback ?? {};

    // Existing values are used when the server response does not
    // contain a particular field.
    final fullName = _firstNonEmpty([
      m['fullName'],
      f['fullName'],
      existing?.fullName,
    ]);

    final email = _firstNonEmpty([
      m['email'],
      f['email'],
      existing?.email,
    ]);

    final phone = _firstNonEmpty([
      m['phone'],
      f['phone'],
      existing?.phone,
    ]);

    final gender = _firstNonEmpty([
      m['gender'],
      f['gender'],
      existing?.gender,
    ]);

    final patientType = _firstNonEmpty([
      m['patientType'],
      f['patientType'],
      existing?.patientType,
    ], defaultValue: 'Regular');

    final patientId = _firstNonEmpty([
      m['patientId'],
      f['patientId'],
      existing?.patientId,
    ]);

    final philHealthNumber = _firstNonEmpty([
      m['philHealthNumber'],
      f['philHealthNumber'],
      existing?.philHealthNumber,
    ]);

    final hmoNumber = _firstNonEmpty([
      m['hmoNumber'],
      f['hmoNumber'],
      existing?.hmoNumber,
    ]);

    /* ---------------- DOB ---------------- */

    final serverDob = _parseDob(
      m['dob'] ?? m['dateOfBirth'] ?? f['dob'] ?? f['dateOfBirth'],
    );

    final finalDob = serverDob ??
        (existing?.dob.year != null && existing!.dob.year > 1900
            ? existing.dob
            : DateTime(2000));

    /* ---------------- AGE ---------------- */

    String finalAge = _firstNonEmpty([
      m['age'],
      f['age'],
      existing?.age,
    ]);

    // If server does not return age, calculate it from DOB.
    if (finalAge.isEmpty && finalDob.year > 1900) {
      finalAge = _ageFromDob(finalDob);
    }

    return AppUser(
      id: _firstNonEmpty([
        m['_id'],
        m['id'],
        f['_id'],
        f['id'],
        existing?.id,
      ]),
      fullName: fullName,
      email: email,
      phone: phone,
      dob: finalDob,
      gender: gender,
      password: '',
      patientType: patientType,
      patientId: patientId,
      age: finalAge,
      philHealthNumber: philHealthNumber,
      hmoNumber: hmoNumber,
    );
  }

  String _firstNonEmpty(
    List<dynamic> values, {
    String defaultValue = '',
  }) {
    for (final value in values) {
      if (value == null) continue;

      final text = value.toString().trim();

      if (text.isNotEmpty) {
        return text;
      }
    }

    return defaultValue;
  }

  static DateTime? _parseDob(dynamic value) {
    if (value is DateTime) {
      return value;
    }

    if (value is Map) {
      final nested = value[r'$date'] ?? value['date'] ?? value['value'];

      if (nested != null) {
        return _parseDob(nested);
      }
    }

    return DateTime.tryParse(
      value?.toString() ?? '',
    );
  }

  static String _ageFromDob(DateTime? dob) {
    if (dob == null || dob.year <= 1900) {
      return '';
    }

    final now = DateTime.now();

    int age = now.year - dob.year;

    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }

    return age >= 0 ? age.toString() : '';
  }

  /* ─────────────────────────────────────────────────────────
     LOGOUT
  ───────────────────────────────────────────────────────── */

  Future<void> logout() async {
    await ApiService.clearToken();

    _currentUser = null;
    _appointments = [];
    _currentQueue = null;
    _chatMessages = [];
    _chatHistoryLoaded = false;
    _pendingCallPopup = null;
    _queueSocket.disconnect();

    notifyListeners();
  }

  /* ─────────────────────────────────────────────────────────
     REFRESH PROFILE
  ───────────────────────────────────────────────────────── */

  Future<void> refreshProfile() async {
    try {
      final data = await ApiService.getMe();

      final oldUser = _currentUser;

      final merged = <String, dynamic>{
        ...data,

        // Keep existing values if /auth/me doesn't return them.
        'fullName': data['fullName'] ?? oldUser?.fullName ?? '',

        'email': data['email'] ?? oldUser?.email ?? '',

        'phone': data['phone'] ?? oldUser?.phone ?? '',

        'gender': data['gender'] ?? oldUser?.gender ?? '',

        'patientType': data['patientType'] ?? oldUser?.patientType ?? 'Regular',

        'philHealthNumber':
            data['philHealthNumber'] ?? oldUser?.philHealthNumber ?? '',

        'hmoNumber': data['hmoNumber'] ?? oldUser?.hmoNumber ?? '',

        'age': data['age'] ?? oldUser?.age ?? '',

        'dateOfBirth': data['dateOfBirth'] ??
            data['dob'] ??
            oldUser?.dob.toIso8601String(),
      };

      _currentUser = _userFromMap(merged);

      notifyListeners();

      debugPrint(
        'PROFILE REFRESHED - HMO: ${_currentUser?.hmoNumber}',
      );
    } catch (e) {
      debugPrint('refreshProfile error: $e');
    }
  }

  /* ─────────────────────────────────────────────────────────
     UPDATE PROFILE
  ───────────────────────────────────────────────────────── */

  Future<void> updateCurrentUserProfile({
    String? fullName,
    String? phone,
    String? age,
    String? gender,
    DateTime? dob,
    String? patientType,
    String? philHealthNumber,
    String? hmoNumber,
  }) async {
    if (_currentUser == null) {
      throw Exception('No logged-in user.');
    }

    final oldUser = _currentUser!;

    try {
      final body = <String, dynamic>{
        if (fullName != null) 'fullName': fullName,
        if (phone != null) 'phone': phone,
        if (age != null) 'age': age,
        if (gender != null) 'gender': gender,
        if (dob != null) 'dateOfBirth': dob.toIso8601String(),
        if (patientType != null) 'patientType': patientType,
        if (philHealthNumber != null) 'philHealthNumber': philHealthNumber,
        if (hmoNumber != null) 'hmoNumber': hmoNumber,
      };

      debugPrint('PROFILE UPDATE BODY: $body');

      final updatedUser = await ApiService.updateProfile(body);

      /*
     * Some backend versions don't return all patient fields
     * after updating. Therefore, keep the old values when the
     * server response does not contain them.
     */
      final merged = <String, dynamic>{
        ...updatedUser,
        'fullName': updatedUser['fullName'] ?? oldUser.fullName,
        'email': updatedUser['email'] ?? oldUser.email,
        'phone': updatedUser['phone'] ?? oldUser.phone,
        'gender': updatedUser['gender'] ?? oldUser.gender,
        'patientType': updatedUser['patientType'] ?? oldUser.patientType,
        'philHealthNumber':
            updatedUser['philHealthNumber'] ?? oldUser.philHealthNumber,
        'hmoNumber': updatedUser['hmoNumber'] ?? oldUser.hmoNumber,
        'age': updatedUser['age'] ?? oldUser.age,
        'dateOfBirth': updatedUser['dateOfBirth'] ??
            updatedUser['dob'] ??
            oldUser.dob.toIso8601String(),
      };

      _currentUser = _userFromMap(merged);

      notifyListeners();

      /*
     * Get the latest data from the server after updating.
     * This makes sure the Profile screen reflects the database.
     */
      await refreshProfile();
    } catch (e) {
      debugPrint('Profile update failed: $e');
      rethrow;
    }
  }
  /* ─────────────────────────────────────────────────────────
     APPOINTMENTS
  ───────────────────────────────────────────────────────── */

  List<Appointment> _appointments = [];
  bool _apptLoading = false;

  List<Appointment> get appointments => List.unmodifiable(_appointments);

  bool get apptLoading => _apptLoading;

  List<Appointment> get upcomingAppointments =>
      _appointments.where((a) => a.isUpcoming).toList();

  List<Appointment> get pastAppointments =>
      _appointments.where((a) => a.isPast).toList();

  Future<void> fetchAppointments() async {
    _apptLoading = true;
    notifyListeners();

    try {
      final list = await ApiService.getMyAppointments();

      _appointments = list.map((raw) {
        final m = raw as Map<String, dynamic>;

        String clinicName = '';

        if (m['clinic'] is Map) {
          clinicName = (m['clinic'] as Map)['name']?.toString() ?? '';
        } else if (m['clinicId'] is Map) {
          clinicName = (m['clinicId'] as Map)['name']?.toString() ?? '';
        } else if (m['clinicName'] is String) {
          clinicName = m['clinicName'] as String;
        }

        String serviceName = '';

        if (m['serviceName'] is String) {
          serviceName = m['serviceName'] as String;
        } else if (m['serviceId'] is Map) {
          serviceName = (m['serviceId'] as Map)['name']?.toString() ?? '';
        } else if (m['department'] is String) {
          serviceName = m['department'] as String;
        }

        String doctorName = '';

        if (m['staff'] is Map) {
          doctorName = (m['staff'] as Map)['fullName']?.toString() ?? '';
        } else if (m['staffId'] is Map) {
          doctorName = (m['staffId'] as Map)['fullName']?.toString() ?? '';
        } else if (m['doctor'] is String) {
          doctorName = m['doctor'] as String;
        }

        return Appointment(
          id: m['_id']?.toString() ?? m['id']?.toString() ?? '',
          clinicName: clinicName,
          department: serviceName,
          doctor: doctorName,
          date: DateTime.tryParse(
                m['appointmentDate']?.toString() ?? m['date']?.toString() ?? '',
              ) ??
              DateTime.now(),
          timeLabel:
              m['timeSlot']?.toString() ?? m['timeLabel']?.toString() ?? '',
          status: Appointment.parseStatus(
            m['status']?.toString(),
          ),
          notes: m['notes']?.toString() ?? '',
        );
      }).toList();
    } catch (e) {
      debugPrint(
        'fetchAppointments error: $e',
      );
    } finally {
      _apptLoading = false;
      notifyListeners();
    }
  }

  void addAppointment(
    Appointment appt,
  ) {
    _appointments.insert(
      0,
      appt,
    );

    notifyListeners();

    fetchAppointments();
  }

  void updateAppointment(
    String id, {
    AppointmentStatus? status,
    DateTime? date,
    String? timeLabel,
    String? notes,
  }) {
    final idx = _appointments.indexWhere(
      (a) => a.id == id,
    );

    if (idx == -1) {
      return;
    }

    _appointments[idx] = _appointments[idx].copyWith(
      status: status,
      date: date,
      timeLabel: timeLabel,
      notes: notes,
    );

    notifyListeners();

    if (status == AppointmentStatus.cancelled) {
      ApiService.cancelAppointment(
        id,
      ).catchError(
        (_) => false,
      );
    }

    fetchAppointments();
  }

  /* ─────────────────────────────────────────────────────────
     QUEUE
  ───────────────────────────────────────────────────────── */

  QueueEntry? _currentQueue;
  bool _queueLoading = false;
  // Only trust a freshly-joined local queue for a short grace period —
  // long enough for the very next poll to confirm it server-side, but not
  // so long that it masks a real completion/cancellation. Previously the
  // null-entry branch in fetchQueueStatus() never actually cleared a
  // populated _currentQueue, so once the server correctly stopped
  // returning a completed/cancelled entry (see getMyQueueStatus — it only
  // matches status waiting/called/serving), the screen kept showing the
  // last known state ("serving") forever.
  DateTime? _localQueueSetAt;

  // Single shared Socket.IO connection for real-time queue updates, owned
  // here (rather than per-screen) so it stays live across the whole app —
  // previously only QueueMonitoringScreen opened a socket, so patients on
  // any other tab (Dashboard, Chat, etc.) never got a push update at all
  // and had to wait for that screen's own periodic poll.
  final QueueSocketService _queueSocket = QueueSocketService();

  // Set the instant the server reports a transition into `called`; cleared
  // by the UI via dismissCallPopup() once it has shown the popup. This is
  // the one-shot signal the global popup (see AppShell) watches for — the
  // edge-detection in fetchQueueStatus() (comparing wasCalled vs isCalled)
  // is what actually prevents duplicate popups for the same call event.
  QueueEntry? _pendingCallPopup;

  QueueEntry? get pendingCallPopup => _pendingCallPopup;

  void dismissCallPopup() {
    _pendingCallPopup = null;
    notifyListeners();
  }

  QueueEntry? get currentQueue => _currentQueue;

  bool get queueLoading => _queueLoading;

  List<QueueEntry> get activeQueues =>
      _currentQueue == null ? [] : [_currentQueue!];

  // True once the patient has actually picked a clinic — either by joining
  // its queue or booking an appointment there. Mirrors the server's own
  // resolvePatientClinicId fallback (queue entry, then appointment), and
  // gates whether the chatbot is allowed to escalate to staff.
  bool get hasSelectedClinic =>
      _currentQueue != null || upcomingAppointments.isNotEmpty;

  // Local notifications are used for immediate in-app feedback for actions
  // such as leaving a queue. The server notification (if created by the
  // backend) will still appear normally through ApiService.getNotifications().
  final List<Map<String, dynamic>> _localNotifications = [];

  List<Map<String, dynamic>> get localNotifications =>
      List.unmodifiable(_localNotifications);

  void addLocalNotification({
    required String type,
    required String title,
    required String message,
  }) {
    _localNotifications.insert(0, {
      '_id': 'local_${DateTime.now().microsecondsSinceEpoch}',
      'type': type,
      'title': title,
      'message': message,
      'isRead': false,
      'createdAt': DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

  void markLocalNotificationRead(String id) {
    final index = _localNotifications.indexWhere((n) => n['_id'] == id);
    if (index == -1) return;
    _localNotifications[index] = {
      ..._localNotifications[index],
      'isRead': true,
    };
    notifyListeners();
  }

  ActiveQueueStatus get currentQueueStatus {
    if (_currentQueue == null) {
      return ActiveQueueStatus.none();
    }

    return ActiveQueueStatus.fromQueueEntry(
      _currentQueue!,
    );
  }

  Future<void> fetchQueueStatus() async {
    _queueLoading = true;
    notifyListeners();

    // Captured before any reassignment below, so we can detect the exact
    // moment the server transitions this patient into `called` — used for
    // the one-shot popup notification (see _pendingCallPopup below).
    final wasCalled = _currentQueue?.isCalled ?? false;

    try {
      final data = await ApiService.getMyQueueStatus();

      // The API can return the queue under entry, queue, or data.
      // Normalize all of those shapes before reading the values.
      dynamic rawEntry = data['entry'] ?? data['queue'] ?? data['data'];

      if (rawEntry is List && rawEntry.isNotEmpty) {
        rawEntry = rawEntry.first;
      }

      // Do not erase a queue that was just saved locally when the server
      // response is temporarily incomplete — but only within a short grace
      // period after joining. Past that, a null entry means the queue
      // genuinely ended (completed/cancelled/no-show), so trust the server.
      if (rawEntry is! Map) {
        final withinGracePeriod = _localQueueSetAt != null &&
            DateTime.now().difference(_localQueueSetAt!) < const Duration(seconds: 8);
        if (!withinGracePeriod) {
          _currentQueue = null;
          // No active queue left to watch — release the socket connection
          // instead of leaving it idly joined to a clinic room.
          _queueSocket.disconnect();
        }
        return;
      }

      final e = Map<String, dynamic>.from(rawEntry);

      String clinicIdStr = '';
      String clinicName = '';
      dynamic clinic = e['clinic'];

      if (clinic is Map) {
        clinicIdStr = clinic['_id']?.toString() ?? clinic['id']?.toString() ?? '';
        clinicName = clinic['name']?.toString() ??
            clinic['clinicName']?.toString() ??
            '';
      } else if (clinic != null) {
        // Some responses send just the raw clinic id string instead of a
        // populated object.
        clinicIdStr = clinic.toString();
      }
      if (clinicIdStr.isEmpty && e['clinicId'] != null) {
        clinicIdStr = e['clinicId'].toString();
      }
      if (e['clinicName'] != null) {
        clinicName = e['clinicName'].toString();
      }

      String serviceName =
          e['serviceName']?.toString() ?? e['service']?.toString() ?? '';

      int toInt(dynamic value, {int fallback = 0}) {
        if (value == null) return fallback;
        if (value is int) return value;
        if (value is num) return value.round();
        return int.tryParse(value.toString()) ?? fallback;
      }

      final wait = toInt(
        data['estimatedWaitTime'] ??
            data['estimatedWaitMinutes'] ??
            data['estimatedWait'] ??
            e['estimatedWaitTime'] ??
            e['estimatedWaitMinutes'] ??
            e['estimatedWait'],
      );

      // Some APIs expose position, while others expose peopleAhead.
      // If only peopleAhead is available, the user's position is ahead + 1.
      final peopleAheadValue = data['peopleAhead'] ?? e['peopleAhead'];
      final positionValue = data['position'] ?? e['position'];

      final ahead = toInt(peopleAheadValue, fallback: -1);
      final position = toInt(
        positionValue,
        fallback: ahead >= 0 ? ahead + 1 : 1,
      );

      DateTime joinedAt = DateTime.now();
      final joinedRaw = e['joinedAt'] ?? e['createdAt'];
      if (joinedRaw != null) {
        joinedAt = DateTime.tryParse(joinedRaw.toString()) ?? joinedAt;
      }

      final queueId = e['_id']?.toString() ?? e['id']?.toString() ?? '';

      DateTime? graceExpiry = DateTime.tryParse(
        e['gracePeriodExpiresAt']?.toString() ?? '',
      );

      _currentQueue = QueueEntry(
        id: queueId,
        queueNumber:
            e['queueNumber']?.toString() ?? e['queueNo']?.toString() ?? 'N/A',
        clinicId: clinicIdStr,
        clinicName: clinicName,
        serviceName: serviceName,
        patientName: _currentUser?.fullName ?? '',
        patientEmail: _currentUser?.email,
        patientPhone: _currentUser?.phone,
        status: QueueEntry.parseStatus(e['status']?.toString()),
        position: position,
        totalAhead: ahead >= 0 ? ahead : position,
        estimatedWait: wait,
        estimatedWaitTimeMinutes: wait,
        joinedAt: joinedAt,
        queueType: QueueType.regular,
        departmentId: e['departmentId']?.toString(),
        departmentName: e['departmentName']?.toString(),
        serviceId: e['serviceId']?.toString(),
        doctorId: e['doctorId']?.toString(),
        doctorName: e['doctorName']?.toString(),
        gracePeriodExpiresAt: graceExpiry,
      );
      // We now have a confirmed server entry, so the post-join optimism
      // window is no longer needed — the next null response should be
      // trusted immediately.
      _localQueueSetAt = null;

      // Keep the shared socket connected to this queue's clinic room.
      // QueueSocketService.connect() already no-ops if it's already
      // connected to the same clinic, so calling this on every fetch
      // (poll or socket-triggered) never creates duplicate connections
      // or duplicate listeners.
      if (clinicIdStr.isNotEmpty) {
        _queueSocket.connect(
          clinicIdStr,
          onQueueUpdated: (_) => fetchQueueStatus(),
        );
      }

      // Fire the "you're being called" popup exactly once per call event —
      // only on the transition INTO `called`, never while it stays called
      // across repeated polls/socket pings within the same session.
      if (!wasCalled && _currentQueue!.isCalled) {
        _pendingCallPopup = _currentQueue;
      }
    } catch (e) {
      debugPrint('fetchQueueStatus error: $e');
      // Keep the locally saved queue instead of replacing it with null.
    } finally {
      _queueLoading = false;
      notifyListeners();
    }
  }

  void addQueueFromJoinResult(QueueJoinResult result) {
    _currentQueue = QueueEntry(
      id: result.entryId.isNotEmpty ? result.entryId : result.id,
      queueNumber: result.queueNumber,
      clinicId: result.clinicId,
      clinicName: result.clinicName,
      serviceName: result.serviceName,
      patientName: _currentUser?.fullName ?? result.patientName,
      patientEmail: _currentUser?.email ?? result.patientEmail,
      patientPhone: _currentUser?.phone ?? result.patientPhone,
      status: QueueStatus.waiting,
      position: result.position > 0 ? result.position : 1,
      totalAhead: result.totalAhead,
      estimatedWait: result.estimatedWait,
      estimatedWaitTimeMinutes: result.estimatedWaitTimeMinutes,
      joinedAt: result.joinedAt,
      queueType: result.queueType,
      departmentId: result.departmentId,
      departmentName: result.departmentName,
      serviceId: result.serviceId,
      doctorId: result.doctorId,
      doctorName: result.doctorName,
    );
    _localQueueSetAt = DateTime.now();

    // Connect immediately at join time rather than waiting for the next
    // poll/refresh — no-ops if already connected to this clinic.
    if (result.clinicId.isNotEmpty) {
      _queueSocket.connect(
        result.clinicId,
        onQueueUpdated: (_) => fetchQueueStatus(),
      );
    }

    notifyListeners();
  }

  Future<bool> cancelQueue(
    String id,
  ) async {
    // Keep this method for callers that want AppState to perform the API call.
    // QueueMonitoringScreen uses cancelQueueLocally() after it has already
    // called ApiService.cancelQueue(), so the request is never sent twice.
    final ok = await ApiService.cancelQueue(id);

    if (ok) {
      cancelQueueLocally();
    }

    return ok;
  }

  void cancelQueueLocally() {
    _currentQueue = null;
    _localQueueSetAt = null;
    _pendingCallPopup = null;
    _queueSocket.disconnect();
    notifyListeners();
  }

  /* ─────────────────────────────────────────────────────────
     CHAT
  ───────────────────────────────────────────────────────── */

  List<ChatMessage> _chatMessages = [];
  bool _chatLoading = false;

  List<ChatMessage> get messages => List.unmodifiable(
        _chatMessages,
      );

  List<ChatMessage> get chatMessages => messages;

  bool get chatLoading => _chatLoading;

  void addChatMessage(
    ChatMessage msg,
  ) {
    _chatMessages.add(msg);
    notifyListeners();
  }

  void addBotText(
    String text, {
    List<String> quickReplies = const [],
  }) {
    _chatMessages.add(
      ChatMessage(
        text: text,
        isUser: false,
        timestamp: DateTime.now(),
        quickReplies: quickReplies,
      ),
    );

    notifyListeners();
  }

  void addUserText(
    String text,
  ) {
    _chatMessages.add(
      ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ),
    );

    notifyListeners();
  }

  bool get isChatLoading => _chatLoading;

  void setChatLoading(
    bool v,
  ) {
    _chatLoading = v;
    notifyListeners();
  }

  void seedChatIfEmpty() {
    if (_chatMessages.isNotEmpty) {
      return;
    }

    addBotText(
      "Hi! I'm HQ Assistant 👋\n"
      "How can I help you today?",
      quickReplies: [
        'Check my queue',
        'Book appointment',
        'Find a clinic',
        'Wait time',
      ],
    );
  }

  bool _chatHistoryLoaded = false;

  // Loads the patient's last 7 days of chatbot conversation from the server
  // (GET /chatbot/history) so it's available again after closing the chat
  // screen or restarting the app, instead of only living in memory for the
  // current session. Each ChatLog entry becomes a user bubble + bot reply
  // bubble, in chronological order, matching how they were actually sent.
  // Only fetched once per app session — calling this repeatedly (e.g. every
  // time the chat screen opens) would keep prepending/duplicating history.
  Future<void> loadChatHistory() async {
    if (_chatHistoryLoaded) return;
    _chatHistoryLoaded = true;
    try {
      final history = await ApiService.getChatHistory();
      if (history.isEmpty) {
        seedChatIfEmpty();
        return;
      }
      final restored = <ChatMessage>[];
      for (final raw in history) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final ts = DateTime.tryParse(m['createdAt']?.toString() ?? '') ??
            DateTime.now();
        final userMsg = m['message']?.toString() ?? '';
        final botReply = m['reply']?.toString() ?? '';
        if (userMsg.isNotEmpty) {
          restored.add(ChatMessage(text: userMsg, isUser: true, timestamp: ts));
        }
        if (botReply.isNotEmpty) {
          restored.add(ChatMessage(text: botReply, isUser: false, timestamp: ts));
        }
      }
      if (restored.isNotEmpty) {
        _chatMessages = restored;
        notifyListeners();
      } else {
        seedChatIfEmpty();
      }
    } catch (e) {
      debugPrint('loadChatHistory error: $e');
      // Fall back to the normal greeting rather than leaving the screen
      // blank if history couldn't be loaded (e.g. offline).
      seedChatIfEmpty();
    }
  }

  void clearChat() {
    _chatMessages.clear();
    notifyListeners();
  }
}
