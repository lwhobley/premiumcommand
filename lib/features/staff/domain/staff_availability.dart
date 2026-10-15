import '../../../core/text/initials.dart';

/// Availability states an administrator can record for a person.
enum AvailabilityStatus {
  available('available', 'Available'),
  limited('limited', 'Limited'),
  unavailable('unavailable', 'Unavailable');

  const AvailabilityStatus(this.code, this.label);

  final String code;
  final String label;

  static AvailabilityStatus fromCode(String code) =>
      values.firstWhere((s) => s.code == code);
}

/// A window in which someone is available, limited, or unavailable.
class StaffAvailability {
  const StaffAvailability({
    required this.id,
    required this.userId,
    required this.status,
    required this.startsAt,
    required this.endsAt,
    this.note = '',
  });

  final String id;
  final String userId;
  final AvailabilityStatus status;
  final DateTime startsAt;
  final DateTime endsAt;
  final String note;

  bool covers(DateTime moment) =>
      !moment.isBefore(startsAt) && moment.isBefore(endsAt);

  factory StaffAvailability.fromJson(Map<String, dynamic> json) =>
      StaffAvailability(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        status: AvailabilityStatus.fromCode(json['status'] as String),
        startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
        endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
        note: (json['note'] as String?) ?? '',
      );
}

/// What a person's availability is at [moment]. Nothing recorded means available.
/// When windows overlap, the most restrictive status wins.
AvailabilityStatus availabilityAt(
  List<StaffAvailability> records,
  String userId,
  DateTime moment,
) {
  var result = AvailabilityStatus.available;
  for (final record in records) {
    if (record.userId != userId || !record.covers(moment)) continue;
    if (record.status.index > result.index) result = record.status;
  }
  return result;
}

/// One person in the staff directory. No contact details: those stay with the profile.
class StaffDirectoryEntry {
  const StaffDirectoryEntry({
    required this.userId,
    required this.fullName,
    required this.employeeId,
    required this.department,
    required this.jobTitle,
    required this.active,
  });

  final String userId;
  final String fullName;
  final String employeeId;
  final String department;
  final String jobTitle;
  final bool active;

  String get initials => initialsFor(fullName);

  factory StaffDirectoryEntry.fromJson(Map<String, dynamic> json) =>
      StaffDirectoryEntry(
        userId: json['user_id'] as String,
        fullName: (json['full_name'] as String?) ?? '',
        employeeId: (json['employee_id'] as String?) ?? '',
        department: (json['department'] as String?) ?? '',
        jobTitle: (json['job_title'] as String?) ?? '',
        active: json['status'] == 'active',
      );
}
