import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
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
     REGISTER — two-step: create account (server sends OTP) →
     verify OTP (server returns token). Login itself never asks
     for an OTP; this is the only place it's required.
  ───────────────────────────────────────────────────────── */

  /// Step 1 — creates the (unverified) account and triggers the server to
  /// text an OTP to the phone number given. Returns the userId needed for
  /// [verifyRegistrationOtp] / [resendRegistrationOtp].
  Future<String> startRegistration(Map<String, dynamic> body) async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.register(body);
      final userId = data['userId']?.toString();
      if (userId == null || userId.isEmpty) {
        throw Exception('Registration succeeded but no account ID was returned.');
      }
      return userId;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Step 2 — confirms the OTP and logs the newly-verified patient in.
  Future<void> verifyRegistrationOtp({
    required String userId,
    required String otp,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.verifyOtp(userId: userId, otp: otp);
      _currentUser = _userFromMap(data['user'] ?? data);
      await Future.wait([
        fetchAppointments(),
        fetchQueueStatus(),
      ]);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> resendRegistrationOtp(String userId) =>
      ApiService.resendOtp(userId);

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

  QueueEntry? get currentQueue => _currentQueue;

  bool get queueLoading => _queueLoading;

  List<QueueEntry> get activeQueues =>
      _currentQueue == null ? [] : [_currentQueue!];

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

    try {
      final data = await ApiService.getMyQueueStatus();

      // The API can return the queue under entry, queue, or data.
      // Normalize all of those shapes before reading the values.
      dynamic rawEntry = data['entry'] ?? data['queue'] ?? data['data'];

      if (rawEntry is List && rawEntry.isNotEmpty) {
        rawEntry = rawEntry.first;
      }

      // Do not erase a queue that was just saved locally when the server
      // response is temporarily incomplete. This is especially important
      // immediately after joining a queue.
      if (rawEntry is! Map) {
        if (_currentQueue == null) {
          _currentQueue = null;
        }
        return;
      }

      final e = Map<String, dynamic>.from(rawEntry);

      String clinicName = '';
      dynamic clinic = e['clinic'];

      if (clinic is Map) {
        clinicName = clinic['name']?.toString() ??
            clinic['clinicName']?.toString() ??
            '';
      } else if (e['clinicName'] != null) {
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

      _currentQueue = QueueEntry(
        id: queueId,
        queueNumber:
            e['queueNumber']?.toString() ?? e['queueNo']?.toString() ?? 'N/A',
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
      );
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

  void clearChat() {
    _chatMessages.clear();
    notifyListeners();
  }
}
