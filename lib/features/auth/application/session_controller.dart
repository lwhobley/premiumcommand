import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/offline/outbox.dart';
import '../../../core/permissions/app_permission.dart';
import '../../../core/push/push_service.dart';
import '../data/auth_repository.dart';
import '../domain/app_session.dart';

final sessionCacheProvider = Provider<SessionCache>((ref) => SessionCache());

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (AppConfig.hasSupabase) {
    return SupabaseAuthRepository(Supabase.instance.client, ref.watch(sessionCacheProvider));
  }
  return DemoAuthRepository();
});

final pushServiceProvider = Provider<PushService>((ref) => PushService());

final sessionProvider = NotifierProvider<SessionController, AppSession?>(SessionController.new);

class SessionController extends Notifier<AppSession?> {
  @override
  AppSession? build() {
    if (AppConfig.hasSupabase) {
      // A signed-out, expired, or revoked login must not leave the app showing a live session.
      final subscription = Supabase.instance.client.auth.onAuthStateChange.listen((change) {
        if (change.event == AuthChangeEvent.signedOut) state = null;
      });
      ref.onDispose(subscription.cancel);
    }
    return null;
  }

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  /// Push registration must never delay or fail sign-in.
  void _startPush() {
    if (AppConfig.hasSupabase && state != null) {
      unawaited(ref.read(pushServiceProvider).start(Supabase.instance.client));
    }
  }

  /// Called once at startup, before the first frame. A failure here must never stop the app
  /// from opening: the user lands on the sign-in screen instead.
  Future<void> restore() async {
    try {
      state = await _auth.restoreSession();
      _startPush();
    } catch (_) {
      state = null;
    }
  }

  Future<void> signInWithPassword({required String email, required String password}) async {
    state = await _auth.signInWithPassword(email: email, password: password);
    _startPush();
  }

  /// Demo mode only: previews a single role with sample data.
  void signInAsDemo(AppRole role) {
    final repo = DemoAuthRepository(demoRole: role);
    state = repo.demoSession(role);
  }

  /// Always ends the local session, even when the server cannot be reached.
  Future<void> signOut() async {
    if (AppConfig.hasSupabase) await ref.read(pushServiceProvider).stop(Supabase.instance.client);
    try {
      await _auth.signOut();
    } catch (_) {
      // Offline sign-out still clears the local session below.
    }
    state = null;
  }
}
