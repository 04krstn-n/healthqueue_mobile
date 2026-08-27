/// Queue & shared data models
/// Server queue statuses: waiting | serving | done | completed | cancelled | noShow | skipped
library;

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────
//  Shared lookup models
// ─────────────────────────────────────────────────────────────────
class Department {
  final String id, name, description;
  final IconData icon;
  const Department({required this.id, required this.name,
      required this.description, required this.icon});
}

class Doctor {
  final String id, departmentId, name, specialization;
  const Doctor({required this.id, required this.departmentId,
      required this.name, required this.specialization});
}

class ServiceItem {
  final String id, departmentId, name, description;
  const ServiceItem({required this.id, required this.departmentId,
      required this.name, required this.description});
}

// ─────────────────────────────────────────────────────────────────
//  PatientType — matches all screens (join queue uses all 5 values)
// ─────────────────────────────────────────────────────────────────
enum PatientType {
  regular,
  senior,    // Senior Citizen
  pwd,       // Person with Disability
  pregnant,
  priority,
}

extension PatientTypeLabel on PatientType {
  String get label {
    switch (this) {
      case PatientType.regular:  return 'Regular';
      case PatientType.senior:   return 'Senior Citizen';
      case PatientType.pwd:      return 'PWD';
      case PatientType.pregnant: return 'Pregnant';
      case PatientType.priority: return 'Priority';
    }
  }

  static PatientType fromString(String s) {
    switch (s.toLowerCase()) {
      case 'senior citizen':
      case 'senior':   return PatientType.senior;
      case 'pwd':      return PatientType.pwd;
      case 'pregnant': return PatientType.pregnant;
      case 'priority': return PatientType.priority;
      default:         return PatientType.regular;
    }
  }
}

// ─────────────────────────────────────────────────────────────────
//  Queue status / type enums
// ─────────────────────────────────────────────────────────────────
enum QueueStatus {
  waiting,
  called,
  serving,
  completed,
  cancelled,
  noShow,
  skipped,
  pending,
}

enum QueueType { regular, priority }

// ─────────────────────────────────────────────────────────────────
//  QueueEntry — main queue record
// ─────────────────────────────────────────────────────────────────
class QueueEntry {
  final String      id;
  final String      queueNumber;
  final String      clinicId;
  final String      clinicName;
  final String      serviceName;
  final String      patientName;
  final String?     patientEmail;
  final String?     patientPhone;
  final QueueStatus status;
  final int         position;
  final DateTime    joinedAt;

  // wait time — two aliases used across screens
  final int estimatedWait;
  final int estimatedWaitTimeMinutes;

  // extended fields
  final QueueType queueType;
  final String    departmentId;
  final String    departmentName;
  final String    serviceId;
  final String?   doctorId;
  final String?   doctorName;
  final int       totalAhead;
  // When the patient must arrive by, once called — server sends this as
  // entry.gracePeriodExpiresAt (see queueController.callPatient). Screens
  // previously looked for a top-level `graceRemaining` (minutes) field that
  // the server never actually sends, so the countdown never worked; this
  // stores the real timestamp so screens can compute remaining time themselves.
  final DateTime? gracePeriodExpiresAt;

  QueueEntry({
    required this.id,
    String?       queueNumber,
    String?       clinicId,
    String?       clinicName,
    String?       serviceName,
    String?       patientName,
    this.patientEmail,
    this.patientPhone,
    QueueStatus?  status,
    int?          position,
    required this.joinedAt,
    int?          estimatedWait,
    int?          estimatedWaitTimeMinutes,
    QueueType?    queueType,
    String?       departmentId,
    String?       departmentName,
    String?       serviceId,
    this.doctorId,
    this.doctorName,
    int?          totalAhead,
    this.gracePeriodExpiresAt,
  })  : queueNumber              = queueNumber   ?? '',
        clinicId                 = clinicId      ?? '',
        clinicName               = clinicName    ?? '',
        serviceName              = serviceName   ?? '',
        patientName              = patientName   ?? '',
        status                   = status        ?? QueueStatus.pending,
        position                 = position      ?? 0,
        estimatedWait            = estimatedWait ?? estimatedWaitTimeMinutes ?? 0,
        estimatedWaitTimeMinutes = estimatedWaitTimeMinutes ?? estimatedWait ?? 0,
        queueType                = queueType     ?? QueueType.regular,
        departmentId             = departmentId  ?? '',
        departmentName           = departmentName ?? '',
        serviceId                = serviceId     ?? '',
        totalAhead               = totalAhead    ?? position ?? 0;

