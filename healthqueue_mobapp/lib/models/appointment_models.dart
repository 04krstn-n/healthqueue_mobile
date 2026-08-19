/// Appointment data models — synced with hq-server enums
/// Server statuses: pending | confirmed | arrived | serving | completed | noShow | cancelled | rescheduled

enum AppointmentStatus {
  pending,
  confirmed,
  arrived,
  serving,
  completed,
  cancelled,
  noShow,
  rescheduled,
}

enum DoctorSelectionMode { automatic, manual }

class Appointment {
  final String            id;
  // Fields used by book_appointment_screen (local creation)
  final String            departmentId;
  final String            departmentName;
  final String            serviceName;
  final String            doctorId;
  final String            doctorName;
  final String?           patientTypeLabel;
  // Fields used by server responses + appointments_screen
  final String            clinicName;   // server: clinicId.name
  final String            department;   // alias for departmentName / service
  final String            doctor;       // alias for doctorName
  final DateTime          date;
  final String            timeLabel;
  final AppointmentStatus status;
  final String            notes;

  const Appointment({
    required this.id,
    // local / book_appointment fields
    String? departmentId,
    String? departmentName,
    String? serviceName,
    String? doctorId,
    String? doctorName,
    this.patientTypeLabel,
    // server / display fields
    String? clinicName,
    String? department,
    String? doctor,
    required this.date,
    required this.timeLabel,
    required this.status,
    String? notes,
  })  : departmentId   = departmentId   ?? '',
        departmentName = departmentName ?? clinicName ?? '',
        serviceName    = serviceName    ?? department ?? '',
        doctorId       = doctorId       ?? '',
        doctorName     = doctorName     ?? doctor    ?? '',
        clinicName     = clinicName     ?? departmentName ?? '',
        department     = department     ?? departmentName ?? serviceName ?? '',
        doctor         = doctor         ?? doctorName ?? '',
        notes          = notes          ?? '';

  Appointment copyWith({
    AppointmentStatus? status,
    DateTime?          date,
    String?            timeLabel,
    String?            notes,
  }) => Appointment(
    id:             id,
    departmentId:   departmentId,
    departmentName: departmentName,
    serviceName:    serviceName,
    doctorId:       doctorId,
    doctorName:     doctorName,
    patientTypeLabel: patientTypeLabel,
    clinicName:     clinicName,
    department:     department,
    doctor:         doctor,
    date:           date      ?? this.date,
    timeLabel:      timeLabel ?? this.timeLabel,
    status:         status    ?? this.status,
    notes:          notes     ?? this.notes,
  );

  static AppointmentStatus parseStatus(String? s) {
    switch (s) {
      case 'confirmed':   return AppointmentStatus.confirmed;
      case 'arrived':     return AppointmentStatus.arrived;
      case 'serving':     return AppointmentStatus.serving;
      case 'completed':   return AppointmentStatus.completed;
      case 'cancelled':   return AppointmentStatus.cancelled;
      case 'noShow':      return AppointmentStatus.noShow;
      case 'rescheduled': return AppointmentStatus.rescheduled;
      default:            return AppointmentStatus.pending;
    }
  }

  String get statusString {
    switch (status) {
      case AppointmentStatus.confirmed:   return 'confirmed';
      case AppointmentStatus.arrived:     return 'arrived';
      case AppointmentStatus.serving:     return 'serving';
      case AppointmentStatus.completed:   return 'completed';
      case AppointmentStatus.cancelled:   return 'cancelled';
      case AppointmentStatus.noShow:      return 'noShow';
      case AppointmentStatus.rescheduled: return 'rescheduled';
      default:                            return 'pending';
    }
  }

  bool get isUpcoming =>
      status == AppointmentStatus.pending   ||
      status == AppointmentStatus.confirmed ||
      status == AppointmentStatus.arrived;

  bool get isPast =>
      status == AppointmentStatus.completed  ||
      status == AppointmentStatus.cancelled  ||
      status == AppointmentStatus.noShow     ||
      status == AppointmentStatus.rescheduled;
}
