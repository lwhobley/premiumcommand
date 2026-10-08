import 'package:cutx_premium_command/core/permissions/app_permission.dart';
import 'package:cutx_premium_command/features/dispatch/data/dispatch_repository.dart';
import 'package:cutx_premium_command/features/dispatch/domain/request_lifecycle.dart';
import 'package:cutx_premium_command/features/dispatch/domain/routing.dart';
import 'package:cutx_premium_command/features/dispatch/domain/service_request.dart';
import 'package:cutx_premium_command/features/events/domain/readiness.dart';
import 'package:flutter_test/flutter_test.dart';

const manager = {AppPermission.manageEvents, AppPermission.manageRequests};
const runnerPerms = {AppPermission.manageRequests, AppPermission.updateTasks};

ServiceRequest _request({
  RequestStatus status = RequestStatus.isNew,
  DateTime? createdAt,
  DateTime? acknowledgedAt,
  RequestPriority priority = RequestPriority.normal,
  String? department,
  String? userId,
}) {
  return ServiceRequest(
    id: 'r1',
    eventId: 'e1',
    clientRequestId: 'c1',
    category: RequestCategory.ice,
    location: 'Suite 1',
    description: 'Ice',
    priority: priority,
    status: status,
    createdAt: createdAt ?? DateTime(2026, 10, 8, 12),
    version: 1,
    assignedDepartment: department,
    assignedUserId: userId,
    acknowledgedAt: acknowledgedAt,
  );
}

