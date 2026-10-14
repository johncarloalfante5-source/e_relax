import '../../models/profile.dart';

abstract interface class AuthRepository {
  Future<Profile> signIn({required String email, required String password});
  Future<void> signUpClient({
    required String email,
    required String password,
    required String displayName,
  });
  Future<void> signOut();
  Future<void> resetPassword(String email);
  Future<Profile?> currentProfile();
  Future<void> updateDisplayName(String displayName);
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
}
