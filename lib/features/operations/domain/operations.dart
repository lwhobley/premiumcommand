import '../../events/domain/readiness.dart';

// ---- Banquet timeline ------------------------------------------------------

enum TimelineStatus {
  scheduled('scheduled', 'Scheduled'),
  inProgress('in_progress', 'In progress'),
  done('done', 'Done'),
  late('late', 'Late'),
  blocked('blocked', 'Blocked');

  const TimelineStatus(this.code, this.label);

  final String code;
  final String label;

  static TimelineStatus fromCode(String code) => values.firstWhere((s) => s.code == code);
}

class TimelineItem {
  const TimelineItem({
    required this.id,
    required this.eventId,
    required this.title,
    required this.department,
    required this.assigneeName,
    required this.scheduledStart,
    required this.status,
    required this.version,
    this.targetCompletion,
    this.actualCompletion,
    this.notes = '',
    this.dependsOn,
  });

  final String id;
  final String eventId;
  final String title;
  final Department department;
  final String assigneeName;
  final DateTime scheduledStart;
  final DateTime? targetCompletion;
  final DateTime? actualCompletion;
  final TimelineStatus status;
  final String notes;
  final String? dependsOn;
  final int version;

  /// Past its target and not finished. Drives the Late indicator on the live timeline.
  bool isLate(DateTime now) =>
      status != TimelineStatus.done && targetCompletion != null && now.isAfter(targetCompletion!);

  factory TimelineItem.fromJson(Map<String, dynamic> json) {
    DateTime? parse(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
    return TimelineItem(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      title: json['title'] as String,
      department: Department.fromCode((json['department'] as String?) ?? 'banquets'),
      assigneeName: (json['assignee_name'] as String?) ?? '',
      scheduledStart: DateTime.parse(json['scheduled_start'] as String).toLocal(),
      targetCompletion: parse(json['target_completion']),
      actualCompletion: parse(json['actual_completion']),
      status: TimelineStatus.fromCode(json['status'] as String),
      notes: (json['notes'] as String?) ?? '',
      dependsOn: json['depends_on'] as String?,
      version: (json['version'] as num).toInt(),
    );
  }
}

// ---- Culinary ----------------------------------------------------------------

/// Ready, collected, delivered and received are separate steps. Readiness is not proof of delivery.
enum BatchState {
  planned('planned', 'Planned'),
  inProduction('in_production', 'In production'),
  ready('ready', 'Ready'),
  collected('collected', 'Collected'),
  delivered('delivered', 'Delivered'),
  received('received', 'Received');

  const BatchState(this.code, this.label);

  final String code;
  final String label;

  BatchState? get next => index + 1 < values.length ? values[index + 1] : null;

  static BatchState fromCode(String code) => values.firstWhere((s) => s.code == code);
}

class CulinaryBatch {
  const CulinaryBatch({
    required this.id,
    required this.eventId,
    required this.description,
    required this.quantity,
    required this.destination,
    required this.state,
    required this.version,
    this.dueAt,
    this.deliveredAt,
    this.receivedBy = '',
  });

  final String id;
  final String eventId;
  final String description;
  final int quantity;
  final String destination;
  final BatchState state;
  final int version;
  final DateTime? dueAt;
  final DateTime? deliveredAt;
  final String receivedBy;

  bool isLateDelivery() =>
      dueAt != null && deliveredAt != null && deliveredAt!.isAfter(dueAt!);

  factory CulinaryBatch.fromJson(Map<String, dynamic> json) {
    DateTime? parse(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
    return CulinaryBatch(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      description: json['description'] as String,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      destination: (json['destination'] as String?) ?? '',
      state: BatchState.fromCode(json['state'] as String),
      version: (json['version'] as num).toInt(),
      dueAt: parse(json['due_at']),
      deliveredAt: parse(json['delivered_at']),
      receivedBy: (json['received_by'] as String?) ?? '',
    );
  }
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.course,
    required this.dietaryTags,
    required this.allergens,
  });

  final String id;
  final String name;
  final String course;
  final List<String> dietaryTags;
  final String allergens;

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['id'] as String,
      name: json['name'] as String,
      course: (json['course'] as String?) ?? '',
      dietaryTags: ((json['dietary_tags'] as List?) ?? const []).cast<String>(),
      allergens: (json['allergens'] as String?) ?? '',
    );
  }
}

// ---- Inspections -------------------------------------------------------------

class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.label,
    required this.responseType,
    required this.requiresManagerApproval,
    required this.department,
  });

  final String id;
  final String label;
  final String responseType;
  final bool requiresManagerApproval;
  final Department department;

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      id: json['id'] as String,
      label: json['label'] as String,
      responseType: json['response_type'] as String,
      requiresManagerApproval: json['requires_manager_approval'] as bool? ?? false,
      department: Department.fromCode((json['department'] as String?) ?? 'operations'),
    );
  }
}

class ChecklistTemplate {
  const ChecklistTemplate({required this.id, required this.category, required this.name, required this.items});

  final String id;
  final String category;
  final String name;
  final List<ChecklistItem> items;
}

class InspectionInstance {
  const InspectionInstance({
    required this.id,
    required this.eventId,
    required this.templateId,
    required this.subject,
    required this.status,
    this.completedAt,
  });

  final String id;
  final String eventId;
  final String templateId;
  final String subject;
  final String status;
  final DateTime? completedAt;

  factory InspectionInstance.fromJson(Map<String, dynamic> json) {
    return InspectionInstance(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      templateId: json['template_id'] as String,
      subject: (json['subject'] as String?) ?? '',
      status: json['status'] as String,
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String).toLocal(),
    );
  }
}

// ---- Communications ----------------------------------------------------------

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      title: json['title'] as String,
      body: (json['body'] as String?) ?? '',
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      readAt: json['read_at'] == null ? null : DateTime.parse(json['read_at'] as String).toLocal(),
    );
  }
}

// ---- Closeout ----------------------------------------------------------------

class Closeout {
  const Closeout({
    required this.eventId,
    required this.status,
    required this.recap,
    this.managerSigned = false,
    this.directorSigned = false,
  });

  final String eventId;
  final String status;
  final Map<String, dynamic> recap;
  final bool managerSigned;
  final bool directorSigned;

  factory Closeout.fromJson(Map<String, dynamic> json) {
    return Closeout(
      eventId: json['event_id'] as String,
      status: json['status'] as String,
      recap: (json['recap'] as Map?)?.cast<String, dynamic>() ?? const {},
      managerSigned: json['manager_signed_at'] != null,
      directorSigned: json['director_signed_at'] != null,
    );
  }
}
