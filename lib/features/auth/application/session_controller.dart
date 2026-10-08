import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/permissions/app_permission.dart';
import '../data/auth_repository.dart';
import '../domain/app_session.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (AppConfig.hasSupabase) {
    return SupabaseAuthRepository(Supabase.instance.client);
  }
  return DemoAuthRepository();
});

final sessionProvider = NotifierProvider<SessionController, AppSession?>(SessionController.new);

class SessionController extends Notifier<AppSession?> {
  @override
  AppSession? build() => null;

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  /// Called once at startup, before the first frame.
  Future<void> restore() async {
    state = await _auth.restoreSession();
  }

  Future<void> signInWithPassword({required String email, required String password}) async {
    state = await _auth.signInWithPassword(email: email, password: password);
  }

  /// Demo mode only: previews a single role with sample data.
  void signInAsDemo(AppRole role) {
    final repo = DemoAuthRepository(demoRole: role);
    state = repo.demoSession(role);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    state = null;
  }
}
