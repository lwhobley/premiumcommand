import '../../suites/domain/suite_service_days.dart';
import 'beo.dart';

/// The parts of a BEO that apply to one day of the event.
class BeoDay {
  const BeoDay({
    required this.schedule,
    required this.menu,
    required this.beverage,
    required this.dietary,
  });

  final List<String> schedule;
  final List<String> menu;
  final List<String> beverage;
  final List<String> dietary;

  bool get isEmpty =>
      schedule.isEmpty && menu.isEmpty && beverage.isEmpty && dietary.isEmpty;
}

/// What [content] says about [day]. A line that starts with a day ("Thu Nov 5: …") belongs to
/// that day, with the "- " bullets under it; under a day heading ("Thu Nov 5:", "Thu Nov 5
/// (invoice #46)") every line up to the next day or a blank line belongs to that day. Lines that
/// name no day apply to the whole event: in a one-day event they all count; otherwise the menu,
/// beverage and dietary ones show on days that have something scheduled, and the schedule shows
/// only that day's lines.
BeoDay beoDay(BeoContent content, DateTime day, List<DateTime> eventDays) {
  final oneDay = eventDays.length == 1 && eventDays.first == day;
  final schedule = _linesOn(content.timeline, day, eventDays, undated: oneDay);
  final general = oneDay || schedule.isNotEmpty;
  return BeoDay(
    schedule: schedule,
    menu: _linesOn(content.menu, day, eventDays, undated: general),
    beverage: _linesOn(content.beverage, day, eventDays, undated: general),
    dietary: _linesOn(content.dietary, day, eventDays, undated: general),
  );
}

/// The lines of [text] for [day], plus the lines that name no day when [undated] is set.
List<String> _linesOn(
  String text,
  DateTime day,
  List<DateTime> eventDays, {
  required bool undated,
}) {
  final lines = <String>[];
  // Whether a "- " bullet applies to [day]: bullets follow the line above them. Bullets before
  // any heading name no day.
  var bulletApplies = undated;
  // Whether a plain line applies to [day] while under a day heading; null outside one.
  bool? headingApplies;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) {
      headingApplies = null;
      bulletApplies = undated;
      continue;
    }
    final bool applies;
    if (line.startsWith('- ')) {
      applies = bulletApplies;
    } else if (startsWithServiceDay(line)) {
      applies = bulletApplies = leadingServiceDay(line, eventDays) == day;
      headingApplies = isServiceDayHeading(line) ? applies : null;
    } else {
      applies = bulletApplies = headingApplies ?? undated;
    }
    if (applies) lines.add(line);
  }
  return lines;
}
