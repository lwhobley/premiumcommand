import 'package:cutx_premium_command/features/events/data/event_repository.dart';
import 'package:cutx_premium_command/features/events/domain/ops_event.dart';
import 'package:cutx_premium_command/features/events/domain/readiness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DemoEventRepository repo;

  setUp(() {
    repo = DemoEventRepository(venueId: 'demo-venue', now: DateTime(2026, 10, 8, 12));
  });

  test('seeds sample events for the venue', () async {
    final events = await repo.listEvents();
    expect(events, isNotEmpty);
    expect(events.every((e) => e.venueId == 'demo-venue'), isTrue);
    expect(events.every((e) => e.name.startsWith('Sample')), isTrue);
  });

  test('created events start as draft with a generated id', () async {
    final created = await repo.createEvent(OpsEvent(
      id: '',
      venueId: 'demo-venue',
      name: 'New',
      type: EventType.meeting,
      serviceStart: DateTime(2026, 11, 1, 18),
      serviceEnd: DateTime(2026, 11, 1, 21),
      guaranteedGuests: 10,
      managerName: '',
      status: EventStatus.draft,
    ));
    expect(created.id, isNotEmpty);
    expect(created.status, EventStatus.draft);
    expect((await repo.listEvents()).any((e) => e.id == created.id), isTrue);
  });

  test('task status updates persist to the repository', () async {
    final event = (await repo.listEvents()).first;
    final task = (await repo.listTasks(event.id)).first;
    final updated = await repo.setTaskStatus(task.id, TaskStatus.completed);
    expect(updated.status, TaskStatus.completed);
    final reloaded = (await repo.listTasks(event.id)).firstWhere((t) => t.id == task.id);
    expect(reloaded.status, TaskStatus.completed);
  });
}
