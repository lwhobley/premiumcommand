import '../../events/domain/readiness.dart';

/// A staffed position for an event. A position with no name and no user is uncovered.
class StaffPosition {
  const StaffPosition({
    required this.id,
    required this.eventId,
    required this.displayName,
    required this.roleLabel,
    required this.department,
    required this.zone,
    required this.station,
    this.suiteAssignmentId,
    this.userId,
  });

  final String id;
  final String eventId;
  final String displayName;
  final String roleLabel;
  final Department department;
  final String zone;
  final String station;
  final String? suiteAssignmentId;
  final String? userId;

  bool get isCovered => displayName.trim().isNotEmpty || userId != null;

  factory StaffPosition.fromJson(Map<String, dynamic> json) {
    return StaffPosition(
      id: json['id'] as String,
      eventId: json['event_id'] as String,
      displayName: (json['display_name'] as String?) ?? '',
      roleLabel: (json['role_label'] as String?) ?? '',
      department: Department.fromCode((json['department'] as String?) ?? 'operations'),
      zone: (json['zone'] as String?) ?? '',
      station: (json['station'] as String?) ?? '',
      suiteAssignmentId: json['suite_assignment_id'] as String?,
      userId: json['user_id'] as String?,
    );
  }
}

class RosterRow {
  const RosterRow({
    required this.displayName,
    required this.roleLabel,
    required this.department,
    required this.zone,
    required this.station,
  });

  final String displayName;
  final String roleLabel;
  final Department department;
  final String zone;
  final String station;
}

class RosterParseResult {
  const RosterParseResult(this.rows, this.errors);

  final List<RosterRow> rows;
  final List<String> errors;
}

/// Parses roster CSV with the header `name,role,department,zone,station`.
/// Columns may be in any order. Blank lines are skipped. Bad rows are reported, not dropped silently.
RosterParseResult parseRosterCsv(String text) {
  final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty) return const RosterParseResult([], ['The file is empty.']);

  final header = lines.first.split(',').map((h) => h.trim().toLowerCase()).toList();
  int col(String name) => header.indexOf(name);
  final nameCol = col('name');
  if (nameCol < 0) return const RosterParseResult([], ['The header must include a "name" column.']);

  final rows = <RosterRow>[];
  final errors = <String>[];
  for (var i = 1; i < lines.length; i++) {
    final cells = lines[i].split(',').map((c) => c.trim()).toList();
    String cell(String name) {
      final index = col(name);
      return index >= 0 && index < cells.length ? cells[index] : '';
    }

    final name = cell('name');
    if (name.isEmpty) {
      errors.add('Line ${i + 1}: name is missing.');
      continue;
    }
    final deptText = cell('department');
    final dept = deptText.isEmpty
        ? Department.operations
        : Department.values.where((d) => d.code == deptText.toLowerCase()).firstOrNull;
    if (dept == null) {
      errors.add('Line ${i + 1}: unknown department "$deptText".');
      continue;
    }
    rows.add(RosterRow(
      displayName: name,
      roleLabel: cell('role'),
      department: dept,
      zone: cell('zone'),
      station: cell('station'),
    ));
  }
  return RosterParseResult(rows, errors);
}

class Briefing {
  const Briefing({
    required this.id,
    required this.eventId,
    required this.title,
    required this.body,
    required this.createdAt,
    this.acknowledgedByMe = false,
  });

  final String id;
  final String eventId;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool acknowledgedByMe;
}
