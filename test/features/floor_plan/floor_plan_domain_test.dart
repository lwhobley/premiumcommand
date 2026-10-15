import 'package:cutx_premium_command/features/floor_plan/domain/floor_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generateRoundTableLayouts', () {
    test('generates distinct feasible arrangements for a large ballroom', () {
      final options = generateRoundTableLayouts(widthFeet: 80, depthFeet: 60, guestCount: 120);
      expect(options, isNotEmpty);
      for (final option in options) {
        expect(option.tables, isNotEmpty);
        expect(option.tables.length * defaultSeatsPerTable, greaterThanOrEqualTo(120));
        final plan = VenueSpaceFloorPlan(
          venueId: 'v',
          venueSpaceId: 's',
          widthFeet: 80,
          depthFeet: 60,
          verified: true,
          tables: option.tables,
        );
        expect(validateFloorPlanLayout(plan), isEmpty);
      }
    });

    test('rejects a room too small for any table with clearance', () {
      expect(
        () => generateRoundTableLayouts(widthFeet: 5, depthFeet: 5, guestCount: 20),
        throwsFormatException,
      );
    });

    test('rejects non-positive room measurements', () {
      expect(
        () => generateRoundTableLayouts(widthFeet: 0, depthFeet: 40, guestCount: 10),
        throwsFormatException,
      );
    });

    test('rejects a non-positive guest count', () {
      expect(
        () => generateRoundTableLayouts(widthFeet: 80, depthFeet: 60, guestCount: 0),
        throwsFormatException,
      );
    });
  });

  group('floorPlanCapacity', () {
    test('multiplies table count by seats per table', () {
      final plan = VenueSpaceFloorPlan(
        venueId: 'v',
        venueSpaceId: 's',
        widthFeet: 80,
        depthFeet: 60,
        verified: true,
        seatsPerTable: 8,
        tables: const [FloorPlanTable(5, 5), FloorPlanTable(10, 5)],
      );
      expect(floorPlanCapacity(plan), 16);
    });

    test('is zero for a plan with no tables yet', () {
      final plan = VenueSpaceFloorPlan(venueId: 'v', venueSpaceId: 's', widthFeet: 80, depthFeet: 60, verified: false);
      expect(floorPlanCapacity(plan), 0);
    });
  });

  group('validateFloorPlanLayout', () {
    test('flags a table that extends past the room boundary', () {
      final plan = VenueSpaceFloorPlan(
        venueId: 'v',
        venueSpaceId: 's',
        widthFeet: 20,
        depthFeet: 20,
        verified: true,
        tables: const [FloorPlanTable(1, 1)],
      );
      expect(validateFloorPlanLayout(plan), isNotEmpty);
    });

    test('flags overlapping clearance zones', () {
      final plan = VenueSpaceFloorPlan(
        venueId: 'v',
        venueSpaceId: 's',
        widthFeet: 40,
        depthFeet: 40,
        verified: true,
        tables: const [FloorPlanTable(15, 15), FloorPlanTable(16, 15)],
      );
      expect(validateFloorPlanLayout(plan), isNotEmpty);
    });

    test('accepts a single well-clear table', () {
      final plan = VenueSpaceFloorPlan(
        venueId: 'v',
        venueSpaceId: 's',
        widthFeet: 40,
        depthFeet: 40,
        verified: true,
        tables: const [FloorPlanTable(20, 20)],
      );
      expect(validateFloorPlanLayout(plan), isEmpty);
    });
  });

  group('buildFloorPlanSceneData', () {
    final plan = VenueSpaceFloorPlan(
      venueId: 'v',
      venueSpaceId: 's',
      widthFeet: 80,
      depthFeet: 60,
      verified: true,
      tables: const [FloorPlanTable(5, 5), FloorPlanTable(10, 5), FloorPlanTable(15, 5)],
    );

    test('fills tables in order up to the confirmed guest count', () {
      final data = buildFloorPlanSceneData(plan: plan, guestCount: 15);
      final tables = data['tables'] as List;
      expect((tables[0] as Map)['occupiedSeats'], defaultSeatsPerTable);
      expect((tables[1] as Map)['occupiedSeats'], 5);
      expect((tables[2] as Map)['occupiedSeats'], 0);
    });

    test('never exceeds seatsPerTable even with excess guests', () {
      final data = buildFloorPlanSceneData(plan: plan, guestCount: 999);
      final tables = data['tables'] as List;
      for (final entry in tables) {
        expect((entry as Map)['occupiedSeats'], defaultSeatsPerTable);
      }
    });

    test('converts feet to meters for the renderer', () {
      final data = buildFloorPlanSceneData(plan: plan, guestCount: 0);
      expect(data['widthMeters'], closeTo(80 * 0.3048, 0.001));
      expect(data['heightMeters'], closeTo(60 * 0.3048, 0.001));
      expect(data['tableDiameterMeters'], closeTo(defaultTableDiameterFeet * 0.3048, 0.001));
      expect(data['seatsPerTable'], defaultSeatsPerTable);
    });
  });
}
