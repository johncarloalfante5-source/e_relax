import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/profile.dart';
import '../backend/supabase_client_provider.dart';
import 'auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseClient get _client => SupabaseClientProvider.client;

  @override
  Future<Profile> signIn({required String email, required String password}) async {
    final response = await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    final user = response.user;
    if (user == null) throw const AuthException('Sign in did not return a user.');
    final row = await _client.from('profiles').select().eq('id', user.id).single();
    return Profile.fromJson(row);
  }

  @override
  Future<void> signUpClient({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'display_name': displayName.trim()},
    );
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<void> resetPassword(String email) =>
      _client.auth.resetPasswordForEmail(email.trim());

  @override
  Future<Profile?> currentProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final row = await _client.from('profiles').select().eq('id', user.id).maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('Sign in to update your profile.');
    await _client.from('profiles').update({
      'display_name': displayName.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', user.id);
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _client.auth.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      throw const AuthException('Sign in again before changing your password.');
    }

    final verified = await _client.auth.signInWithPassword(
      email: email,
      password: currentPassword,
    );
    if (verified.user?.id != user.id) {
      throw const AuthException('Could not verify this account. Sign in again.');
    }

    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }
}
