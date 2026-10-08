enum EventType {
  hockeyGame('hockey_game', 'Hockey game'),
  concert('concert', 'Concert'),
  sportingEvent('sporting_event', 'Sporting event'),
  corporateBanquet('corporate_banquet', 'Corporate banquet'),
  privateReception('private_reception', 'Private reception'),
  vipHospitality('vip_hospitality', 'VIP hospitality'),
  clubEvent('club_event', 'Club event'),
  platedDinner('plated_dinner', 'Plated dinner'),
  buffet('buffet', 'Buffet'),
  meeting('meeting', 'Meeting'),
  custom('custom', 'Custom');

  const EventType(this.code, this.label);

  final String code;
  final String label;

  static EventType fromCode(String code) =>
      values.firstWhere((type) => type.code == code, orElse: () => EventType.custom);
}

enum EventStatus {
  draft('draft', 'Draft'),
  planning('planning', 'Planning'),
  approved('approved', 'Approved'),
  setup('setup', 'Setup'),
  ready('ready', 'Ready'),
  inService('in_service', 'In service'),
  breakdown('breakdown', 'Breakdown'),
  closed('closed', 'Closed'),
  cancelled('cancelled', 'Cancelled');

  const EventStatus(this.code, this.label);

  final String code;
  final String label;

  static EventStatus fromCode(String code) =>
      values.firstWhere((status) => status.code == code);

  /// Active events are happening now or being prepared for imminent service.
  bool get isActive => switch (this) {
        setup || ready || inService || breakdown => true,
        _ => false,
      };
}

/// A premium hospitality event. The event is the central record that operational
/// modules attach to.
class OpsEvent {
  const OpsEvent({
    required this.id,
    required this.venueId,
    required this.name,
    required this.type,
    required this.serviceStart,
    required this.serviceEnd,
    required this.guaranteedGuests,
    required this.managerName,
    required this.status,
    this.notes = '',
  });

  final String id;
  final String venueId;
  final String name;
  final EventType type;
  final DateTime serviceStart;
  final DateTime serviceEnd;
  final int guaranteedGuests;
  final String managerName;
  final EventStatus status;
  final String notes;

  OpsEvent copyWith({EventStatus? status}) {
    return OpsEvent(
      id: id,
      venueId: venueId,
      name: name,
      type: type,
      serviceStart: serviceStart,
      serviceEnd: serviceEnd,
      guaranteedGuests: guaranteedGuests,
      managerName: managerName,
      status: status ?? this.status,
      notes: notes,
    );
  }

  factory OpsEvent.fromJson(Map<String, dynamic> json) {
    return OpsEvent(
      id: json['id'] as String,
      venueId: json['venue_id'] as String,
      name: json['name'] as String,
      type: EventType.fromCode(json['event_type'] as String),
      serviceStart: DateTime.parse(json['service_start'] as String).toLocal(),
      serviceEnd: DateTime.parse(json['service_end'] as String).toLocal(),
      guaranteedGuests: (json['guaranteed_guests'] as num?)?.toInt() ?? 0,
      managerName: (json['manager_name'] as String?) ?? '',
      status: EventStatus.fromCode(json['status'] as String),
      notes: (json['notes'] as String?) ?? '',
    );
  }

  /// Insert payload. `id`, `status` and `created_by` are set by the database.
  Map<String, dynamic> toInsertJson() {
    return {
      'venue_id': venueId,
      'name': name,
      'event_type': type.code,
      'service_start': serviceStart.toUtc().toIso8601String(),
      'service_end': serviceEnd.toUtc().toIso8601String(),
      'guaranteed_guests': guaranteedGuests,
      'manager_name': managerName,
      'notes': notes,
    };
  }
}
