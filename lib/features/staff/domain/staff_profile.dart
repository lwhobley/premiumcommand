import 'dart:math';

import '../../../core/text/initials.dart';
import '../../events/domain/readiness.dart';

/// One staff member's profile. Staff read their own; administrators read and edit all.
class StaffProfile {
  const StaffProfile({
    required this.id,
    required this.venueId,
    required this.userId,
    required this.employeeId,
    required this.fullName,
    required this.jobTitle,
    required this.department,
    required this.contactEmail,
    required this.contactPhone,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.status,
    required this.version,
    this.startDate,
    this.photoPath,
  });

  final String id;
  final String venueId;
  final String userId;
  final String employeeId;
  final String fullName;
  final String jobTitle;
  final Department department;
  final String contactEmail;
  final String contactPhone;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final DateTime? startDate;
  final String? photoPath;
  final StaffStatus status;
  final int version;

  bool get isActive => status == StaffStatus.active;

  String get initials => initialsFor(fullName);

  factory StaffProfile.fromJson(Map<String, dynamic> json) => StaffProfile(
    id: json['id'] as String,
    venueId: json['venue_id'] as String,
    userId: json['user_id'] as String,
    employeeId: json['employee_id'] as String,
    fullName: json['full_name'] as String,
    jobTitle: (json['job_title'] as String?) ?? '',
    department: Department.fromCode(
      (json['department'] as String?) ?? 'operations',
    ),
    contactEmail: (json['contact_email'] as String?) ?? '',
    contactPhone: (json['contact_phone'] as String?) ?? '',
    emergencyContactName: (json['emergency_contact_name'] as String?) ?? '',
    emergencyContactPhone: (json['emergency_contact_phone'] as String?) ?? '',
    startDate: json['start_date'] == null
        ? null
        : DateTime.parse(json['start_date'] as String),
    photoPath: json['photo_path'] as String?,
    status: StaffStatus.fromCode((json['status'] as String?) ?? 'active'),
    version: (json['version'] as num).toInt(),
  );
}

enum StaffStatus {
  active('active', 'Active'),
  inactive('inactive', 'Deactivated');

  const StaffStatus(this.code, this.label);

  final String code;
  final String label;

  static StaffStatus fromCode(String code) =>
      values.firstWhere((s) => s.code == code);
}

// The same rules the edge functions and database enforce (supabase/functions/_shared/staff_pin.ts).
final _employeeIdPattern = RegExp(r'^[A-Z0-9-]{3,20}$');
final _pinPattern = RegExp(r'^[0-9]{4}$');
const _weakPins = {
  '0000',
  '1111',
  '2222',
  '3333',
  '4444',
  '5555',
  '6666',
  '7777',
  '8888',
  '9999', //
  '1234', '4321', '1212', '2580',
};

String normalizeEmployeeId(String input) => input.trim().toUpperCase();

bool isValidEmployeeId(String input) =>
    _employeeIdPattern.hasMatch(normalizeEmployeeId(input));

bool isValidPin(String pin) =>
    _pinPattern.hasMatch(pin) && !_weakPins.contains(pin);

/// A PIN that passes [isValidPin]. Random, so an administrator can hand it straight to the staff member.
String generatePin([Random? random]) {
  final rng = random ?? Random.secure();
  while (true) {
    final pin = rng.nextInt(10000).toString().padLeft(4, '0');
    if (isValidPin(pin)) return pin;
  }
}

/// Returns the first problem with the staff details, or null when they are valid.
String? validateStaffFields({
  required String employeeId,
  required String fullName,
  required String jobTitle,
  required String contactEmail,
  required String contactPhone,
  required String emergencyContactName,
  required String emergencyContactPhone,
}) {
  if (!isValidEmployeeId(employeeId)) {
    return 'Employee ID must be 3 to 20 letters, digits, or hyphens.';
  }
  if (fullName.trim().isEmpty || fullName.trim().length > 120) {
    return 'Full name is required (up to 120 characters).';
  }
  if (jobTitle.length > 120) {
    return 'Job title is too long (up to 120 characters).';
  }
  if (contactEmail.length > 254) return 'Contact email is too long.';
  if (contactPhone.length > 40 || emergencyContactPhone.length > 40) {
    return 'Phone numbers are too long (up to 40 characters).';
  }
  if (emergencyContactName.length > 120) {
    return 'Emergency contact name is too long.';
  }
  return null;
}

/// Field values the staff-admin function and staff_update_profile accept.
Map<String, Object?> staffFieldsJson({
  required String employeeId,
  required String fullName,
  required String jobTitle,
  required Department department,
  required String contactEmail,
  required String contactPhone,
  required String emergencyContactName,
  required String emergencyContactPhone,
  DateTime? startDate,
}) => {
  'employee_id': normalizeEmployeeId(employeeId),
  'full_name': fullName.trim(),
  'job_title': jobTitle.trim(),
  'department': department.code,
  'contact_email': contactEmail.trim(),
  'contact_phone': contactPhone.trim(),
  'emergency_contact_name': emergencyContactName.trim(),
  'emergency_contact_phone': emergencyContactPhone.trim(),
  'start_date': startDate == null ? null : _dateOnly(startDate),
};

String _dateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The bucket path the app uploads a photo to. staff_set_photo accepts only this path.
String staffPhotoPath(String venueId, String profileId) =>
    '$venueId/$profileId.jpg';

/// Matches a name or employee ID, ignoring case and extra spaces.
bool matchesStaffSearch(StaffProfile profile, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return profile.fullName.toLowerCase().contains(q) ||
      profile.employeeId.toLowerCase().contains(q);
}
