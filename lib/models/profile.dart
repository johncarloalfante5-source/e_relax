enum AppRole { client, admin, cashier, therapist }

class Profile {
  const Profile({
    required this.id,
    required this.role,
    required this.displayName,
    required this.email,
    this.phone,
  });

  final String id;
  final AppRole role;
  final String displayName;
  final String? email;
  final String? phone;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    role: AppRole.values.byName(json['role'] as String),
    displayName: json['display_name'] as String? ?? '',
    email: json['email'] as String?,
    phone: json['phone'] as String?,
  );
}
