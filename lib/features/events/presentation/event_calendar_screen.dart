import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/time/venue_time.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../../core/widgets/tag.dart';
import '../../auth/application/session_controller.dart';
import '../application/event_providers.dart';
import '../domain/readiness.dart';

/// Events grouped by service day, in venue-local time.
class EventCalendarScreen extends ConsumerWidget {
  const EventCalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshots = ref.watch(eventSnapshotsProvider);
    final zone = ref.watch(sessionProvider)?.timeZone ?? 'UTC';
    final dayFormat = DateFormat('EEEE, MMMM d, y');
    final timeFormat = DateFormat('h:mm a');

    return PageScaffold(
      kicker: 'Events',
      title: 'Event Calendar',
      children: snapshots.when(
        loading: () => const [LinearProgressIndicator()],
        error: (error, _) => [Text('Could not load events. $error')],
        data: (items) {
          final byDay = <String, List<EventSnapshot>>{};
          for (final snapshot in items) {
            final key = dayFormat.format(
              atVenue(snapshot.event.serviceStart, zone),
            );
            byDay.putIfAbsent(key, () => []).add(snapshot);
          }
          return [
            for (final (index, entry) in byDay.entries.indexed) ...[
              SectionHeading(entry.key, first: index == 0),
              for (final snapshot in entry.value)
                OpenRow(
                  title: snapshot.event.name,
                  meta:
                      '${timeFormat.format(atVenue(snapshot.event.serviceStart, zone))} – ${timeFormat.format(atVenue(snapshot.event.serviceEnd, zone))} $zone · ${snapshot.event.type.label}',
                  trailing: Tag(
                    snapshot.event.status.label,
                    eventStatusTone(snapshot.event.status),
                  ),
                  onTap: () => context.go('/events/${snapshot.event.id}'),
                ),
            ],
            if (byDay.isEmpty) const EmptyNote('No events scheduled.'),
          ];
        },
      ),
    );
  }
}
