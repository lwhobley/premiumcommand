import 'package:cutx_premium_command/core/time/venue_time.dart';
import 'package:cutx_premium_command/features/staffing/presentation/staff_deployment_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  testWidgets('availability picker saves venue wall time as UTC', (
    tester,
  ) async {
    AvailabilityDraft? saved;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await showDialog<AvailabilityDraft>(
                  context: context,
                  builder: (_) => const AvailabilityDialog(
                    name: 'Alex',
                    timeZone: 'Asia/Tokyo',
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Times in Asia/Tokyo'), findsOneWidget);
    final venueNow = atVenue(DateTime.now(), 'Asia/Tokyo');
    expect(
      find.text(DateFormat('EEE MMM d, h:mm a').format(venueNow)),
      findsOneWidget,
    );

    Future<void> pickTime(int index, String hour, String minute) async {
      await tester.tap(find.text('Change').at(index));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(TimePickerDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), hour);
      await tester.enterText(fields.at(1), minute);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    await pickTime(0, '01', '15');
    await pickTime(1, '23', '45');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(
      saved!.startsAt,
      venueWallTimeUtc(
        DateTime.utc(venueNow.year, venueNow.month, venueNow.day, 1, 15),
        'Asia/Tokyo',
      ),
    );
    expect(saved!.startsAt.isUtc, isTrue);
    expect(saved!.endsAt.isAfter(saved!.startsAt), isTrue);
  });
}
