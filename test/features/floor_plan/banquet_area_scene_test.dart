import 'package:cutx_premium_command/features/admin/domain/banquet_area.dart';
import 'package:cutx_premium_command/features/floor_plan/domain/banquet_area_scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const meetingRooms = BanquetArea(
    id: 'meeting-group',
    venueId: 'venue',
    name: 'Meeting Rooms',
    kind: 'meeting_room_group',
    spaceCount: 2,
    capacityPerSpace: 32,
    canCombine: true,
  );

  test('3D schematic includes two rooms and a combined toggle, no inferred dimensions', () {
    final separate = buildBanquetAreaSceneData(meetingRooms);
    final combined = buildBanquetAreaSceneData(meetingRooms, combined: true);

    expect(separate['spaceCount'], 2);
    expect(separate['combined'], false);
    expect(combined['combined'], true);
    expect(combined, isNot(contains('widthMeters')));
    expect(combined, isNot(contains('heightMeters')));
    expect(combined, isNot(contains('combinedCapacity')));
    expect(combined, isNot(contains('tables')));
  });

  test('a single area cannot be shown as a combined room', () {
    const arena = BanquetArea(
      id: 'arena',
      venueId: 'venue',
      name: 'Main Arena Floor',
      kind: 'arena_floor',
      spaceCount: 1,
      canCombine: false,
    );
    expect(buildBanquetAreaSceneData(arena, combined: true)['combined'], false);
  });
}
