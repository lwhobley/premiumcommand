/// A suite's guest preference card: what the guests like, and what must never be served to them.
class GuestPreferences {
  const GuestPreferences({
    required this.suiteAssignmentId,
    this.seating = '',
    this.drink = '',
    this.allergies = '',
    this.notes = '',
    this.version = 0,
  });

  final String suiteAssignmentId;
  final String seating;
  final String drink;
  final String allergies;
  final String notes;

  /// Zero until the card has been saved once.
  final int version;

  bool get isEmpty =>
      seating.trim().isEmpty &&
      drink.trim().isEmpty &&
      allergies.trim().isEmpty &&
      notes.trim().isEmpty;

  factory GuestPreferences.fromJson(Map<String, dynamic> json) {
    return GuestPreferences(
      suiteAssignmentId: json['suite_assignment_id'] as String,
      seating: (json['seating'] as String?) ?? '',
      drink: (json['drink'] as String?) ?? '',
      allergies: (json['allergies'] as String?) ?? '',
      notes: (json['notes'] as String?) ?? '',
    );
  }
}

enum CompStatus {
  pending('pending', 'Awaiting approval'),
  approved('approved', 'Approved'),
  rejected('rejected', 'Rejected');

  const CompStatus(this.code, this.label);

  final String code;
  final String label;

  static CompStatus fromCode(String code) => values.firstWhere(
    (s) => s.code == code,
    orElse: () => CompStatus.pending,
  );
}

/// A comp requested by staff. Only a manager or administrator can approve or reject it.
class Comp {
  const Comp({
    required this.id,
    required this.eventId,
    required this.amountCents,
    required this.reason,
    required this.status,
    required this.requestedAt,
    required this.version,
    this.suiteAssignmentId,
    this.decisionNote = '',
  });

  final String id;
  final String eventId;
  final String? suiteAssignmentId;
  final int amountCents;
  final String reason;
  final CompStatus status;
  final DateTime requestedAt;
  final int version;
  final String decisionNote;

  factory Comp.fromJson(Map<String, dynamic> json) {
    return Comp(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      suiteAssignmentId: json['suite_assignment_id'] as String?,
      amountCents: (json['amount_cents'] as num).toInt(),
      reason: (json['reason'] as String?) ?? '',
      status: CompStatus.fromCode(json['status'] as String),
      requestedAt: DateTime.parse(json['requested_at'] as String),
      version: (json['version'] as num).toInt(),
      decisionNote: (json['decision_note'] as String?) ?? '',
    );
  }
}

/// Reads a dollar amount such as "12.50" or "$12" as cents. Returns null when it is not a
/// positive amount with at most two decimal places.
int? parseDollarsToCents(String input) {
  final cleaned = input.trim().replaceAll(r'$', '').replaceAll(',', '');
  final match = RegExp(r'^(\d{1,6})(?:\.(\d{1,2}))?$').firstMatch(cleaned);
  if (match == null) return null;
  final dollars = int.parse(match.group(1)!);
  final cents = int.parse((match.group(2) ?? '0').padRight(2, '0'));
  final total = dollars * 100 + cents;
  return total > 0 ? total : null;
}
