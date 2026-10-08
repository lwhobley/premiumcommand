enum RequestCategory {
  foodDelivery('food_delivery', 'Food delivery'),
  beverageReplenishment('beverage_replenishment', 'Beverage replenishment'),
  ice('ice', 'Ice'),
  glassware('glassware', 'Glassware'),
  equipment('equipment', 'Equipment'),
  roomSetup('room_setup', 'Room setup'),
  cleanup('cleanup', 'Cleanup'),
  guestAssistance('guest_assistance', 'Guest assistance'),
  maintenance('maintenance', 'Maintenance'),
  culinarySupport('culinary_support', 'Culinary support'),
  managementAssistance('management_assistance', 'Management assistance'),
  other('other', 'Other');

  const RequestCategory(this.code, this.label);

  final String code;
  final String label;

  static RequestCategory fromCode(String code) =>
      values.firstWhere((c) => c.code == code, orElse: () => RequestCategory.other);
}

enum RequestPriority {
  low('low', 'Low', Duration(minutes: 45)),
  normal('normal', 'Normal', Duration(minutes: 20)),
  high('high', 'High', Duration(minutes: 10)),
  urgent('urgent', 'Urgent', Duration(minutes: 5));

  const RequestPriority(this.code, this.label, this.escalateAfter);

  final String code;
  final String label;

  /// An unacknowledged request older than this is escalated to management.
  final Duration escalateAfter;

  static RequestPriority fromCode(String code) =>
      values.firstWhere((p) => p.code == code, orElse: () => RequestPriority.normal);
}

enum RequestStatus {
  isNew('new', 'New'),
  assigned('assigned', 'Assigned'),
  accepted('accepted', 'Accepted'),
  inProgress('in_progress', 'In progress'),
  blocked('blocked', 'Blocked'),
  completed('completed', 'Completed'),
  rejected('rejected', 'Rejected'),
  cancelled('cancelled', 'Cancelled');

  const RequestStatus(this.code, this.label);

  final String code;
  final String label;

  bool get isTerminal => switch (this) {
        completed || rejected || cancelled => true,
        _ => false,
      };

  bool get isOpen => !isTerminal;

  static RequestStatus fromCode(String code) =>
      values.firstWhere((s) => s.code == code);
}

class ServiceRequest {
  const ServiceRequest({
    required this.id,
    required this.eventId,
    required this.clientRequestId,
    required this.category,
    required this.location,
    required this.description,
    required this.priority,
    required this.status,
    required this.createdAt,
    required this.version,
    this.assignedDepartment,
    this.assignedUserId,
    this.acknowledgedAt,
    this.completedAt,
  });

  final String id;
  final String eventId;
  final String clientRequestId;
  final RequestCategory category;
  final String location;
  final String description;
  final RequestPriority priority;
  final RequestStatus status;
  final DateTime createdAt;
  final int version;
  final String? assignedDepartment;
  final String? assignedUserId;
  final DateTime? acknowledgedAt;
  final DateTime? completedAt;

  /// Only unacknowledged open requests escalate. Once someone accepts, response time is met.
  bool isEscalated(DateTime now) {
    final unacknowledged = acknowledgedAt == null && (status == RequestStatus.isNew || status == RequestStatus.assigned);
    return unacknowledged && now.difference(createdAt) > priority.escalateAfter;
  }

  ServiceRequest copyWith({RequestStatus? status, int? version}) {
    return ServiceRequest(
      id: id,
      eventId: eventId,
      clientRequestId: clientRequestId,
      category: category,
      location: location,
      description: description,
      priority: priority,
      status: status ?? this.status,
      createdAt: createdAt,
      version: version ?? this.version,
      assignedDepartment: assignedDepartment,
      assignedUserId: assignedUserId,
      acknowledgedAt: acknowledgedAt,
      completedAt: completedAt,
    );
  }

  factory ServiceRequest.fromJson(Map<String, dynamic> json) {
    return ServiceRequest(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      clientRequestId: json['client_request_id'] as String,
      category: RequestCategory.fromCode(json['category'] as String),
      location: (json['location'] as String?) ?? '',
      description: json['description'] as String,
      priority: RequestPriority.fromCode(json['priority'] as String),
      status: RequestStatus.fromCode(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      version: (json['version'] as num).toInt(),
      assignedDepartment: json['assigned_department'] as String?,
      assignedUserId: json['assigned_user_id'] as String?,
      acknowledgedAt: _parseNullable(json['acknowledged_at']),
      completedAt: _parseNullable(json['completed_at']),
    );
  }

  static DateTime? _parseNullable(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();
}
