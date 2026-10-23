import 'package:cutx_premium_command/core/offline/outbox.dart';
import 'package:cutx_premium_command/core/permissions/app_permission.dart';
import 'package:cutx_premium_command/features/auth/application/session_controller.dart';
import 'package:cutx_premium_command/features/events/application/event_providers.dart';
import 'package:cutx_premium_command/features/events/data/event_repository.dart';
import 'package:cutx_premium_command/features/events/domain/ops_event.dart';
import 'package:cutx_premium_command/features/events/domain/readiness.dart';
import 'package:cutx_premium_command/features/sync/application/sync_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Events extends DemoEventRepository {
  _Events() : super(venueId: 'demo-venue');

  int reads = 0;
  TaskStatus taskStatus = TaskStatus.notStarted;

  @override
  Future<List<OpsEvent>> listEvents() async {
    reads++;
    return super.listEvents();
  }

  @override
  Future<List<EventTask>> listTasks(String eventId) async => [
    EventTask(
      id: 'task',
      eventId: eventId,
      department: Department.suites,
      title: 'Prepare suite',
      isRequired: true,
      status: taskStatus,
    ),
  ];

  @override
  Future<EventTask> setTaskStatus(
    String taskId,
    TaskStatus status, {
    int? expectedVersion,
    String? actionId,
  }) async {
    taskStatus = status;
    return (await listTasks('event')).single;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('refreshes remote task changes without a local edit', (
    tester,
  ) async {
    final repo = _Events();
    final container = ProviderContainer(
      overrides: [eventRepositoryProvider.overrideWithValue(repo)],
    );
    container.read(sessionProvider.notifier).signInAsDemo(AppRole.director);
    container.listen(eventSnapshotsProvider, (_, _) {});
    expect(
      (await container.read(eventSnapshotsProvider.future))
          .first
          .requiredTasksComplete,
      isFalse,
    );
    repo.taskStatus = TaskStatus.completed;

    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(
      (await container.read(eventSnapshotsProvider.future))
          .first
          .requiredTasksComplete,
      isTrue,
    );
    expect(repo.reads, 2);

    container.dispose();
    await tester.pump(const Duration(seconds: 31));
    expect(repo.reads, 2);
  });

  test(
    'successful offline task replay refreshes readiness immediately',
    () async {
      final repo = _Events();
      final store = OutboxStore();
      await store.load();
      final container = ProviderContainer(
        overrides: [
          eventRepositoryProvider.overrideWithValue(repo),
          outboxStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      container.read(sessionProvider.notifier).signInAsDemo(AppRole.director);
      container.listen(eventSnapshotsProvider, (_, _) {});
      expect(
        (await container.read(eventSnapshotsProvider.future))
            .first
            .requiredTasksComplete,
        isFalse,
      );
      final sync = container.read(syncControllerProvider.notifier);
      // Allow the initial empty-queue flush to finish before adding work.
      await Future<void>.delayed(Duration.zero);
      await sync.enqueue(outboxSetTaskStatus, {
        'task_id': 'task',
        'status': 'completed',
        'expected_version': 1,
      });
      for (var i = 0; i < 20 && store.items.isNotEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(store.items, isEmpty);
      expect(
        (await container.read(eventSnapshotsProvider.future))
            .first
            .requiredTasksComplete,
        isTrue,
      );
      expect(repo.reads, 2);
    },
  );
}
