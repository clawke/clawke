import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/models/user_model.dart';
import 'package:client/services/auth_service.dart';

/// Auth state: logged in user or null.
final authUserProvider = StateProvider<UserVO?>((ref) => null);

/// Whether user is logged in (has persisted uid + securit).
final isLoggedInProvider = FutureProvider<bool>((ref) async {
  return AuthService.isLoggedIn();
});

/// Relay credentials (persisted).
final relayCredentialsProvider = StateProvider<RelayCredentials?>((ref) => null);
