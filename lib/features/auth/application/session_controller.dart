import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/offline/outbox.dart';
import '../../../core/permissions/app_permission.dart';
import '../../../core/push/push_service.dart';
import '../data/auth_repository.dart';
import '../data/session_timing_store.dart';
import '../domain/app_session.dart';

final sessionCacheProvider = Provider<SessionCache>((ref) => SessionCache());

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (AppConfig.hasSupabase) {
    return SupabaseAuthRepository(
      Supabase.instance.client,
      ref.watch(sessionCacheProvider),
    );
  }
  return DemoAuthRepository();
});

final sessionTimingStoreProvider = Provider((ref) => SessionTimingStore());
final sessionClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final pushServiceProvider = Provider<PushService>((ref) => PushService());

final sessionProvider = NotifierProvider<SessionController, AppSession?>(
  SessionController.new,
);

class SessionController extends Notifier<AppSession?> {
  /// Signed out after this long without a tap or click.
  static const idleLimit = Duration(minutes: 30);

  /// Signed out this long after sign-in, even while active.
  static const totalLimit = Duration(hours: 12);

  Timer? _timeoutTimer;
  DateTime? _signedInAt;
  DateTime? _lastActivity;
  String? _endedNotice;

  @override
  AppSession? build() {
    if (AppConfig.hasSupabase) {
      // A signed-out, expired, or revoked login must not leave the app showing a live session.
      final subscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((change) {
            if (change.event == AuthChangeEvent.signedOut) {
              _stopTimeout();
              state = null;
            }
          });
      ref.onDispose(subscription.cancel);
    }
    ref.onDispose(_stopTimeout);
    return null;
  }

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  /// Read once by the sign-in screen after an automatic sign-out.
  String? takeEndedNotice() {
    final notice = _endedNotice;
    _endedNotice = null;
    return notice;
  }

  DateTime _now() => ref.read(sessionClockProvider)();
  SessionTimingStore get _timing => ref.read(sessionTimingStoreProvider);

  bool get _expired {
    final now = _now();
    return _signedInAt == null ||
        _lastActivity == null ||
        now.isBefore(_signedInAt!) ||
        now.isBefore(_lastActivity!) ||
        now.difference(_signedInAt!) >= totalLimit ||
        now.difference(_lastActivity!) >= idleLimit;
  }

  /// Called on every pointer press anywhere in the app. Resets the idle timer.
  void touch() {
    final session = state;
    if (session == null) return;
    if (_expired) {
      _enforceTimeout();
      return;
    }
    _lastActivity = _now();
    unawaited(
      _timing
          .write(session.userId, _signedInAt!, _lastActivity!)
          .catchError((_) {}),
    );
  }

  Future<void> _beginTimedSession(String userId) async {
    final now = _now();
    _signedInAt = now;
    _lastActivity = now;
    await _timing.write(userId, now, now);
    _startTimer();
  }

  void _startTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _enforceTimeout(),
    );
  }

  void _stopTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  void _enforceTimeout() {
    if (state == null) return;
    final now = _now();
    final idle = now.difference(_lastActivity ?? now) >= idleLimit;
    if (!_expired) return;
    _endedNotice = idle
        ? 'You were signed out after 30 minutes without activity. Sign in again.'
        : 'Your session reached its 12-hour limit. Sign in again.';
    unawaited(signOut());
  }

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
      final restored = await _auth.restoreSession();
      if (restored == null) return;
      final saved = await _timing.read();
      _signedInAt = DateTime.tryParse(saved?['started'] as String? ?? '');
      _lastActivity = DateTime.tryParse(saved?['activity'] as String? ?? '');
      if (saved?['user_id'] != restored.userId || _expired) {
        _endedNotice = 'Your session expired. Sign in again.';
        await signOut();
        return;
      }
      state = restored;
      _startTimer();
      _startPush();
    } catch (_) {
      state = null;
    }
  }

  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final session = await _auth.signInWithPassword(
      email: email,
      password: password,
    );
    await _beginTimedSession(session.userId);
    state = session;
    _startPush();
  }

  Future<void> signInWithPin({required String pin}) async {
    final session = await _auth.signInWithPin(pin: pin);
    await _beginTimedSession(session.userId);
    state = session;
    _startPush();
  }

  /// Demo mode only: previews a single role with sample data.
  void signInAsDemo(AppRole role) {
    final repo = DemoAuthRepository(demoRole: role);
    state = repo.demoSession(role);
    _signedInAt = _lastActivity = _now();
  }

  /// Always ends the local session, even when the server cannot be reached.
  Future<void> signOut() async {
    _stopTimeout();
    state = null;
    await _timing.clear().catchError((_) {});
    if (AppConfig.hasSupabase) {
      await ref.read(pushServiceProvider).stop(Supabase.instance.client);
    }
    try {
      await _auth.signOut();
    } catch (_) {
      // Offline sign-out still clears the local session below.
    }
    state = null;
  }
}
