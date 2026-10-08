import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/ops_event.dart';
import '../domain/readiness.dart';

abstract interface class EventRepository {
  Future<List<OpsEvent>> listEvents();

  Future<OpsEvent> getEvent(String eventId);

  Future<OpsEvent> createEvent(OpsEvent draft);

  /// Persists a lifecycle change. Supabase enforces the rules server-side.
  Future<OpsEvent> setStatus(String eventId, EventStatus status);

  Future<List<EventTask>> listTasks(String eventId);

  Future<EventTask> setTaskStatus(String taskId, TaskStatus status);
}

/// In-memory sample data for previewing without a backend. Clearly labeled in the UI.
class DemoEventRepository implements EventRepository {
  DemoEventRepository({required this.venueId, DateTime? now}) {
    _seed(now ?? DateTime.now());
  }

  final String venueId;
  final List<OpsEvent> _events = [];
  final List<EventTask> _tasks = [];
  int _nextId = 1;

  void _seed(DateTime now) {
    final samples = <({String name, EventType type, EventStatus status, Duration startOffset})>[
      (name: 'Sample hockey home game', type: EventType.hockeyGame, status: EventStatus.inService, startOffset: const Duration(hours: -1)),
      (name: 'Sample corporate banquet', type: EventType.corporateBanquet, status: EventStatus.setup, startOffset: const Duration(hours: 20)),
      (name: 'Sample VIP hospitality dinner', type: EventType.vipHospitality, status: EventStatus.approved, startOffset: const Duration(days: 4)),
      (name: 'Sample concert suite package', type: EventType.concert, status: EventStatus.planning, startOffset: const Duration(days: 12)),
    ];

    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i];
      final start = now.add(sample.startOffset);
      final id = 'demo-event-${_nextId++}';
      _events.add(OpsEvent(
        id: id,
        venueId: venueId,
        name: sample.name,
        type: sample.type,
        serviceStart: start,
        serviceEnd: start.add(const Duration(hours: 4)),
        guaranteedGuests: 120 + i * 40,
        managerName: 'Demo premium manager',
        status: sample.status,
        notes: 'Sample data. Replace with real venue information.',
      ));
      _tasks.addAll(_sampleTasks(id, i, now));
    }
  }

  List<EventTask> _sampleTasks(String eventId, int seed, DateTime now) {
    const templates = <(Department, String)>[
      (Department.suites, 'Suite setup walkthrough'),
      (Department.suites, 'Suite catering delivery confirmed'),
      (Department.banquets, 'Room setup complete'),
      (Department.banquets, 'Captain sign-off'),
      (Department.culinary, 'Production ready'),
      (Department.beverage, 'Bar opening inspection'),
      (Department.lounge, 'Lounge readiness check'),
      (Department.operations, 'Staff briefing acknowledged'),
    ];

    return [
      for (var i = 0; i < templates.length; i++)
        EventTask(
          id: '$eventId-task-$i',
          eventId: eventId,
          department: templates[i].$1,
          title: templates[i].$2,
          isRequired: true,
          status: _sampleStatus(seed, i),
          dueAt: now.add(Duration(hours: i - 2)),
        ),
    ];
  }

  TaskStatus _sampleStatus(int seed, int index) {
    final value = (seed * 7 + index * 3) % 5;
    return switch (value) {
      0 || 1 => TaskStatus.completed,
      2 => TaskStatus.inProgress,
      3 => TaskStatus.notStarted,
      _ => TaskStatus.blocked,
    };
  }

  @override
  Future<List<OpsEvent>> listEvents() async => List.unmodifiable(_events);

  @override
  Future<OpsEvent> getEvent(String eventId) async {
    return _events.firstWhere(
      (event) => event.id == eventId,
      orElse: () => throw const AppFailure('Event not found.'),
    );
  }

  @override
  Future<OpsEvent> createEvent(OpsEvent draft) async {
    final event = OpsEvent(
      id: 'demo-event-${_nextId++}',
      venueId: venueId,
      name: draft.name,
      type: draft.type,
      serviceStart: draft.serviceStart,
      serviceEnd: draft.serviceEnd,
      guaranteedGuests: draft.guaranteedGuests,
      managerName: draft.managerName,
      status: EventStatus.draft,
      notes: draft.notes,
    );
    _events.add(event);
    return event;
  }

  @override
  Future<OpsEvent> setStatus(String eventId, EventStatus status) async {
    final index = _events.indexWhere((event) => event.id == eventId);
    if (index < 0) throw const AppFailure('Event not found.');
    final updated = _events[index].copyWith(status: status);
    _events[index] = updated;
    return updated;
  }

  @override
  Future<List<EventTask>> listTasks(String eventId) async {
    return _tasks.where((task) => task.eventId == eventId).toList();
  }

  @override
  Future<EventTask> setTaskStatus(String taskId, TaskStatus status) async {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index < 0) throw const AppFailure('Task not found.');
    final updated = _tasks[index].copyWith(status: status);
    _tasks[index] = updated;
    return updated;
  }
}

class SupabaseEventRepository implements EventRepository {
  SupabaseEventRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<OpsEvent>> listEvents() async {
    final rows = await _client.from('events').select().order('service_start');
    return rows.cast<Map<String, dynamic>>().map(OpsEvent.fromJson).toList();
  }

  @override
  Future<OpsEvent> getEvent(String eventId) async {
    final row = await _client.from('events').select().eq('id', eventId).single();
    return OpsEvent.fromJson(row);
  }

  @override
  Future<OpsEvent> createEvent(OpsEvent draft) async {
    final row = await _client.from('events').insert(draft.toInsertJson()).select().single();
    return OpsEvent.fromJson(row);
  }

  @override
  Future<OpsEvent> setStatus(String eventId, EventStatus status) async {
    // transition_event re-checks lifecycle order, permissions and task completion in the database.
    final row = await _client.rpc<Map<String, dynamic>>(
      'transition_event',
      params: {'p_event_id': eventId, 'p_to': status.code},
    );
    return OpsEvent.fromJson(row);
  }

  @override
  Future<List<EventTask>> listTasks(String eventId) async {
    final rows = await _client.from('event_tasks').select().eq('event_id', eventId);
    return rows.cast<Map<String, dynamic>>().map(EventTask.fromJson).toList();
  }

  @override
  Future<EventTask> setTaskStatus(String taskId, TaskStatus status) async {
    final row = await _client
        .from('event_tasks')
        .update({
          'status': status.code,
          'completed_at': status == TaskStatus.completed ? DateTime.now().toUtc().toIso8601String() : null,
        })
        .eq('id', taskId)
        .select()
        .single();
    return EventTask.fromJson(row);
  }
}
