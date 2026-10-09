import 'package:cutx_premium_command/app/app.dart';
import 'package:cutx_premium_command/core/permissions/app_permission.dart';
import 'package:cutx_premium_command/features/auth/application/session_controller.dart';
import 'package:cutx_premium_command/features/auth/presentation/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void useSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Unmounts the app and disposes its container inside the test body. Background timers
  /// (the sync poller) must be cancelled before the framework checks for pending timers.
  Future<void> closeApp(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  }

  Future<ProviderContainer> pumpApp(
    WidgetTester tester,
    Size size, {
    AppRole role = AppRole.director,
  }) async {
    useSize(tester, size);
    final container = ProviderContainer();
    container.read(sessionProvider.notifier).signInAsDemo(role);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const CutxApp()),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('responsive shell', () {
    testWidgets('phone width uses a bottom navigation bar and no overflow', (
      tester,
    ) async {
      final container = await pumpApp(tester, const Size(375, 812));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('CUTX Premium Command'), findsNothing);
      expect(tester.takeException(), isNull);
      await closeApp(tester, container);
    });

    testWidgets('desktop width uses the sidebar and no overflow', (
      tester,
    ) async {
      final container = await pumpApp(tester, const Size(1280, 800));
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('CUTX Premium Command'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await closeApp(tester, container);
    });

    testWidgets('a runner sees fewer sections than a director', (tester) async {
      final container = await pumpApp(
        tester,
        const Size(1280, 800),
        role: AppRole.runner,
      );
      expect(find.text('Administration & Configuration'), findsNothing);
      expect(find.text('Live Service Dispatch'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await closeApp(tester, container);
    });
  });

  group('accessibility', () {
    testWidgets('sign-in buttons meet the Android tap-target guideline', (
      tester,
    ) async {
      useSize(tester, const Size(375, 812));
      final handle = tester.ensureSemantics();

      final container = ProviderContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: const SignInScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
      await closeApp(tester, container);
    });

    testWidgets(
      'sign-in offers demo roles only when no backend is configured',
      (tester) async {
        useSize(tester, const Size(375, 812));

        final container = ProviderContainer();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(home: const SignInScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Tests run without --dart-define, so no backend is configured and the demo roles show.
        expect(find.text('Demo roles (sample data)'), findsOneWidget);
        await closeApp(tester, container);
      },
    );
  });
}
