import 'package:cutx_premium_command/features/beo/domain/beo.dart';
import 'package:cutx_premium_command/features/events/domain/readiness.dart';
import 'package:cutx_premium_command/features/staffing/domain/staffing.dart';
import 'package:cutx_premium_command/features/suites/domain/suite.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('suite state machine', () {
    test('moves forward one state at a time and stops at closed', () {
      expect(SuiteState.notStarted.next, SuiteState.setupInProgress);
      expect(SuiteState.setupInProgress.next, SuiteState.ready);
      expect(SuiteState.ready.next, SuiteState.inService);
      expect(SuiteState.inService.next, SuiteState.closing);
      expect(SuiteState.closing.next, SuiteState.closed);
      expect(SuiteState.closed.next, isNull);
    });

    test('only ready and later count as ready', () {
      expect(SuiteState.setupInProgress.isReadyOrBeyond, isFalse);
      expect(SuiteState.ready.isReadyOrBeyond, isTrue);
      expect(SuiteState.closed.isReadyOrBeyond, isTrue);
    });

    test('summary counts ready suites and not-started suites', () {
      SuiteAssignment suite(SuiteState state) => SuiteAssignment(
            id: state.code,
            eventId: 'e',
            suiteId: 's',
            suiteName: 'S',
            location: '',
            serviceZone: '',
            state: state,
            version: 1,
          );
      final summary = suiteSummary([
        suite(SuiteState.notStarted),
        suite(SuiteState.ready),
        suite(SuiteState.inService),
        suite(SuiteState.closed),
      ]);
      expect(summary.total, 4);
      expect(summary.ready, 2, reason: 'closed suites are not counted as ready');
      expect(summary.notStarted, 1);
    });
  });

  group('roster CSV', () {
    test('parses rows with the header in any order', () {
      const csv = 'role,name,department,zone,station\n'
          'Server,Ana Ruiz,banquets,A,\n'
          'Runner,Sam Lee,operations,,Pickup\n';
      final result = parseRosterCsv(csv);
      expect(result.errors, isEmpty);
      expect(result.rows.length, 2);
      expect(result.rows.first.displayName, 'Ana Ruiz');
      expect(result.rows.first.department, Department.banquets);
      expect(result.rows.last.station, 'Pickup');
    });

    test('reports bad rows without dropping the good ones', () {
      const csv = 'name,department\n'
          'Ana,banquets\n'
          ',suites\n'
          'Bo,warehouse\n';
      final result = parseRosterCsv(csv);
      expect(result.rows.length, 1);
      expect(result.errors.length, 2);
      expect(result.errors.first, contains('name is missing'));
      expect(result.errors.last, contains('unknown department'));
    });

    test('requires a name column', () {
      final result = parseRosterCsv('person,role\nAna,Server\n');
      expect(result.rows, isEmpty);
      expect(result.errors.single, contains('"name"'));
    });

    test('an empty file is an error', () {
      expect(parseRosterCsv('   \n').errors.single, 'The file is empty.');
    });

    test('blank department defaults to operations', () {
      final result = parseRosterCsv('name,department\nAna,\n');
      expect(result.rows.single.department, Department.operations);
    });
  });

  group('staff positions', () {
    StaffPosition position(String name, {String? userId}) => StaffPosition(
          id: 'p',
          eventId: 'e',
          displayName: name,
          roleLabel: '',
          department: Department.operations,
          zone: '',
          station: '',
          userId: userId,
        );

    test('a named position is covered', () {
      expect(position('Ana').isCovered, isTrue);
    });

    test('a blank position with no user is uncovered', () {
      expect(position('').isCovered, isFalse);
      expect(position('  ').isCovered, isFalse);
    });

    test('a position linked to a user is covered even without a display name', () {
      expect(position('', userId: 'u1').isCovered, isTrue);
    });
  });

  group('BEO content', () {
    test('round-trips through JSON', () {
      const content = BeoContent(
        guests: 120,
        departments: {Department.banquets, Department.culinary},
        timeline: '6:00 doors',
        menu: 'Plated dinner',
        dietary: 'Two gluten-free',
        beverage: 'Open bar',
        equipment: 'Lectern',
        specialRequests: 'Cake at 8',
      );
      final back = BeoContent.fromJson(content.toJson());
      expect(back.guests, 120);
      expect(back.departments, {Department.banquets, Department.culinary});
      expect(back.timeline, '6:00 doors');
      expect(back.specialRequests, 'Cake at 8');
    });

    test('ignores unknown department codes instead of failing', () {
      final back = BeoContent.fromJson({
        'guests': 5,
        'departments': ['culinary', 'pool_service'],
      });
      expect(back.departments, {Department.culinary});
    });
  });
}
