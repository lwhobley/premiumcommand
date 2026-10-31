import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/session_controller.dart';
import '../../events/application/event_providers.dart';
import '../../planning/application/planning_providers.dart';
import '../domain/suite_service_days.dart';

/// The venue days an event covers. Empty until the event loads.
final eventServiceDaysProvider = Provider.family<List<DateTime>, String>((
  ref,
  eventId,
) {
  final event = ref.watch(eventSnapshotProvider(eventId)).value?.event;
  if (event == null) return const [];
  final timeZone = ref.watch(sessionProvider)?.timeZone ?? 'UTC';
  return eventServiceDays(event.serviceStart, event.serviceEnd, timeZone);
});

/// The day Premium Spaces is showing for an event. Starts on today when the event covers it,
/// otherwise on the event's first day.
final selectedServiceDayProvider =
    NotifierProvider.family<SelectedServiceDay, DateTime?, String>(
      SelectedServiceDay.new,
    );

class SelectedServiceDay extends Notifier<DateTime?> {
  SelectedServiceDay(this.eventId);

  final String eventId;

  @override
  DateTime? build() {
    final days = ref.watch(eventServiceDaysProvider(eventId));
    // Events reload every 30 seconds, rebuilding this: keep the day picked while the event
    // still covers it.
    final picked = stateOrNull;
    if (picked != null && days.contains(picked)) return picked;
    final timeZone = ref.watch(sessionProvider)?.timeZone ?? 'UTC';
    return defaultServiceDay(days, DateTime.now(), timeZone);
  }

  void select(DateTime day) => state = day;
}

/// Suite assignments with a BEO on the selected day, shown striped: those whose order serves
/// that day, and those the event BEO's timeline names for that day (a suite sharing another
/// suite's order, such as 229 with 228). Uses the approved BEO, or the latest draft.
final beoAssignmentIdsProvider = Provider.family<Set<String>, String>((
  ref,
  eventId,
) {
  final day = ref.watch(selectedServiceDayProvider(eventId));
  if (day == null) return const {};
  final orders = ref.watch(suiteOrdersProvider(eventId)).value ?? const [];
  final days = ref.watch(eventServiceDaysProvider(eventId));
  final timeZone = ref.watch(sessionProvider)?.timeZone ?? 'UTC';
  final beo = ref.watch(beoProvider(eventId)).value;
  final timeline = (beo?.approved ?? beo?.latest)?.content.timeline ?? '';
  final named = beoTimelineSuites(timeline, day, days);
  final assignments = ref.watch(suitesProvider(eventId)).value ?? const [];
  return {
    ...assignmentsServedOn(day, orders, days, timeZone),
    for (final a in assignments)
      if (named.contains(a.planArea)) a.id,
  };
});

/// Suite assignments in use on the selected day of a multi-day event, or null when there is
/// nothing to filter (a one-day event, or no day yet): suites booked for particular shows show
/// only on those days.
final dayAssignmentIdsProvider = Provider.family<Set<String>?, String>((
  ref,
  eventId,
) {
  final days = ref.watch(eventServiceDaysProvider(eventId));
  final day = ref.watch(selectedServiceDayProvider(eventId));
  if (day == null || days.length < 2) return null;
  final assignments = ref.watch(suitesProvider(eventId)).value ?? const [];
  return assignmentsInUseOn(
    day,
    assignments,
    days,
    ref.watch(beoAssignmentIdsProvider(eventId)),
  );
});
