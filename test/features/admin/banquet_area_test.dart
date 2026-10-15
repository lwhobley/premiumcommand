import 'package:cutx_premium_command/features/admin/domain/banquet_area.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('meeting room group preserves two separate capacities and an unknown combined capacity', () {
    final area = BanquetArea.fromJson({
      'id': 'area-1',
      'venue_id': 'venue-1',
      'venue_space_id': null,
      'name': 'Meeting Rooms',
      'kind': 'meeting_room_group',
      'space_count': 2,
      'capacity_per_space': 32,
      'area_square_feet': null,
      'can_combine': true,
      'combined_capacity': null,
      'has_full_service_bar': null,
    });

    expect(area.spaceCount, 2);
    expect(area.capacityPerSpace, 32);
    expect(area.combinedCapacity, isNull);
    expect(area.venueSpaceId, isNull);
  });

  test('premium lounge keeps measured area, capacity, and bar service', () {
    final area = BanquetArea.fromJson({
      'id': 'area-2',
      'venue_id': 'venue-1',
      'venue_space_id': 'space-2',
      'name': 'Premium Level Lounge',
      'kind': 'premium_lounge',
      'space_count': 1,
      'capacity_per_space': 100,
      'area_square_feet': 2000,
      'can_combine': false,
      'combined_capacity': null,
      'has_full_service_bar': true,
    });

    expect(area.areaSquareFeet, 2000);
    expect(area.capacityPerSpace, 100);
    expect(area.hasFullServiceBar, isTrue);
  });
}
