import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_kind.dart';
import '../../../core/permissions/app_permission.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/app_session.dart';
import '../../sync/application/sync_controller.dart';
import '../data/dispatch_repository.dart';
import '../domain/request_lifecycle.dart';
import '../domain/service_request.dart';

final Map<String, DemoDispatchRepository> _demoDispatch = {};

final dispatchRepositoryProvider = Provider<DispatchRepository>((ref) {
  if (AppConfig.hasSupabase) {
    return SupabaseDispatchRepository(Supabase.instance.client, ref.watch(offlineCacheProvider));
  }
  final venueId = ref.watch(sessionProvider)?.venueId ?? 'demo-venue';
  return _demoDispatch.putIfAbsent(venueId, () => DemoDispatchRepository(venueId: venueId));
});

/// Live requests for one event. Updates arrive as the repository emits changes.
final eventRequestsProvider = StreamProvider.family<List<ServiceRequest>, String>((ref, eventId) {
  return ref.watch(dispatchRepositoryProvider).watchRequests(eventId);
});

/// Escalation limits for the signed-in venue. Re-read when the session changes.
final escalationThresholdsProvider = FutureProvider<Map<RequestPriority, Duration>>((ref) {
  final venueId = ref.watch(sessionProvider)?.venueId ?? 'demo-venue';
  return ref.watch(dispatchRepositoryProvider).escalationThresholds(venueId);
});

/// Write actions for dispatch. Each checks permissions and lifecycle rules first.
final dispatchActionsProvider = Provider<DispatchActions>((ref) => DispatchActions(ref));

class DispatchActions {
  DispatchActions(this._ref);

  final Ref _ref;

  DispatchRepository get _repo => _ref.read(dispatchRepositoryProvider);

  AppSession get _session {
    final session = _ref.read(sessionProvider);
    if (session == null) throw const AppFailure('Sign in to continue.');
    return session;
  }

  Future<void> create(String eventId, ServiceRequestDraft draft) async {
    if (!_session.can(AppPermission.manageRequests)) {
      throw const AppFailure('You do not have permission to create service requests.');
    }
    if (draft.description.trim().isEmpty) {
      throw const AppFailure('Describe what is needed.');
    }
    try {
      await _repo.createRequest(eventId, draft);
    } catch (error) {
      if (!isNetworkError(error)) rethrow;
      // Offline: keep the request on this device. Its client id makes the later send idempotent.
      await _ref.read(syncControllerProvider.notifier).enqueue(
        outboxCreateRequest,
        {
          'event_id': eventId,
          'client_request_id': draft.clientRequestId,
          'category': draft.category.code,
          'location': draft.location,
          'description': draft.description,
          'priority': draft.priority.code,
        },
        id: draft.clientRequestId,
      );
    }
  }

  Future<void> move(
    ServiceRequest request, {
    required RequestStatus to,
    String note = '',
    String? department,
    String? userId,
  }) async {
    final session = _session;
    // Mirrors the database: a named person, or a department-level request in the user's own department.
    final dept = request.assignedDepartment;
    final isAssignee = request.assignedUserId == session.userId ||
        (request.assignedUserId == null &&
            dept != null &&
            session.can(AppPermission.manageRequests) &&
            session.departments.any((d) => d.code == dept));
    final decision = evaluateRequestTransition(
      from: request.status,
      to: to,
      permissions: session.permissions,
      isAssignee: isAssignee,
      note: note,
      hasTarget: department != null || userId != null,
    );
    if (!decision.allowed) throw AppFailure(decision.reason ?? 'This change is not allowed.');

    try {
      await _repo.transition(
        requestId: request.id,
        to: to,
        expectedVersion: request.version,
        note: note,
        department: department,
        userId: userId,
      );
    } catch (error) {
      if (!isNetworkError(error)) rethrow;
      // Offline: queue the change with the version it was made against. A stale version is
      // flagged for review on sync, never applied over someone else's change.
      await _ref.read(syncControllerProvider.notifier).enqueue(outboxTransitionRequest, {
        'request_id': request.id,
        'to': to.code,
        'expected_version': request.version,
        'note': note,
        'department': department,
        'user_id': userId,
      });
    }
  }
}
