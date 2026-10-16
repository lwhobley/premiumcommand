import 'package:cutx_premium_command/core/permissions/app_permission.dart';
import 'package:cutx_premium_command/features/auth/application/session_controller.dart';
import 'package:cutx_premium_command/features/auth/data/auth_repository.dart';
import 'package:cutx_premium_command/features/auth/data/session_timing_store.dart';
import 'package:cutx_premium_command/features/auth/domain/app_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAuth extends DemoAuthRepository {
  bool signedOut = false;
  @override
  Future<AppSession?> restoreSession() async => demoSession(AppRole.director);
  @override
  Future<AppSession> signInWithPin({required String pin}) async =>
      demoSession(AppRole.director);
  @override
  Future<void> signOut() async {
    signedOut = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('restart preserves original start and last activity', () async {
    var now = DateTime.utc(2026, 10, 16);
    final auth = FakeAuth();
    ProviderContainer container() => ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        sessionClockProvider.overrideWithValue(() => now),
      ],
    );
    final first = container();
    await first.read(sessionProvider.notifier).signInWithPin(pin: '1234');
    now = now.add(const Duration(minutes: 20));
    first.read(sessionProvider.notifier).touch();
    final saved = await first.read(sessionTimingStoreProvider).read();
    first.dispose();
    now = now.add(const Duration(minutes: 20));
    final second = container();
    addTearDown(second.dispose);
    await second.read(sessionProvider.notifier).restore();
    expect(second.read(sessionProvider), isNotNull);
    expect(await second.read(sessionTimingStoreProvider).read(), saved);
    now = now.add(const Duration(minutes: 10));
    second.read(sessionProvider.notifier).touch();
    expect(second.read(sessionProvider), isNull);
    await second.read(sessionTimingStoreProvider).read();
  });

  for (final reason in ['idle', 'total', 'missing', 'wrong user']) {
    test('restore rejects $reason session', () async {
      final now = DateTime.utc(2026, 10, 16, 12);
      final auth = FakeAuth();
      final store = SessionTimingStore();
      if (reason != 'missing') {
        await store.write(
          reason == 'wrong user'
              ? 'other'
              : auth.demoSession(AppRole.director).userId,
          now.subtract(Duration(hours: reason == 'total' ? 12 : 1)),
          now.subtract(Duration(minutes: reason == 'idle' ? 30 : 1)),
        );
      }
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          sessionTimingStoreProvider.overrideWithValue(store),
          sessionClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sessionProvider.notifier).restore();
      expect(container.read(sessionProvider), isNull);
      expect(auth.signedOut, isTrue);
      expect(await store.read(), isNull);
    });
  }
}
