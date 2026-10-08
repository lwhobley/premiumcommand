import 'ops_event.dart';

enum TaskStatus {
  notStarted('not_started', 'Not started'),
  inProgress('in_progress', 'In progress'),
  completed('completed', 'Completed'),
  blocked('blocked', 'Blocked');

  const TaskStatus(this.code, this.label);

  final String code;
  final String label;

  static TaskStatus fromCode(String code) =>
      values.firstWhere((status) => status.code == code);
}

enum Department {
  suites('suites', 'Suites'),
  banquets('banquets', 'Banquets'),
  culinary('culinary', 'Culinary'),
  beverage('beverage', 'Beverage'),
  lounge('lounge', 'Lounge'),
  operations('operations', 'Operations');

  const Department(this.code, this.label);

  final String code;
  final String label;

  static Department fromCode(String code) =>
      values.firstWhere((dept) => dept.code == code, orElse: () => Department.operations);
}

class EventTask {
  const EventTask({
    required this.id,
    required this.eventId,
    required this.department,
    required this.title,
    required this.isRequired,
    required this.status,
    this.dueAt,
  });

  final String id;
  final String eventId;
  final Department department;
  final String title;
  final bool isRequired;
  final TaskStatus status;
  final DateTime? dueAt;

  bool get isOverdue =>
      status != TaskStatus.completed && dueAt != null && dueAt!.isBefore(DateTime.now());

  EventTask copyWith({TaskStatus? status}) {
    return EventTask(
      id: id,
      eventId: eventId,
      department: department,
      title: title,
      isRequired: isRequired,
      status: status ?? this.status,
      dueAt: dueAt,
    );
  }

  factory EventTask.fromJson(Map<String, dynamic> json) {
    return EventTask(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      department: Department.fromCode(json['department'] as String),
      title: json['title'] as String,
      isRequired: json['is_required'] as bool? ?? true,
      status: TaskStatus.fromCode(json['status'] as String),
      dueAt: json['due_at'] == null ? null : DateTime.parse(json['due_at'] as String).toLocal(),
    );
  }
}

enum ReadinessState {
  notStarted('Not started'),
  inProgress('In progress'),
  attentionRequired('Attention required'),
  delayed('Delayed'),
  blocked('Blocked'),
  ready('Ready');

  const ReadinessState(this.label);

  final String label;
}

/// Readiness for one department, calculated from its required tasks only.
class DepartmentReadiness {
  const DepartmentReadiness({
    required this.department,
    required this.requiredCount,
    required this.completedCount,
    required this.state,
  });

  final Department department;
  final int requiredCount;
  final int completedCount;
  final ReadinessState state;

  double get percent => requiredCount == 0 ? 1 : completedCount / requiredCount;
}

/// Computes readiness from real task records. Nothing here is manually entered.
DepartmentReadiness computeDepartmentReadiness({
  required Department department,
  required List<EventTask> tasks,
  required DateTime serviceStart,
  required DateTime now,
}) {
  final required = tasks
      .where((task) => task.department == department && task.isRequired)
      .toList();
  final completed = required.where((t) => t.status == TaskStatus.completed).length;

  final ReadinessState state;
  if (required.isEmpty || completed == required.length) {
    state = ReadinessState.ready;
  } else if (required.any((t) => t.status == TaskStatus.blocked)) {
    state = ReadinessState.blocked;
  } else if (required.any((t) => t.status != TaskStatus.completed && t.dueAt != null && t.dueAt!.isBefore(now))) {
    state = ReadinessState.delayed;
  } else if (required.any((t) => t.status == TaskStatus.inProgress || t.status == TaskStatus.completed)) {
    state = ReadinessState.inProgress;
  } else if (serviceStart.difference(now) <= const Duration(hours: 48)) {
    state = ReadinessState.attentionRequired;
  } else {
    state = ReadinessState.notStarted;
  }

  return DepartmentReadiness(
    department: department,
    requiredCount: required.length,
    completedCount: completed,
    state: state,
  );
}

/// An event with its tasks and derived readiness, used by the dashboard and workspace.
class EventSnapshot {
  EventSnapshot({required this.event, required this.tasks, required DateTime now})
      : departments = [
          for (final dept in Department.values)
            computeDepartmentReadiness(
              department: dept,
              tasks: tasks,
              serviceStart: event.serviceStart,
              now: now,
            ),
        ],
        overdueCount = tasks.where((t) => t.isRequired && t.isOverdue).length,
        blockedCount = tasks.where((t) => t.isRequired && t.status == TaskStatus.blocked).length;

  final OpsEvent event;
  final List<EventTask> tasks;
  final List<DepartmentReadiness> departments;
  final int overdueCount;
  final int blockedCount;

  List<EventTask> get requiredTasks => tasks.where((t) => t.isRequired).toList();

  /// True only when there is at least one required task and every one is complete.
  bool get requiredTasksComplete =>
      requiredTasks.isNotEmpty && requiredTasks.every((t) => t.status == TaskStatus.completed);

  double get overallPercent {
    final required = requiredTasks;
    if (required.isEmpty) return 0;
    return required.where((t) => t.status == TaskStatus.completed).length / required.length;
  }
}
