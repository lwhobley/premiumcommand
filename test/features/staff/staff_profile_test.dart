import 'dart:math';

import 'package:cutx_premium_command/features/events/domain/readiness.dart';
import 'package:cutx_premium_command/features/staff/domain/staff_profile.dart';
import 'package:cutx_premium_command/features/staff/presentation/staff_management_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({
  String id = 'p1',
  String name = 'Ana Staff',
  String employeeId = 'E-1001',
  String department = 'suites',
  String status = 'active',
}) => {
  'id': id,
  'venue_id': 'v1',
  'user_id': 'u-$id',
  'employee_id': employeeId,
  'full_name': name,
  'job_title': 'Suite attendant',
  'department': department,
  'contact_email': '',
  'contact_phone': '555-0100',
  'emergency_contact_name': 'Sam',
  'emergency_contact_phone': '555-0101',
  'start_date': '2026-03-01',
  'photo_path': null,
  'status': status,
  'version': 3,
};

void main() {
  group('PIN rules', () {
    test('accepts four digits', () {
      expect(isValidPin('4821'), isTrue);
      expect(isValidPin('0072'), isTrue);
    });

    test('rejects wrong length, letters, and obvious patterns', () {
      expect(isValidPin('482'), isFalse);
      expect(isValidPin('48210'), isFalse);
      expect(isValidPin('48a1'), isFalse);
      expect(isValidPin('1234'), isFalse);
      expect(isValidPin('7777'), isFalse);
    });

    test('generated PINs always pass validation', () {
      final rng = Random(7);
      for (var i = 0; i < 500; i++) {
        expect(isValidPin(generatePin(rng)), isTrue);
      }
    });
  });

  group('employee IDs', () {
    test('are normalized to upper case and checked', () {
      expect(normalizeEmployeeId(' e-1001 '), 'E-1001');
      expect(isValidEmployeeId('e-1001'), isTrue);
      expect(isValidEmployeeId('AB'), isFalse);
      expect(isValidEmployeeId('E 1001'), isFalse);
      expect(isValidEmployeeId('A' * 21), isFalse);
    });
  });

  group('staff details', () {
    String? check({
      String name = 'Ana',
      String id = 'E-1001',
      String title = '',
    }) => validateStaffFields(
      employeeId: id,
      fullName: name,
      jobTitle: title,
      contactEmail: '',
      contactPhone: '',
      emergencyContactName: '',
      emergencyContactPhone: '',
    );

    test('accepts valid details', () => expect(check(), isNull));

    test('requires a name and a valid employee ID', () {
      expect(check(name: '   '), contains('Full name'));
      expect(check(id: 'x'), contains('Employee ID'));
    });

    test('builds the payload the database expects', () {
      final fields = staffFieldsJson(
        employeeId: ' e-1001 ',
        fullName: ' Ana Staff ',
        jobTitle: '',
        department: Department.suites,
        contactEmail: '',
        contactPhone: '',
        emergencyContactName: '',
        emergencyContactPhone: '',
        startDate: DateTime(2026, 3, 1),
      );
      expect(fields['employee_id'], 'E-1001');
      expect(fields['full_name'], 'Ana Staff');
      expect(fields['department'], 'suites');
      expect(fields['start_date'], '2026-03-01');
    });
  });

  group('StaffProfile', () {
    test('parses a database row', () {
      final profile = StaffProfile.fromJson(_row());
      expect(profile.employeeId, 'E-1001');
      expect(profile.department, Department.suites);
      expect(profile.status, StaffStatus.active);
      expect(profile.isActive, isTrue);
      expect(profile.startDate, DateTime.parse('2026-03-01'));
      expect(profile.version, 3);
    });

    test('initials use the first and last name', () {
      expect(
        StaffProfile.fromJson(_row(name: 'ana maria staff')).initials,
        'AS',
      );
      expect(StaffProfile.fromJson(_row(name: 'Cher')).initials, 'C');
    });

    test('photo path matches the path the database accepts', () {
      expect(staffPhotoPath('venue-1', 'profile-9'), 'venue-1/profile-9.jpg');
    });
  });

  group('staff list filters', () {
    final staff = [
      StaffProfile.fromJson(
        _row(id: 'p1', name: 'Ana Staff', employeeId: 'E-1001'),
      ),
      StaffProfile.fromJson(
        _row(
          id: 'p2',
          name: 'Ben Kitchen',
          employeeId: 'E-2002',
          department: 'culinary',
          status: 'inactive',
        ),
      ),
    ];

    test('search matches name or employee ID without case', () {
      expect(filterStaffProfiles(staff, query: 'ana').map((p) => p.id), ['p1']);
      expect(filterStaffProfiles(staff, query: 'e-2002').map((p) => p.id), [
        'p2',
      ]);
      expect(filterStaffProfiles(staff, query: '   ').length, 2);
    });

    test('department and status narrow the list', () {
      expect(
        filterStaffProfiles(
          staff,
          department: Department.culinary,
        ).map((p) => p.id),
        ['p2'],
      );
      expect(
        filterStaffProfiles(staff, status: StaffStatus.active).map((p) => p.id),
        ['p1'],
      );
      expect(
        filterStaffProfiles(staff, query: 'ben', department: Department.suites),
        isEmpty,
      );
    });
  });
}
