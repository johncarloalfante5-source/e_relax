import 'dart:typed_data';

class TherapistProfile {
  TherapistProfile({
    required this.id,
    required this.name,
    required this.specialty,
    this.email = '',
    this.phone = '',
    this.profileImageBytes,
    this.profileImagePath,
    this.specialtyServiceId,
    this.authProfileId,
  });

  final String id;
  String name, specialty, email, phone;
  Uint8List? profileImageBytes;
  String? profileImagePath;
  String? specialtyServiceId;
  String? authProfileId;

  factory TherapistProfile.fromJson(Map<String, dynamic> json, {Uint8List? bytes}) => TherapistProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    specialty: _serviceLabel(json['specialty_service_id'] as String?),
    email: json['email'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    profileImagePath: json['profile_image_path'] as String?,
    profileImageBytes: bytes,
    specialtyServiceId: json['specialty_service_id'] as String?,
    authProfileId: json['auth_profile_id'] as String?,
  );

  static String _serviceLabel(String? id) => switch (id) {
    'svc_001' => 'Whole Body Massage',
    'svc_002' => 'Lying/Back Massage',
    'svc_003' || 'svc_004' => 'Foot Massage',
    _ => id ?? '',
  };
}
