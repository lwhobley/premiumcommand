import 'package:cutx_premium_command/features/dispatch/domain/routing.dart';
import 'package:cutx_premium_command/features/dispatch/domain/service_request.dart';
import 'package:cutx_premium_command/features/events/domain/readiness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ServiceRequest request({String? userId}) => ServiceRequest(
        id: 'request',
        eventId: 'event',
        clientRequestId: 'client',
        category: RequestCategory.ice,
        location: 'Suite',
        description: 'Ice',
        priority: RequestPriority.normal,
        status: RequestStatus.assigned,
        createdAt: DateTime.utc(2026, 10, 14),
        version: 1,
        assignedDepartment: 'suites',
        assignedUserId: userId,
      );

  test('named requests are visible only to their assignee', () {
    expect(requestsForShift(
      requests: [request(userId: 'coworker')],
      userId: 'me',
      departments: {Department.suites},
    ), isEmpty);
    expect(requestsForShift(
      requests: [request(userId: 'me')],
      userId: 'me',
      departments: {Department.suites},
    ), hasLength(1));
  });

  test('unassigned department requests appear for department staff', () {
    expect(requestsForShift(
      requests: [request()],
      userId: 'me',
      departments: {Department.suites},
    ), hasLength(1));
  });
}
