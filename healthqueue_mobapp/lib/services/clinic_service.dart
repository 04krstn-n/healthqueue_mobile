import 'api_service.dart';

/// Clinic model — matches hq-server Clinic schema exactly.
class Clinic {
  final String id;
  final String name;
  final String address;
  final String city;
  final double? latitude;
  final double? longitude;
  final List<Map<String, dynamic>> services;
  final int    queueLength;
  final int    currentWaitingTime;
  final int    maxQueueCapacity;
  final String status;
  final bool   acceptsWalkIn;
  final bool   acceptsAppointment;

  const Clinic({
    required this.id,
    required this.name,
    required this.address,
    this.city               = '',
    this.latitude,
    this.longitude,
    required this.services,
    this.queueLength        = 0,
    this.currentWaitingTime = 0,
    this.maxQueueCapacity   = 0,
    this.status             = 'open',
    this.acceptsWalkIn      = true,
    this.acceptsAppointment = true,
  });

  bool get hasLocation =>
      latitude != null && longitude != null &&
      latitude != 0.0  && longitude != 0.0;

  List<String> get serviceNames => services
      .where((s) => s['isAvailable'] != false)
      .map((s) => s['name']?.toString() ?? '')
      .where((n) => n.isNotEmpty)
      .toList();

  List<Map<String, dynamic>> get availableServices =>
      services.where((s) => s['isAvailable'] != false).toList();

  factory Clinic.fromJson(Map<String, dynamic> j) {
    final svcs = <Map<String, dynamic>>[];
    if (j['services'] is List) {
      for (final s in j['services'] as List) {
        if (s is Map) {
          // Cast safely: Map can be Map<dynamic,dynamic> from JSON decode
          svcs.add(Map<String, dynamic>.from(s as Map));
        } else if (s is String && s.isNotEmpty) {
          svcs.add({'name': s, 'isAvailable': true});
        }
      }
    }

    double? lat = _toDouble(j['latitude']);
    double? lng = _toDouble(j['longitude']);
    if ((lat == null || lat == 0.0) && j['location'] is Map) {
      final coords = (j['location'] as Map)['coordinates'];
      if (coords is List && coords.length == 2) {
        lng = _toDouble(coords[0]);
        lat = _toDouble(coords[1]);
      }
    }
    if (lat == 0.0 && lng == 0.0) { lat = null; lng = null; }

    return Clinic(
      id:                 j['_id']?.toString()     ?? j['id']?.toString()  ?? '',
      name:               j['name']?.toString()    ?? '',
      address:            j['address']?.toString() ?? '',
      city:               j['city']?.toString()    ?? '',
      latitude:           lat,
      longitude:          lng,
      services:           svcs,
      queueLength:        _toInt(j['queueLength']        ?? j['queueCount']   ?? j['currentQueue']    ?? 0),
      currentWaitingTime: _toInt(j['currentWaitingTime'] ?? j['estimatedWait'] ?? j['waitMinutes']     ?? 0),
      maxQueueCapacity:   _toInt(j['maxQueueCapacity']   ?? j['maxCapacity']  ?? 0),
      status:             j['status']?.toString() ?? 'open',
      acceptsWalkIn:      j['acceptsWalkIn']      != false,
      acceptsAppointment: j['acceptsAppointment'] != false,
    );
  }

  Object? get clinic => null;

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int)    return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int)    return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}

class ClinicService {
  static Future<List<Clinic>> getDirectory() async {
    final data = await ApiService.getClinicDirectory();
    final result = <Clinic>[];
    for (final item in data) {
      if (item is Map) {
        result.add(Clinic.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return result;
  }

  static Future<List<Clinic>> getRecommended({
    double? lat, double? lng, String? service,
  }) async {
    final raw = await ApiService.getRecommendedClinics(
      lat: lat, lng: lng, service: service,
    );
    final list = raw['clinics'] ?? raw['data'] ?? raw;
    final result = <Clinic>[];
    if (list is List) {
      for (final item in list) {
        if (item is Map) {
          result.add(Clinic.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return result;
  }
}