void main() {
  group('request lifecycle', () {
    test('only managers can assign', () {
      final runner = evaluateRequestTransition(
        from: RequestStatus.isNew,
        to: RequestStatus.assigned,
        permissions: runnerPerms,
        isAssignee: false,
        note: '',
        hasTarget: true,
      );
      final managerDecision = evaluateRequestTransition(
        from: RequestStatus.isNew,
        to: RequestStatus.assigned,
        permissions: manager,
        isAssignee: false,
        note: '',
        hasTarget: true,
      );
      expect(runner.allowed, isFalse);
      expect(managerDecision.allowed, isTrue);
    });

    test('assignment needs a target', () {
      final decision = evaluateRequestTransition(
        from: RequestStatus.isNew,
        to: RequestStatus.assigned,
        permissions: manager,
        isAssignee: false,
        note: '',
      );
      expect(decision.allowed, isFalse);
    });

    test('completion requires progress and cannot repeat', () {
      final fromAccepted = evaluateRequestTransition(
        from: RequestStatus.accepted,
        to: RequestStatus.completed,
        permissions: runnerPerms,
        isAssignee: true,
        note: '',
      );
      final fromProgress = evaluateRequestTransition(
        from: RequestStatus.inProgress,
        to: RequestStatus.completed,
        permissions: runnerPerms,
        isAssignee: true,
        note: '',
      );
      final repeat = evaluateRequestTransition(
        from: RequestStatus.completed,
        to: RequestStatus.completed,
        permissions: runnerPerms,
        isAssignee: true,
        note: '',
      );
      expect(fromAccepted.allowed, isFalse);
      expect(fromProgress.allowed, isTrue);
      expect(repeat.allowed, isFalse);
    });

    test('block and reject require a reason', () {
      final blockNoReason = evaluateRequestTransition(
        from: RequestStatus.inProgress,
        to: RequestStatus.blocked,
        permissions: runnerPerms,
        isAssignee: true,
        note: '  ',
      );
      final blockWithReason = evaluateRequestTransition(
        from: RequestStatus.inProgress,
        to: RequestStatus.blocked,
        permissions: runnerPerms,
        isAssignee: true,
        note: 'Freezer door broken',
      );
      expect(blockNoReason.allowed, isFalse);
      expect(blockWithReason.allowed, isTrue);
    });

    test('only managers can cancel', () {
      final decision = evaluateRequestTransition(
        from: RequestStatus.assigned,
        to: RequestStatus.cancelled,
        permissions: runnerPerms,
        isAssignee: true,
        note: 'Guest left',
      );
      expect(decision.allowed, isFalse);
    });

    test('terminal requests accept no changes', () {
      final decision = evaluateRequestTransition(
        from: RequestStatus.cancelled,
        to: RequestStatus.assigned,
        permissions: manager,
        isAssignee: false,
        note: '',
        hasTarget: true,
      );
      expect(decision.allowed, isFalse);
    });
  });

  group('escalation', () {
    final now = DateTime(2026, 10, 8, 12);

    test('an unacknowledged urgent request escalates after five minutes', () {
      final request = _request(
        priority: RequestPriority.urgent,
        createdAt: now.subtract(const Duration(minutes: 6)),
      );
      expect(request.isEscalated(now), isTrue);
    });

    test('an accepted request does not escalate', () {
      final request = _request(
        status: RequestStatus.accepted,
        priority: RequestPriority.urgent,
        createdAt: now.subtract(const Duration(minutes: 30)),
        acknowledgedAt: now.subtract(const Duration(minutes: 20)),
      );
      expect(request.isEscalated(now), isFalse);
    });

    test('a recent normal request is not escalated', () {
      final request = _request(createdAt: now.subtract(const Duration(minutes: 5)));
      expect(request.isEscalated(now), isFalse);
    });
  });

  group('routing', () {
    test('runners see operations work, not suite work', () {
      final requests = [
        _request(status: RequestStatus.assigned, department: 'operations'),
        _request(status: RequestStatus.assigned, department: 'suites'),
      ];
      final mine = requestsForShift(
        requests: requests,
        userId: 'u1',
        departments: departmentsFor({AppRole.runner}),
      );
      expect(mine.length, 1);
      expect(mine.single.assignedDepartment, 'operations');
    });

    test('a request named to the user shows even outside their departments', () {
      final requests = [_request(status: RequestStatus.assigned, userId: 'u1')];
      final mine = requestsForShift(requests: requests, userId: 'u1', departments: const {});
      expect(mine.length, 1);
    });

    test('closed requests are excluded from a shift', () {
      final requests = [_request(status: RequestStatus.completed, userId: 'u1')];
      final mine = requestsForShift(requests: requests, userId: 'u1', departments: const {});
      expect(mine, isEmpty);
    });

    test('directors see every department', () {
      expect(departmentsFor({AppRole.director}), Department.values.toSet());
    });
  });

  group('client request ids', () {
    test('are version-4 UUIDs and unique', () {
      final a = newClientRequestId();
      final b = newClientRequestId();
      final pattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      expect(pattern.hasMatch(a), isTrue);
      expect(a, isNot(b));
    });
  });

  group('demo dispatch repository', () {
    test('a retry with the same client id returns the original request', () async {
      final repo = DemoDispatchRepository(venueId: 'v');
      const draft = ServiceRequestDraft(
        clientRequestId: 'same-id',
        category: RequestCategory.ice,
        location: 'Suite 3',
        description: 'Ice',
        priority: RequestPriority.high,
      );
      final first = await repo.createRequest('event-x', draft);
      final retry = await repo.createRequest('event-x', draft);
      expect(retry.id, first.id);
      final all = await repo.watchRequests('event-x').first;
      expect(all.where((r) => r.clientRequestId == 'same-id').length, 1);
    });

    test('a stale version is rejected as a conflict', () async {
      final repo = DemoDispatchRepository(venueId: 'v');
      const draft = ServiceRequestDraft(
        clientRequestId: 'c-stale',
        category: RequestCategory.ice,
        location: '',
        description: 'Ice',
        priority: RequestPriority.normal,
      );
      final created = await repo.createRequest('event-y', draft);
      await repo.transition(
        requestId: created.id,
        to: RequestStatus.assigned,
        expectedVersion: created.version,
        department: 'suites',
      );
      expect(
        () => repo.transition(
          requestId: created.id,
          to: RequestStatus.cancelled,
          expectedVersion: created.version,
          note: 'Stale',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
