/// One of the signed-in person's assignments on an event that has not closed.
class MyAssignment {
  const MyAssignment({
    required this.id,
    required this.eventName,
    required this.roleLabel,
    required this.location,
    this.acknowledgedAt,
  });

  final String id;
  final String eventName;
  final String roleLabel;
  final String location;
  final DateTime? acknowledgedAt;

  bool get acknowledged => acknowledgedAt != null;

  /// Reads a row from event_staff joined to its event and premium space. Same wording as
  /// the database's assignment_location, so the notice and the screen agree.
  factory MyAssignment.fromJson(Map<String, dynamic> json) {
    final event = (json['events'] as Map?)?.cast<String, dynamic>() ?? const {};
    final suite = (json['suite_event_assignments'] as Map?)
        ?.cast<String, dynamic>();
    final venueSuite = (suite?['venue_suites'] as Map?)
        ?.cast<String, dynamic>();
    final parts = [
      (venueSuite?['name'] as String?) ?? '',
      (json['department'] as String?) ?? '',
      (json['zone'] as String?) ?? '',
      (json['station'] as String?) ?? '',
    ].where((p) => p.isNotEmpty);
    final location = parts.isEmpty
        ? 'Location to be confirmed'
        : parts.join(' · ');
    return MyAssignment(
      id: json['id'] as String,
      eventName: (event['name'] as String?) ?? 'Event',
      roleLabel: (json['role_label'] as String?)?.isNotEmpty == true
          ? json['role_label'] as String
          : 'Position',
      location: location,
      acknowledgedAt: json['acknowledged_at'] == null
          ? null
          : DateTime.parse(json['acknowledged_at'] as String).toLocal(),
    );
  }
}
