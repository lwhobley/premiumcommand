import 'package:flutter_test/flutter_test.dart';
import 'package:cutx_premium_command/core/time/venue_time.dart';

void main() {
  test('venue time stays fixed across device time zones', () {
    final instant = DateTime.utc(2026, 10, 14, 18);
    expect(atVenue(instant, 'America/Chicago').hour, 13);
    expect(atVenue(instant, 'America/New_York').hour, 14);
  });

  test('venue wall time converts to UTC and rejects a DST gap', () {
    expect(
      venueWallTimeUtc(DateTime.utc(2026, 10, 14, 13), 'America/Chicago'),
      DateTime.utc(2026, 10, 14, 18),
    );
    expect(
      () => venueWallTimeUtc(DateTime.utc(2026, 3, 8, 2, 30), 'America/Chicago'),
      throwsArgumentError,
    );
  });
}
