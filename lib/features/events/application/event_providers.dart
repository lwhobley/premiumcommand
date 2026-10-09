import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_kind.dart';
import '../../../core/permissions/app_permission.dart';
import '../../auth/application/session_controller.dart';
import '../../sync/application/sync_controller.dart';
import '../../auth/domain/app_session.dart';
import '../data/event_repository.dart';
import '../domain/event_lifecycle.dart';
import '../domain/ops_event.dart';
import '../domain/readiness.dart';

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  final session = ref.watch(sessionProvider);
  if (AppConfig.hasSupabase) {
    return SupabaseEventRepository(Supabase.instance.client);
  }
  return _demoRepository(session?.venueId ?? 'demo-venue');
});

// Demo data is created once per venue so edits persist for the life of the app.
final Map<String, DemoEventRepository> _demoRepositories = {};

DemoEventRepository _demoRepository(String venueId) {
  return _demoRepositories.putIfAbsent(venueId, () => DemoEventRepository(venueId: venueId));
}

/// Every event visible to the session, with tasks and readiness derived from real task records.
final eventSnapshotsProvider = FutureProvider<List<EventSnapshot>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return const [];

  final repo = ref.watch(eventRepositoryProvider);
  final now = DateTime.now();
  final events = await repo.listEvents();
  // One request per event, all in flight together instead of one after another.
  final snapshots = await Future.wait([
    for (final event in events)
      repo.listTasks(event.id).then((tasks) => EventSnapshot(event: event, tasks: tasks, now: now)),
  ]);
  snapshots.sort((a, b) => a.event.serviceStart.compareTo(b.event.serviceStart));
  return snapshots;
});

final eventSnapshotProvider = FutureProvider.family<EventSnapshot, String>((ref, eventId) async {
  final snapshots = await ref.watch(eventSnapshotsProvider.future);
  return snapshots.firstWhere(
    (snapshot) => snapshot.event.id == eventId,
    orElse: () => throw const AppFailure('Event not found.'),
  );
});

/// Write actions. Each checks the session's permissions and the lifecycle rules
/// before calling the repository. The database re-checks the same rules.
final eventActionsProvider = Provider<EventActions>((ref) => EventActions(ref));

class EventActions {
  EventActions(this._ref);

  final Ref _ref;

  EventRepository get _repo => _ref.read(eventRepositoryProvider);

  AppSession get _session {
    final session = _ref.read(sessionProvider);
    if (session == null) throw const AppFailure('Sign in to continue.');
    return session;
  }

  void _refresh() => _ref.invalidate(eventSnapshotsProvider);

  Future<OpsEvent> createEvent(OpsEvent draft) async {
    if (!_session.can(AppPermission.manageEvents)) {
      throw const AppFailure('You do not have permission to create events.');
    }
    final created = await _repo.createEvent(draft);
    // Template tasks make readiness meaningful from the start. Idempotent, so a retry is safe.
    await _repo.generateTasks(created.id);
    _refresh();
    return created;
  }

  Future<void> moveTo(EventSnapshot snapshot, EventStatus to) async {
    final decision = evaluateTransition(
      from: snapshot.event.status,
      to: to,
      permissions: _session.permissions,
      requiredTasksComplete: snapshot.requiredTasksComplete,
    );
    if (!decision.allowed) throw AppFailure(decision.reason ?? 'This change is not allowed.');

    await _repo.setStatus(snapshot.event.id, to);
    _refresh();
  }

  Future<void> setTaskStatus(EventTask task, TaskStatus status) async {
    if (!_session.can(AppPermission.updateTasks)) {
      throw const AppFailure('You do not have permission to update tasks.');
    }
    // Completing an already-completed task is a no-op so duplicate taps do not double-write.
    if (task.status == status) return;

    try {
      await _repo.setTaskStatus(task.id, status);
    } catch (error) {
      if (!isNetworkError(error)) rethrow;
      // Task status is absolute, so a repeated send is harmless. Queue it for later.
      await _ref.read(syncControllerProvider.notifier).enqueue(outboxSetTaskStatus, {
        'task_id': task.id,
        'status': status.code,
      });
    }
    _refresh();
  }
}
