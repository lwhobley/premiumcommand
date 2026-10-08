import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/session_controller.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/events/presentation/event_create_screen.dart';
import '../features/events/presentation/event_workspace_screen.dart';
import 'app_section.dart';
import 'more_screen.dart';
import 'shell_scaffold.dart';

const _signInPath = '/sign-in';
const _homePath = '/my-shift';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (previous, next) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final location = state.matchedLocation;
      final onSignIn = location == _signInPath;

      if (session == null) return onSignIn ? null : _signInPath;
      if (onSignIn || location == '/') return _homePath;

      final section = AppSection.values.where((s) => s.path == location).firstOrNull;
      if (section != null && !section.allows(session.permissions)) return _homePath;
      return null;
    },
    routes: [
      GoRoute(
        path: _signInPath,
        builder: (context, state) => const SignInScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => ShellScaffold(child: child),
        routes: [
          GoRoute(
            path: '/events/new',
            builder: (context, state) => const EventCreateScreen(),
          ),
          GoRoute(
            path: '/events/:id',
            builder: (context, state) =>
                EventWorkspaceScreen(eventId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/menu',
            builder: (context, state) => const MoreScreen(),
          ),
          for (final section in AppSection.values)
            GoRoute(
              path: section.path,
              builder: (context, state) => section.buildScreen(),
            ),
        ],
      ),
    ],
  );
});
