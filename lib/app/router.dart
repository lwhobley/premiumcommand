import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/push/push_service.dart';
import '../features/auth/application/session_controller.dart';
import '../core/permissions/app_permission.dart';
import '../features/auth/domain/app_session.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/beo/presentation/beo_screen.dart';
import '../features/chat/presentation/chat_screen.dart';
import '../features/events/presentation/event_create_screen.dart';
import '../features/events/presentation/event_workspace_screen.dart';
import '../features/meeting_notes/presentation/meeting_note_editor_screen.dart';
import '../features/staff/presentation/staff_profile_screen.dart';
import 'app_section.dart';
import 'more_screen.dart';
import 'shell_scaffold.dart';

const _signInPath = '/sign-in';
const _homePath = '/my-shift';

/// The Command Center is the main screen for anyone who can see operations. Everyone else
/// starts on My Shift.
String _homeFor(AppSession session) =>
    session.can(AppPermission.viewOperations) ? AppSection.commandCenter.path : _homePath;

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (previous, next) => refresh.value++);
  // A tapped alert re-runs the redirect below, which opens the screen it is about.
  final taps = PushService.routeTaps.listen((_) => refresh.value++);
  ref.onDispose(taps.cancel);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final location = state.matchedLocation;
      final onSignIn = location == _signInPath;

      if (session == null) return onSignIn ? null : _signInPath;
      final route = PushService.takePendingRoute();
      if (route != null) return route;
      if (onSignIn || location == '/') return _homeFor(session);

      final section = AppSection.values
          .where((s) => s.path == location)
          .firstOrNull;
      if (section != null && !section.allows(session.permissions)) {
        return _homeFor(session);
      }
      if (location.startsWith('/beo/event/') &&
          !AppSection.beoManagement.allows(session.permissions)) {
        return _homeFor(session);
      }
      if (location.startsWith('${AppSection.meetingNotes.path}/') &&
          !AppSection.meetingNotes.allows(session.permissions)) {
        return _homeFor(session);
      }
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
            path: '/beo/event/:eventId',
            builder: (context, state) =>
                BeoScreen(eventId: state.pathParameters['eventId']!),
          ),
          GoRoute(
            path: '/meeting-notes/new',
            builder: (context, state) => MeetingNoteEditorScreen(
              initialEventId: state.uri.queryParameters['event'],
            ),
          ),
          GoRoute(
            path: '/meeting-notes/:id',
            builder: (context, state) =>
                MeetingNoteEditorScreen(noteId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/menu',
            builder: (context, state) => const MoreScreen(),
          ),
          GoRoute(
            path: '/chat/:id',
            builder: (context, state) =>
                ChatThreadScreen(conversationId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const StaffProfileScreen(),
          ),
          GoRoute(
            path: '/staff/:id',
            builder: (context, state) =>
                StaffProfileScreen(profileId: state.pathParameters['id']!),
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
