class Clinic {
  final String id;
  final String name;
  final String address;
  final String contactNumber;
  final List<String> services;
  final double? latitude;
  final double? longitude;
  final int waitMinutes;
  final int queueLength;
  final bool isActive;

  const Clinic({
    required this.id,
    required this.name,
    required this.address,
    this.contactNumber = '',
    required this.services,
    this.latitude,
    this.longitude,
    this.waitMinutes = 0,
    this.queueLength = 0,
    this.isActive = true,
  });

  bool get hasLocation => latitude != null && longitude != null;

  factory Clinic.fromMap(Map<String, dynamic> map) {
    final location = map['location'] is Map ? Map<String, dynamic>.from(map['location']) : <String, dynamic>{};
    final coordinates = location['coordinates'] is List ? List.from(location['coordinates']) : <dynamic>[];

    double? parseCoordinate(dynamic value) {
      if (value == null) return null;
      return double.tryParse(value.toString());
    }

    double? latitude = parseCoordinate(map['latitude'] ?? map['lat'] ?? location['latitude']);
    double? longitude = parseCoordinate(map['longitude'] ?? map['lng'] ?? location['longitude']);

    if ((latitude == null || longitude == null) && coordinates.length >= 2) {
      longitude ??= parseCoordinate(coordinates[0]);
      latitude ??= parseCoordinate(coordinates[1]);
    }

    List<String> services = [];
    final rawServices = map['services'];
    if (rawServices is List) {
      services = rawServices.map((service) {
        if (service is String) return service;
        if (service is Map) return service['name']?.toString() ?? service['serviceName']?.toString() ?? '';
        return '';
      }).where((s) => s.isNotEmpty).toList();
    }

    return Clinic(
      id: map['_id']?.toString() ?? map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      address: map['address']?.toString() ?? map['locationName']?.toString() ?? '',
      contactNumber: map['contactNumber']?.toString() ?? '',
      services: services,
      latitude: latitude,
      longitude: longitude,
      waitMinutes: _toInt(
        map['currentWaitingTime'] ??
            map['waitMinutes'] ??
            map['estimatedWaitMinutes'] ??
            map['avgWaitMinutes'],
      ),
      queueLength: _toInt(
        map['queueLength'] ?? map['currentQueueLength'] ?? map['activeQueueCount'],
      ),
      isActive: map['isActive'] is bool ? map['isActive'] as bool : true,
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}