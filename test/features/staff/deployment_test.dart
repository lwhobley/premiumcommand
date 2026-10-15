import 'package:cutx_premium_command/features/staff/domain/my_assignment.dart';
import 'package:cutx_premium_command/features/staff/domain/staff_availability.dart';
import 'package:cutx_premium_command/features/suites/presentation/suite_map_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

StaffAvailability _window(
  String user,
  AvailabilityStatus status,
  DateTime from,
  DateTime to,
) => StaffAvailability(
  id: '$user-${status.code}',
  userId: user,
  status: status,
  startsAt: from,
  endsAt: to,
);

void main() {
  final now = DateTime(2026, 10, 15, 18);

  group('availability', () {
    test('nothing recorded means available', () {
      expect(availabilityAt([], 'u1', now), AvailabilityStatus.available);
    });

    test('a window covers its start and not its end', () {
      final records = [
        _window(
          'u1',
          AvailabilityStatus.unavailable,
          now,
          now.add(const Duration(hours: 2)),
        ),
      ];
      expect(
        availabilityAt(records, 'u1', now),
        AvailabilityStatus.unavailable,
      );
      expect(
        availabilityAt(records, 'u1', now.add(const Duration(hours: 2))),
        AvailabilityStatus.available,
      );
    });

    test('the most restrictive overlapping window wins', () {
      final records = [
        _window(
          'u1',
          AvailabilityStatus.limited,
          now.subtract(const Duration(hours: 1)),
          now.add(const Duration(hours: 4)),
        ),
        _window(
          'u1',
          AvailabilityStatus.unavailable,
          now,
          now.add(const Duration(hours: 1)),
        ),
      ];
      expect(
        availabilityAt(records, 'u1', now),
        AvailabilityStatus.unavailable,
      );
    });

    test('windows for other people are ignored', () {
      final records = [
        _window(
          'u2',
          AvailabilityStatus.unavailable,
          now,
          now.add(const Duration(hours: 1)),
        ),
      ];
      expect(availabilityAt(records, 'u1', now), AvailabilityStatus.available);
    });
  });

  group('directory', () {
    test('initials come from the first and last name', () {
      final entry = StaffDirectoryEntry.fromJson({
        'user_id': 'u1',
        'full_name': 'ana maria staff',
        'employee_id': 'E-1',
        'department': 'suites',
        'job_title': '',
        'status': 'active',
      });
      expect(entry.initials, 'AS');
      expect(entry.active, isTrue);
    });
  });

  group('My Shift assignments', () {
    test('location lists the premium space, department, zone, and station', () {
      final a = MyAssignment.fromJson({
        'id': 'a1',
        'role_label': 'Suite runner',
        'department': 'suites',
        'zone': 'North',
        'station': 'Bar',
        'acknowledged_at': null,
        'events': {'name': 'Concert', 'status': 'ready'},
        'suite_event_assignments': {
          'venue_suites': {'name': 'Suite 204'},
        },
      });
      expect(a.location, 'Suite 204 · suites · North · Bar');
      expect(a.acknowledged, isFalse);
      expect(a.eventName, 'Concert');
    });

    test('a missing location says so, and an acknowledgment is kept', () {
      final a = MyAssignment.fromJson({
        'id': 'a2',
        'role_label': '',
        'department': '',
        'zone': '',
        'station': '',
        'acknowledged_at': '2026-10-15T18:00:00Z',
        'events': {'name': 'Gala', 'status': 'ready'},
        'suite_event_assignments': null,
      });
      expect(a.location, 'Location to be confirmed');
      expect(a.roleLabel, 'Position');
      expect(a.acknowledged, isTrue);
    });
  });

  group('suite map colors', () {
    test('a suite without a color is drawn muted', () {
      final scene = buildSuiteColorScene({'204': const Color(0xFF2E7D5B)});
      final suites = (scene['suites']! as List).cast<Map<String, Object?>>();
      final s204 = suites.firstWhere((s) => s['id'] == '204');
      final s205 = suites.firstWhere((s) => s['id'] == '205');
      expect(s204['muted'], isFalse);
      expect(s204['color'], '#2e7d5b');
      expect(s205['muted'], isTrue);
    });
  });
}
