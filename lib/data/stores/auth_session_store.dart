import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/profile.dart';
import '../backend/supabase_client_provider.dart';
import '../repositories/auth_repository.dart';
import '../repositories/supabase_auth_repository.dart';

class AuthSessionStore extends ChangeNotifier {
  AuthSessionStore._();
  static final AuthSessionStore instance = AuthSessionStore._();

  final AuthRepository _repository = SupabaseAuthRepository();
  Profile? profile;
  bool isLoading = false;
  String? error;
  StreamSubscription<AuthState>? _subscription;

  bool get isSignedIn => profile != null;

  Future<void> initialize() async {
    _subscription ??= SupabaseClientProvider.client.auth.onAuthStateChange
        .listen((_) => reload());
    await reload();
  }

  Future<void> reload() async {
    try {
      profile = await _repository.currentProfile();
      error = null;
    } catch (exception) {
      error = exception.toString();
    }
    notifyListeners();
  }

  Future<Profile> signIn({required String email, required String password}) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      profile = await _repository.signIn(email: email, password: password);
      return profile!;
    } catch (exception) {
      error = exception.toString();
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signUpClient({required String email, required String password, required String displayName}) =>
      _repository.signUpClient(email: email, password: password, displayName: displayName);

  Future<void> signOut() async {
    await _repository.signOut();
    profile = null;
    notifyListeners();
  }

  Future<void> updateDisplayName(String name) async {
    await _repository.updateDisplayName(name);
    await reload();
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _repository.changePassword(
    currentPassword: currentPassword,
    newPassword: newPassword,
  );

  Future<void> resetPassword(String email) => _repository.resetPassword(email);
}

