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

  bool get isEmpty => schedule.isEmpty && menu.isEmpty && beverage.isEmpty;
}

/// What [content] says about [day]. A line that starts with a day ("Thu Nov 5: …") belongs to
/// that day, along with the "- " bullets under it. Lines that name no day apply to the whole
/// event: in a one-day event they all count; otherwise the menu, beverage and dietary ones show
/// on days that have something scheduled, and the schedule shows only that day's lines.
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
  // Whether the block a "- " bullet sits under applies to [day]. Bullets before any heading
  // name no day.
  var blockApplies = undated;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final bool applies;
    if (line.startsWith('- ')) {
      applies = blockApplies;
    } else if (startsWithServiceDay(line)) {
      applies = blockApplies = leadingServiceDay(line, eventDays) == day;
    } else {
      applies = blockApplies = undated;
    }
    if (applies) lines.add(line);
  }
  return lines;
}
