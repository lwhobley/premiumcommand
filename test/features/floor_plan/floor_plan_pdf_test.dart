import 'dart:convert';

import 'package:cutx_premium_command/features/floor_plan/data/floor_plan_pdf.dart';
import 'package:cutx_premium_command/features/floor_plan/domain/floor_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a floor plan exports as a PDF document',
    () async {
      final plan = VenueSpaceFloorPlan(
        venueId: 'v',
        venueSpaceId: 's',
        widthFeet: 120,
        depthFeet: 80,
        verified: false,
        tables: const [FloorPlanTable(30, 20), FloorPlanTable(60, 40)],
      );
      final bytes = await buildFloorPlanPdf(
        spaceName: 'Premium Level Lounge',
        plan: plan,
        venueName: 'Credit Union of Texas Event Center',
      );
      expect(bytes.length, greaterThan(500));
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    },
  );
}
