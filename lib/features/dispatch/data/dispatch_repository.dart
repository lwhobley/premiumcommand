import 'dart:async';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/service_request.dart';

/// Draft fields for a new request. The client id is generated once per form so retries are safe.
class ServiceRequestDraft {
  const ServiceRequestDraft({
    required this.clientRequestId,
    required this.category,
    required this.location,
    required this.description,
    required this.priority,
  });

  final String clientRequestId;
  final RequestCategory category;
  final String location;
  final String description;
  final RequestPriority priority;
}

abstract interface class DispatchRepository {
  /// Emits the current requests for an event, then again on every change.
  Stream<List<ServiceRequest>> watchRequests(String eventId);

  /// Idempotent: the same [ServiceRequestDraft.clientRequestId] returns the original request.
  Future<ServiceRequest> createRequest(String eventId, ServiceRequestDraft draft);

  /// Optimistic: fails with a conflict if [expectedVersion] is stale.
  Future<ServiceRequest> transition({
    required String requestId,
    required RequestStatus to,
    required int expectedVersion,
    String note = '',
    String? department,
    String? userId,
  });
}

/// Creates a random RFC 4122 version-4 id for client-side idempotency keys.
String newClientRequestId([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// In-memory dispatch for demo mode. Mirrors the database rules so behavior can be previewed.
class DemoDispatchRepository implements DispatchRepository {
  DemoDispatchRepository({required this.venueId});

  final String venueId;
  final List<ServiceRequest> _requests = [];
  final Map<String, ServiceRequest> _byClientId = {};
  final Set<String> _seededEvents = {};
  final _changes = StreamController<void>.broadcast();
  int _next = 1;

  /// Sample requests are created the first time an event is opened, so no event list is needed here.
  void _seedIfNeeded(String eventId) {
    if (!_seededEvents.add(eventId)) return;
    final now = DateTime.now();
    const samples = [
      (RequestCategory.ice, 'Suite 12', 'Two bags of ice', RequestPriority.high, 3),
      (RequestCategory.foodDelivery, 'Kitchen pass', 'Suite 4 charcuterie order', RequestPriority.urgent, 9),
      (RequestCategory.glassware, 'Club bar', 'Restock rocks glasses', RequestPriority.low, 15),
    ];
    for (final (category, location, description, priority, minutesAgo) in samples) {
      _requests.add(ServiceRequest(
        id: 'demo-request-${_next++}',
        eventId: eventId,
        clientRequestId: 'demo-seed-$_next',
        category: category,
        location: location,
        description: description,
        priority: priority,
        status: RequestStatus.isNew,
        createdAt: now.subtract(Duration(minutes: minutesAgo)),
        version: 1,
      ));
    }
  }

  List<ServiceRequest> _listFor(String eventId) {
    _seedIfNeeded(eventId);
    return _requests.where((r) => r.eventId == eventId).toList();
  }

  @override
  Stream<List<ServiceRequest>> watchRequests(String eventId) async* {
    yield _listFor(eventId);
    await for (final _ in _changes.stream) {
      yield _listFor(eventId);
    }
  }

  @override
  Future<ServiceRequest> createRequest(String eventId, ServiceRequestDraft draft) async {
    final existing = _byClientId[draft.clientRequestId];
    if (existing != null) return existing;

    final request = ServiceRequest(
      id: 'demo-request-${_next++}',
      eventId: eventId,
      clientRequestId: draft.clientRequestId,
      category: draft.category,
      location: draft.location,
      description: draft.description,
      priority: draft.priority,
      status: RequestStatus.isNew,
      createdAt: DateTime.now(),
      version: 1,
    );
    _requests.add(request);
    _byClientId[draft.clientRequestId] = request;
    _changes.add(null);
    return request;
  }

  @override
  Future<ServiceRequest> transition({
    required String requestId,
    required RequestStatus to,
    required int expectedVersion,
    String note = '',
    String? department,
    String? userId,
  }) async {
    final index = _requests.indexWhere((r) => r.id == requestId);
    if (index < 0) throw const AppFailure('Request not found.');
    final current = _requests[index];
    if (current.version != expectedVersion) {
      throw const AppFailure('This request was changed by someone else. Refresh and try again.');
    }
    if (current.status.isTerminal) {
      throw AppFailure('This request is already ${current.status.label.toLowerCase()}.');
    }

    final updated = ServiceRequest(
      id: current.id,
      eventId: current.eventId,
      clientRequestId: current.clientRequestId,
      category: current.category,
      location: current.location,
      description: current.description,
      priority: current.priority,
      status: to,
      createdAt: current.createdAt,
      version: current.version + 1,
      assignedDepartment: to == RequestStatus.assigned ? (department ?? current.assignedDepartment) : current.assignedDepartment,
      assignedUserId: to == RequestStatus.assigned ? userId : current.assignedUserId,
      acknowledgedAt: to == RequestStatus.accepted ? DateTime.now() : current.acknowledgedAt,
      completedAt: to == RequestStatus.completed ? DateTime.now() : current.completedAt,
    );
    _requests[index] = updated;
    _changes.add(null);
    return updated;
  }
}

/// Supabase dispatch. Writes go through database functions that enforce the rules.
class SupabaseDispatchRepository implements DispatchRepository {
  SupabaseDispatchRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<List<ServiceRequest>> watchRequests(String eventId) {
    return _client
        .from('service_requests')
        .stream(primaryKey: ['id'])
        .eq('event_id', eventId)
        .map((rows) => rows.map(ServiceRequest.fromJson).toList());
  }

  @override
  Future<ServiceRequest> createRequest(String eventId, ServiceRequestDraft draft) async {
    final row = await _client.rpc<Map<String, dynamic>>('create_service_request', params: {
      'p_event': eventId,
      'p_client_request_id': draft.clientRequestId,
      'p_category': draft.category.code,
      'p_location': draft.location,
      'p_description': draft.description,
      'p_priority': draft.priority.code,
    });
    return ServiceRequest.fromJson(row);
  }

  @override
  Future<ServiceRequest> transition({
    required String requestId,
    required RequestStatus to,
    required int expectedVersion,
    String note = '',
    String? department,
    String? userId,
  }) async {
    final row = await _client.rpc<Map<String, dynamic>>('transition_service_request', params: {
      'p_request': requestId,
      'p_to': to.code,
      'p_expected_version': expectedVersion,
      'p_note': note,
      'p_department': department,
      'p_user': userId,
    });
    return ServiceRequest.fromJson(row);
  }
}