  static QueueStatus parseStatus(String? s) {
    switch (s) {
      case 'waiting':   return QueueStatus.waiting;
      case 'called':    return QueueStatus.called;
      case 'serving':   return QueueStatus.serving;
      case 'done':
      case 'completed': return QueueStatus.completed;
      case 'cancelled': return QueueStatus.cancelled;
      case 'noShow':
      case 'no_show':   return QueueStatus.noShow;
      case 'skipped':   return QueueStatus.skipped;
      default:          return QueueStatus.pending;
    }
  }

  bool get isActive =>
      status == QueueStatus.waiting ||
      status == QueueStatus.called ||
      status == QueueStatus.serving ||
      status == QueueStatus.pending;

  // Staff has called this patient to the counter and they haven't arrived
  // yet — distinct from `serving` (staff has started actively serving them
  // after they arrived). The server's real lifecycle is
  // waiting -> called -> serving -> completed (see queueController.js
  // callPatient/startService), but this enum previously had no `called`
  // value at all, so parseStatus('called') silently fell through to
  // `pending` and every "You're being called!" banner in the app checked
  // `status == QueueStatus.serving` instead — meaning patients were only
  // ever notified one step too late, once staff had already started
  // serving someone else's ticket ahead of them arriving.
  bool get isCalled => status == QueueStatus.called;

  // Minutes left in the arrival grace period, or null if not applicable /
  // already expired. Computed client-side from the server's absolute
  // gracePeriodExpiresAt timestamp rather than trusting any pre-computed
  // "remaining minutes" value, which would go stale between polls.
  int? get graceMinutesRemaining {
    if (gracePeriodExpiresAt == null) return null;
    final diff = gracePeriodExpiresAt!.difference(DateTime.now());
    if (diff.isNegative) return null;
    final mins = (diff.inSeconds / 60).ceil();
    return mins > 0 ? mins : null;
  }
}

// ─────────────────────────────────────────────────────────────────
//  ActiveQueueStatus — wrapper used by dashboard_screen
//  Wraps the raw server /api/queues/my-status response so that
//  dashboard_screen can use: qStatus.inQueue / .entry / .position / .estimatedWaitTime
// ─────────────────────────────────────────────────────────────────
class ActiveQueueStatus {
  final bool        inQueue;
  final QueueEntry? entry;
  final int         position;
  final int         estimatedWaitTime;

  const ActiveQueueStatus({
    required this.inQueue,
    this.entry,
    this.position         = 0,
    this.estimatedWaitTime = 0,
  });

  factory ActiveQueueStatus.none() =>
      const ActiveQueueStatus(inQueue: false);

  factory ActiveQueueStatus.fromQueueEntry(QueueEntry e) =>
      ActiveQueueStatus(
        inQueue:           true,
        entry:             e,
        position:          e.position,
        estimatedWaitTime: e.estimatedWait,
      );
}

// ─────────────────────────────────────────────────────────────────
//  QueueJoinResult — returned after joining queue
// ─────────────────────────────────────────────────────────────────
class QueueJoinResult {
  final String    id;
  final String    entryId;
  final String    queueNumber;
  final String    clinicId;
  final String    clinicName;
  final String    serviceName;
  final String    patientName;
  final String?   patientEmail;
  final String?   patientPhone;
  final String?   doctorId;
  final String?   doctorName;
  final String    departmentId;
  final String    departmentName;
  final String    serviceId;
  final QueueType queueType;
  final int       position;
  final int       totalAhead;
  final int       estimatedWait;
  final int       estimatedWaitTimeMinutes;
  final DateTime  joinedAt;

  QueueJoinResult({
    String?       id,
    String?       entryId,
    String?       queueNumber,
    String?       clinicId,
    String?       clinicName,
    String?       serviceName,
    required this.patientName,
    this.patientEmail,
    this.patientPhone,
    this.doctorId,
    this.doctorName,
    String?       departmentId,
    String?       departmentName,
    String?       serviceId,
    QueueType?    queueType,
    int?          position,
    int?          totalAhead,
    int?          estimatedWait,
    int?          estimatedWaitTimeMinutes,
    required this.joinedAt,
  })  : id                       = id          ?? entryId ?? '',
        entryId                  = entryId     ?? id      ?? '',
        queueNumber              = queueNumber ?? '',
        clinicId                 = clinicId    ?? '',
        clinicName               = clinicName  ?? '',
        serviceName              = serviceName ?? '',
        departmentId             = departmentId  ?? '',
        departmentName           = departmentName ?? '',
        serviceId                = serviceId      ?? '',
        queueType                = queueType      ?? QueueType.regular,
        position                 = position       ?? 0,
        totalAhead               = totalAhead     ?? position ?? 0,
        estimatedWait            = estimatedWait  ?? estimatedWaitTimeMinutes ?? 0,
        estimatedWaitTimeMinutes = estimatedWaitTimeMinutes ?? estimatedWait ?? 0;
}
