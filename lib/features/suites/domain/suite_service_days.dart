import '../../../core/time/venue_time.dart';
import 'suite_order.dart';

/// The venue calendar days an event covers, first to last, as date-only values.
List<DateTime> eventServiceDays(
  DateTime serviceStart,
  DateTime serviceEnd,
  String timeZone,
) {
  final start = _dateOf(atVenue(serviceStart, timeZone));
  final end = _dateOf(atVenue(serviceEnd, timeZone));
  return [for (var day = start; !day.isAfter(end); day = _nextDay(day)) day];
}

const _months = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];

/// An item for a particular day starts with that day: "Fri Oct 30 · The MVP".
final _dayPrefix = RegExp(
  r'^(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*,?\s+([a-z]{3})[a-z]*\.?\s+(\d{1,2})\b',
  caseSensitive: false,
);

/// Whether a line starts with a day ("Fri Oct 30 · …"), inside the event or not.
bool startsWithServiceDay(String text) => _dayPrefix.hasMatch(text.trim());

/// The event day a line starts with ("Fri Oct 30 · …"), or null when it names none or a day
/// outside the event.
DateTime? leadingServiceDay(String text, List<DateTime> eventDays) {
  final match = _dayPrefix.firstMatch(text.trim());
  if (match == null) return null;
  final month = _months.indexOf(match.group(1)!.toLowerCase()) + 1;
  final dayOfMonth = int.parse(match.group(2)!);
  return eventDays
      .where((d) => d.month == month && d.day == dayOfMonth)
      .firstOrNull;
}

/// The days of [eventDays] an order serves: days named at the start of its items, and the
/// day it is delivered. An order that names no day serves every day of the event; one whose
/// days all fall outside the event serves none.
Set<DateTime> orderServiceDays(
  SuiteOrder order,
  List<DateTime> eventDays,
  String timeZone,
) {
  final deliverAt = order.deliverAt;
  final dated =
      deliverAt != null ||
      order.items.any((item) => startsWithServiceDay(item.name));
  if (!dated) return eventDays.toSet();
  return {
    for (final item in order.items) ?leadingServiceDay(item.name, eventDays),
    if (deliverAt != null) _dateOf(atVenue(deliverAt, timeZone)),
  }.where(eventDays.contains).toSet();
}

/// Suite numbers named after "Suite" or "Suites": "Party Suite 228/229", "Suites 201, 202".
final _suiteNumbers = RegExp(
  r'suites?\s*#?\s*(\d{3}(?:\s*(?:/|,|&|and|-)\s*\d{3})*)',
  caseSensitive: false,
);

/// Suite numbers a BEO timeline places on [day]: lines that start with that day and name
/// suites ("Thu Nov 5: food delivery 3:00 PM · Premium Level Party Suite 228/229"). In a
/// one-day event a line that names no day counts as well.
Set<String> beoTimelineSuites(
  String timeline,
  DateTime day,
  List<DateTime> eventDays,
) {
  final numbers = <String>{};
  for (final line in timeline.split('\n')) {
    final lineDay = leadingServiceDay(line, eventDays);
    final onDay = lineDay == null
        ? eventDays.length == 1 && eventDays.first == day
        : lineDay == day;
    if (!onDay) continue;
    for (final match in _suiteNumbers.allMatches(line)) {
      numbers.addAll(
        RegExp(r'\d{3}').allMatches(match.group(1)!).map((m) => m.group(0)!),
      );
    }
  }
  return numbers;
}

/// Assignments whose order, with at least one item, serves [day].
Set<String> assignmentsServedOn(
  DateTime day,
  List<SuiteOrder> orders,
  List<DateTime> eventDays,
  String timeZone,
) => {
  for (final order in orders)
    if (order.items.isNotEmpty &&
        orderServiceDays(order, eventDays, timeZone).contains(day))
      order.assignmentId,
};

/// The day to show first: today when the event covers it, otherwise its first day.
DateTime? defaultServiceDay(
  List<DateTime> eventDays,
  DateTime now,
  String timeZone,
) {
  if (eventDays.isEmpty) return null;
  final today = _dateOf(atVenue(now, timeZone));
  return eventDays.contains(today) ? today : eventDays.first;
}

DateTime _dateOf(DateTime local) =>
    DateTime(local.year, local.month, local.day);

DateTime _nextDay(DateTime day) => DateTime(day.year, day.month, day.day + 1);
