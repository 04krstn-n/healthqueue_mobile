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
  bool     _isAuthLoading = false;
  bool     _isLoading     = false;   // alias used by register_screen

  AppUser? get currentUser   => _currentUser;
  bool     get isLoggedIn    => _currentUser != null;
  bool     get isAuthLoading => _isAuthLoading;
  bool     get isLoading     => _isAuthLoading || _isLoading;

  Future<void> login({required String identifier, required String password}) async {
    _isAuthLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.login(identifier, password);
      _currentUser = _userFromMap(data['user'] ?? data);
      await Future.wait([fetchAppointments(), fetchQueueStatus()]);
    } finally {
      _isAuthLoading = false;
      notifyListeners();
    }
  }

  /// Called by register_screen with a plain Map (flexible API)
  Future<void> register(Map<String, dynamic> body) async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.register(body);
      _currentUser = _userFromMap(data['user'] ?? data, fallback: body.cast<String, dynamic>());
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Named-param variant kept for backward compat
  Future<void> registerUser({
    required String fullName,
    required String email,
    required String phone,
    required DateTime dob,
    required String password,
  }) async {
    await register({
      'fullName': fullName, 'email': email, 'phone': phone,
      'dateOfBirth': dob.toIso8601String(),
      'password': password, 'role': 'patient',
    });
  }

  AppUser _userFromMap(dynamic u, {Map<String, dynamic>? fallback}) {
    final m = (u is Map<String, dynamic>) ? u : <String, dynamic>{};
    final f = fallback ?? {};
    return AppUser(
      id:               m['_id']      ?? m['id']      ?? '',
      fullName:         m['fullName'] ?? f['fullName'] ?? '',
      email:            m['email']    ?? f['email']    ?? '',
      phone:            m['phone']    ?? f['phone']    ?? '',
      dob:              DateTime.tryParse(
                            m['dob']?.toString() ??
                            m['dateOfBirth']?.toString() ?? '') ?? DateTime(2000),
      password:         '',
      patientType:      m['patientType']?.toString()      ?? 'Regular',
      patientId:        m['patientId']?.toString()        ?? '',
      // age: server computes from DOB, falls back to calculating from dob locally
      age:              m['age']?.toString().isNotEmpty == true
                            ? m['age'].toString()
                            : _ageFromDob(
                                DateTime.tryParse(
                                    m['dob']?.toString() ??
                                    m['dateOfBirth']?.toString() ?? '')),
      philHealthNumber: m['philHealthNumber']?.toString() ?? '',
      hmoNumber:        m['hmoNumber']?.toString()        ?? '',
    );
  }


  /// Calculates age as a string from a DateTime, or returns '' if null/year=2000.
  static String _ageFromDob(DateTime? dob) {
    if (dob == null || dob.year <= 1970) return '';
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) age--;
    return age > 0 ? age.toString() : '';
  }

  Future<void> logout() async {
    await ApiService.clearToken();
    _currentUser  = null;
    _appointments = [];
    _currentQueue = null;
    _chatMessages = [];
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    try {
      final data = await ApiService.getMe();
      _currentUser = _userFromMap(data);
      notifyListeners();
    } catch (e) { debugPrint('refreshProfile error: $e'); }
  }

  Future<void> updateCurrentUserProfile({
    String? fullName, String? phone, String? age,
    String? patientType, String? philHealthNumber, String? hmoNumber,
  }) async {
    if (_currentUser == null) return;
    final body = <String, dynamic>{};
    if (fullName         != null) body['fullName']         = fullName;
    if (phone            != null) body['phone']            = phone;
    if (age              != null) body['age']              = age;
    if (patientType      != null) body['patientType']      = patientType;
    if (philHealthNumber != null) body['philHealthNumber'] = philHealthNumber;
    if (hmoNumber        != null) body['hmoNumber']        = hmoNumber;
    try {
      final updated = await ApiService.updateProfile(body);
      _currentUser = _userFromMap(updated);
      notifyListeners();
    } catch (e) { debugPrint('updateProfile error: $e'); }
  }

  /* ─────────────────────────────────────────────────────────
     APPOINTMENTS
  ───────────────────────────────────────────────────────── */
  List<Appointment> _appointments  = [];
  bool              _apptLoading   = false;

  List<Appointment> get appointments         => List.unmodifiable(_appointments);
  bool              get apptLoading          => _apptLoading;
  List<Appointment> get upcomingAppointments =>
      _appointments.where((a) => a.isUpcoming).toList();
  List<Appointment> get pastAppointments     =>
      _appointments.where((a) => a.isPast).toList();

  Future<void> fetchAppointments() async {
    _apptLoading = true;
    notifyListeners();
    try {
      final list = await ApiService.getMyAppointments();
      _appointments = list.map((raw) {
        final m = raw as Map<String, dynamic>;

        // Server populates clinic as 'clinic' (not 'clinicId') with { _id, name, address }
        String clinicName = '';
        if      (m['clinic']   is Map)    clinicName = (m['clinic'] as Map)['name']?.toString() ?? '';
        else if (m['clinicId'] is Map)    clinicName = (m['clinicId'] as Map)['name']?.toString() ?? '';
        else if (m['clinicName'] is String) clinicName = m['clinicName'] as String;

        // Service name — server stores as 'serviceName' string
        String serviceName = '';
        if      (m['serviceName'] is String) serviceName = m['serviceName'] as String;
        else if (m['serviceId']   is Map)    serviceName = (m['serviceId'] as Map)['name']?.toString() ?? '';
        else if (m['department']  is String) serviceName = m['department']  as String;

        // Doctor / staff
        String doctorName = '';
        if      (m['staff']   is Map) doctorName = (m['staff']   as Map)['fullName']?.toString() ?? '';
        else if (m['staffId'] is Map) doctorName = (m['staffId'] as Map)['fullName']?.toString() ?? '';
        else if (m['doctor']  is String) doctorName = m['doctor'] as String;

        return Appointment(
          id:         m['_id']?.toString() ?? m['id']?.toString() ?? '',
          clinicName: clinicName,
          department: serviceName,
          doctor:     doctorName,
          date:       DateTime.tryParse(m['appointmentDate']?.toString() ?? m['date']?.toString() ?? '') ?? DateTime.now(),
          timeLabel:  m['timeSlot']?.toString() ?? m['timeLabel']?.toString() ?? '',
          status:     Appointment.parseStatus(m['status']?.toString()),
          notes:      m['notes']?.toString() ?? '',
        );
      }).toList();
    } catch (e) { debugPrint('fetchAppointments error: $e'); }
    finally {
      _apptLoading = false;
      notifyListeners();
    }
  }

  void addAppointment(Appointment appt) {
    _appointments.insert(0, appt);
    notifyListeners();
    fetchAppointments();
  }

  void updateAppointment(String id, {
    AppointmentStatus? status,
    DateTime?          date,
    String?            timeLabel,
    String?            notes,
  }) {
    final idx = _appointments.indexWhere((a) => a.id == id);
    if (idx == -1) return;
    _appointments[idx] = _appointments[idx].copyWith(
      status: status, date: date, timeLabel: timeLabel, notes: notes,
    );
    notifyListeners();
    if (status == AppointmentStatus.cancelled) {
      ApiService.cancelAppointment(id).catchError((_) {});
    }
    fetchAppointments();
  }

  /* ─────────────────────────────────────────────────────────
     QUEUE
  ───────────────────────────────────────────────────────── */
  QueueEntry? _currentQueue;
  bool        _queueLoading = false;

  QueueEntry?      get currentQueue    => _currentQueue;
  bool             get queueLoading    => _queueLoading;
  List<QueueEntry> get activeQueues    =>
      _currentQueue == null ? [] : [_currentQueue!];

  /// Wrapper getter used by dashboard_screen
  ActiveQueueStatus get currentQueueStatus {
    if (_currentQueue == null) return ActiveQueueStatus.none();
    return ActiveQueueStatus.fromQueueEntry(_currentQueue!);
  }

  Future<void> fetchQueueStatus() async {
    _queueLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.getMyQueueStatus();
      // Server returns {} or {inQueue:false} when not in queue
      if (data.isEmpty || data['entry'] == null) {
        _currentQueue = null;
      } else {
        final e = data['entry'] as Map<String, dynamic>;
        String clinicName = '';
        if (e['clinic'] is Map)             clinicName = e['clinic']['name'] ?? '';
        else if (e['clinicName'] is String) clinicName = e['clinicName'] ?? '';

        final wait = (data['estimatedWaitTime'] ?? e['estimatedWaitMinutes'] ?? 0) as int;
        final pos  = (data['peopleAhead'] ?? data['position'] ?? 0) as int;

        _currentQueue = QueueEntry(
          id:           e['_id']         ?? e['id']  ?? '',
          queueNumber:  e['queueNumber']?.toString() ?? 'N/A',
          clinicName:   clinicName,
          serviceName:  e['serviceName'] ?? '',
          patientName:  _currentUser?.fullName  ?? '',
          patientEmail: _currentUser?.email,
          patientPhone: _currentUser?.phone,
          status:       QueueEntry.parseStatus(e['status']),
          position:     pos,
          estimatedWait: wait,
          joinedAt:     DateTime.tryParse(e['joinedAt'] ?? '') ?? DateTime.now(),
        );
      }
    } catch (e) { debugPrint('fetchQueueStatus error: $e'); }
    finally {
      _queueLoading = false;
      notifyListeners();
    }
  }

  void addQueueFromJoinResult(QueueJoinResult result) {
    _currentQueue = QueueEntry(
      id:           result.entryId,
      queueNumber:  result.queueNumber,
      clinicName:   result.clinicName,
      serviceName:  result.serviceName,
      patientName:  _currentUser?.fullName   ?? result.patientName,
      patientEmail: _currentUser?.email      ?? result.patientEmail,
      patientPhone: _currentUser?.phone      ?? result.patientPhone,
      status:       QueueStatus.waiting,
      position:     result.position,
      estimatedWait: result.estimatedWait,
      joinedAt:     result.joinedAt,
    );
    notifyListeners();
    fetchQueueStatus();
  }

  Future<bool> cancelQueue(String id) async {
    final ok = await ApiService.cancelQueue(id);
    if (ok) { _currentQueue = null; notifyListeners(); }
    return ok;
  }

  /* ─────────────────────────────────────────────────────────
     CHAT
  ───────────────────────────────────────────────────────── */
  List<ChatMessage> _chatMessages = [];
  bool              _chatLoading  = false;

  List<ChatMessage> get messages     => List.unmodifiable(_chatMessages);
  List<ChatMessage> get chatMessages => messages;
  bool              get chatLoading  => _chatLoading;

  void addChatMessage(ChatMessage msg) {
    _chatMessages.add(msg);
    notifyListeners();
  }

  void addBotText(String text, {List<String> quickReplies = const []}) {
    _chatMessages.add(ChatMessage(
      text:         text,
      isUser:       false,
      timestamp:    DateTime.now(),
      quickReplies: quickReplies,
    ));
    notifyListeners();
  }

  void addUserText(String text) {
    _chatMessages.add(ChatMessage(
      text:      text,
      isUser:    true,
      timestamp: DateTime.now(),
    ));
    notifyListeners();
  }

  bool get isChatLoading => _chatLoading;

  void setChatLoading(bool v) {
    _chatLoading = v;
    notifyListeners();
  }

  void seedChatIfEmpty() {
    if (_chatMessages.isNotEmpty) return;
    addBotText(
      "Hi! I'm HQ Assistant 👋\nHow can I help you today?",
      quickReplies: [
        'Check my queue', 'Book appointment', 'Find a clinic', 'Wait time',
      ],
    );
  }

  void clearChat() {
    _chatMessages.clear();
    notifyListeners();
  }
}
