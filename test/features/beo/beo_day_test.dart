import 'package:cutx_premium_command/features/beo/domain/beo.dart';
import 'package:cutx_premium_command/features/beo/domain/beo_day.dart';
import 'package:flutter_test/flutter_test.dart';

BeoContent _content({
  String timeline = '',
  String menu = '',
  String beverage = '',
  String dietary = '',
}) => BeoContent(
  guests: 0,
  departments: const {},
  timeline: timeline,
  menu: menu,
  dietary: dietary,
  beverage: beverage,
  equipment: '',
  specialRequests: '',
);

void main() {
  final quarterfinals = [
    DateTime(2026, 11, 3),
    DateTime(2026, 11, 4),
    DateTime(2026, 11, 5),
    DateTime(2026, 11, 6),
  ];

  test('a day gets its schedule line and the menu block under its heading', () {
    final content = _content(
      timeline:
          'Tue Nov 3: food delivery 3:00 PM · Premium Level Suite 228\n'
          'Thu Nov 5: food delivery 3:00 PM · Party Suite 228/229',
      menu:
          'Tue Nov 3 (invoice #43, 12 guests)\n'
          '- 1 × Popcorn\n'
          '- 12 × Buffalo Wings\n'
          'Thu Nov 5 (invoice #46, 40 guests)\n'
          '- 2 × Nachos',
      beverage:
          'Tue Nov 3: 12 × Water\n'
          'Thu Nov 5: 24 × Pellegrino',
      dietary: 'Contains shellfish: none.',
    );

    final nov5 = beoDay(content, DateTime(2026, 11, 5), quarterfinals);
    expect(nov5.schedule, [
      'Thu Nov 5: food delivery 3:00 PM · Party Suite 228/229',
    ]);
    expect(nov5.menu, ['Thu Nov 5 (invoice #46, 40 guests)', '- 2 × Nachos']);
    expect(nov5.beverage, ['Thu Nov 5: 24 × Pellegrino']);
    // Event-wide notes show on a day that has something on the BEO.
    expect(nov5.dietary, ['Contains shellfish: none.']);

    final nov4 = beoDay(content, DateTime(2026, 11, 4), quarterfinals);
    expect(nov4.isEmpty, isTrue);
    expect(nov4.dietary, isEmpty);
  });

  test(
    'undated menu notes show on every day with a meal, schedule notes do not',
    () {
      final days = [for (var d = 24; d <= 29; d++) DateTime(2026, 11, d)];
      final content = _content(
        timeline:
            'Tue Nov 24 (load-in and rehearsal day): Load-In Crew Lunch 2:00–3:00 PM · 22\n'
            'Fri Nov 27 (3-show day): FCP Light Meal 11:00 AM–12:30 PM · 27\n'
            'Fri Nov 27: Production Meal 4:45–6:30 PM · 80\n'
            'Service times are set by the Production Stage Manager.',
        menu:
            'Menu to be proposed by the venue. Sample:\n'
            '- Load-In Crew Lunch: 1 hot entrée',
      );

      final nov27 = beoDay(content, DateTime(2026, 11, 27), days);
      expect(nov27.schedule, [
        'Fri Nov 27 (3-show day): FCP Light Meal 11:00 AM–12:30 PM · 27',
        'Fri Nov 27: Production Meal 4:45–6:30 PM · 80',
      ]);
      expect(nov27.menu, [
        'Menu to be proposed by the venue. Sample:',
        '- Load-In Crew Lunch: 1 hot entrée',
      ]);

      // A show day with no catering has nothing on the BEO.
      expect(beoDay(content, DateTime(2026, 11, 25), days).isEmpty, isTrue);
    },
  );

  test('in a one-day event every line counts', () {
    final content = _content(
      timeline: 'Food delivery 12:00 PM · Suite 201',
      menu: '- 20 × The MVP',
    );
    final day = DateTime(2026, 10, 30);
    final result = beoDay(content, day, [day]);
    expect(result.schedule, ['Food delivery 12:00 PM · Suite 201']);
    expect(result.menu, ['- 20 × The MVP']);
  });
}
