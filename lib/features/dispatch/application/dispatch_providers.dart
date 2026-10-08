import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/permissions/app_permission.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/app_session.dart';
import '../data/dispatch_repository.dart';
import '../domain/request_lifecycle.dart';
import '../domain/service_request.dart';

final Map<String, DemoDispatchRepository> _demoDispatch = {};

final dispatchRepositoryProvider = Provider<DispatchRepository>((ref) {
  if (AppConfig.hasSupabase) {
    return SupabaseDispatchRepository(Supabase.instance.client);
  }
  final venueId = ref.watch(sessionProvider)?.venueId ?? 'demo-venue';
  return _demoDispatch.putIfAbsent(venueId, () => DemoDispatchRepository(venueId: venueId));
});

/// Live requests for one event. Updates arrive as the repository emits changes.
final eventRequestsProvider = StreamProvider.family<List<ServiceRequest>, String>((ref, eventId) {
  return ref.watch(dispatchRepositoryProvider).watchRequests(eventId);
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

  Future<ServiceRequest> create(String eventId, ServiceRequestDraft draft) async {
    if (!_session.can(AppPermission.manageRequests)) {
      throw const AppFailure('You do not have permission to create service requests.');
    }
    if (draft.description.trim().isEmpty) {
      throw const AppFailure('Describe what is needed.');
    }
    return _repo.createRequest(eventId, draft);
  }

  Future<void> move(
    ServiceRequest request, {
    required RequestStatus to,
    String note = '',
    String? department,
    String? userId,
  }) async {
    final session = _session;
    final isAssignee = request.assignedUserId == session.userId ||
        (request.assignedUserId == null && session.can(AppPermission.manageRequests));
    final decision = evaluateRequestTransition(
      from: request.status,
      to: to,
      permissions: session.permissions,
      isAssignee: isAssignee,
      note: note,
      hasTarget: department != null || userId != null,
    );
    if (!decision.allowed) throw AppFailure(decision.reason ?? 'This change is not allowed.');

    await _repo.transition(
      requestId: request.id,
      to: to,
      expectedVersion: request.version,
      note: note,
      department: department,
      userId: userId,
    );
    // The live stream delivers the change to the board; nothing else needs refreshing.
  }
}
