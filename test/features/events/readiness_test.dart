import 'package:cutx_premium_command/features/events/domain/ops_event.dart';
import 'package:cutx_premium_command/features/events/domain/readiness.dart';
import 'package:flutter_test/flutter_test.dart';

EventTask _task(String id, Department dept, TaskStatus status,
    {bool required = true, DateTime? due}) {
  return EventTask(
    id: id,
    eventId: 'e1',
    department: dept,
    title: id,
    isRequired: required,
    status: status,
    dueAt: due,
  );
}

OpsEvent _event(DateTime start) => OpsEvent(
      id: 'e1',
      venueId: 'v1',
      name: 'Test event',
      type: EventType.concert,
      serviceStart: start,
      serviceEnd: start.add(const Duration(hours: 3)),
      guaranteedGuests: 100,
      managerName: 'M',
      status: EventStatus.setup,
    );

void main() {
  final now = DateTime(2026, 10, 8, 12);

  test('percent is calculated from required tasks only', () {
    final tasks = [
      _task('a', Department.suites, TaskStatus.completed),
      _task('b', Department.suites, TaskStatus.notStarted),
      _task('c', Department.suites, TaskStatus.notStarted, required: false),
    ];
    final r = computeDepartmentReadiness(
      department: Department.suites,
      tasks: tasks,
      serviceStart: now.add(const Duration(days: 10)),
      now: now,
    );
    expect(r.requiredCount, 2);
    expect(r.completedCount, 1);
    expect(r.percent, 0.5);
  });

  test('a blocked required task makes the department blocked', () {
    final r = computeDepartmentReadiness(
      department: Department.banquets,
      tasks: [_task('a', Department.banquets, TaskStatus.blocked)],
      serviceStart: now,
      now: now,
    );
    expect(r.state, ReadinessState.blocked);
  });

  test('an overdue open required task makes the department delayed', () {
    final r = computeDepartmentReadiness(
      department: Department.culinary,
      tasks: [
        _task('a', Department.culinary, TaskStatus.inProgress,
            due: now.subtract(const Duration(hours: 1))),
      ],
      serviceStart: now,
      now: now,
    );
    expect(r.state, ReadinessState.delayed);
  });

  test('fully complete required tasks mean ready', () {
    final r = computeDepartmentReadiness(
      department: Department.beverage,
      tasks: [_task('a', Department.beverage, TaskStatus.completed)],
      serviceStart: now,
      now: now,
    );
    expect(r.state, ReadinessState.ready);
    expect(r.percent, 1);
  });

  test('an unstarted department close to service needs attention', () {
    final r = computeDepartmentReadiness(
      department: Department.suites,
      tasks: [_task('a', Department.suites, TaskStatus.notStarted)],
      serviceStart: now.add(const Duration(hours: 10)),
      now: now,
    );
    expect(r.state, ReadinessState.attentionRequired);
  });

  test('snapshot requires at least one required task before it counts as complete', () {
    final empty = EventSnapshot(event: _event(now), tasks: const [], now: now);
    expect(empty.requiredTasksComplete, isFalse);

    final done = EventSnapshot(
      event: _event(now),
      tasks: [_task('a', Department.operations, TaskStatus.completed)],
      now: now,
    );
    expect(done.requiredTasksComplete, isTrue);
  });
}
