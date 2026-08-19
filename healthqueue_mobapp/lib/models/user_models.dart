class AppUser {
  final String id;
  final String fullName;
  final String email; // can be "" if registered by phone only
  final String phone; // can be "" if registered by email only
  final DateTime dob;

  final String password;

  final String patientType;
  final String patientId;
  final String age;
  final String philHealthNumber;
  final String hmoNumber;

  const AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.dob,
    required this.password,
    required this.patientType,
    required this.patientId,
    required this.age,
    required this.philHealthNumber,
    required this.hmoNumber,
  });

  AppUser copyWith({
    String? fullName,
    String? email,
    String? phone,
    DateTime? dob,
    String? password,
    String? patientType,
    String? patientId,
    String? age,
    String? philHealthNumber,
    String? hmoNumber,
  }) {
    return AppUser(
      id: id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      dob: dob ?? this.dob,
      password: password ?? this.password,
      patientType: patientType ?? this.patientType,
      patientId: patientId ?? this.patientId,
      age: age ?? this.age,
      philHealthNumber: philHealthNumber ?? this.philHealthNumber,
      hmoNumber: hmoNumber ?? this.hmoNumber,
    );
  }
}
