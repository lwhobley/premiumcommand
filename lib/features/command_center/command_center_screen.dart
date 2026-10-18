import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/time/venue_time.dart';
import '../../core/widgets/broadsheet.dart';
import '../../core/widgets/tag.dart';
import '../auth/application/session_controller.dart';
import '../events/application/event_providers.dart';
import '../events/domain/ops_event.dart';
import '../events/domain/readiness.dart';
import 'premium_level_card.dart';

class CommandCenterScreen extends ConsumerWidget {
  const CommandCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshots = ref.watch(eventSnapshotsProvider);
    final session = ref.watch(sessionProvider);
    final timeZone = session?.timeZone ?? 'UTC';
    final today = DateFormat('EEEE, MMMM d')
        .format(atVenue(DateTime.now(), timeZone));

    return PageScaffold(
      kicker: today,
      title: 'Command Center',
      subtitle: session?.venueName,
      children: [
        ...snapshots.when(
          loading: () => const [
            Padding(
              padding: EdgeInsets.only(top: AppSpace.xl),
              child: LinearProgressIndicator(),
            ),
          ],
          error: (error, _) => [
            EmptyNote('Could not load events. ${error.toString()}'),
          ],
          data: (items) {
            final active = items.where((s) => s.event.status.isActive).toList();
            final upcoming = items
                .where(
                  (s) =>
                      !s.event.status.isActive &&
                      s.event.status != EventStatus.closed &&
                      s.event.status != EventStatus.cancelled,
                )
                .toList();
            final overdue = active.fold<int>(
              0,
              (sum, s) => sum + s.overdueCount,
            );
            final blocked = active.fold<int>(
              0,
              (sum, s) => sum + s.blockedCount,
            );
            // The map follows the event in progress, or else the next one coming up.
            final nextUp = [...upcoming]
              ..sort(
                (a, b) => a.event.serviceStart.compareTo(b.event.serviceStart),
              );
            final mapEvent = active.isNotEmpty
                ? active.first.event
                : nextUp.firstOrNull?.event;
            final venueId = session?.venueId;

            return [
              // The four metrics as a 2 x 2 grid on every screen size.
              MetricGrid(
                metrics: [
                  Metric(value: '${active.length}', label: 'Active events'),
                  Metric(value: '${upcoming.length}', label: 'Upcoming events'),
                  Metric(
                    value: '$overdue',
                    label: 'Overdue required tasks',
                    alert: overdue > 0,
                  ),
                  Metric(
                    value: '$blocked',
                    label: 'Blocked required tasks',
                    alert: blocked > 0,
                  ),
                ],
              ),
              if (venueId != null)
                PremiumLevelCard(
                  venueId: venueId,
                  eventId: mapEvent?.id,
                  heading: mapEvent == null
                      ? 'No upcoming events'
                      : '${active.isNotEmpty ? 'Now' : 'Next'}: ${mapEvent.name}',
                ),
              const SectionHeading('Active now'),
              if (active.isEmpty) const EmptyNote('No active events.'),
              for (final s in active)
                _EventRow(snapshot: s, timeZone: timeZone),
              const SectionHeading('Upcoming'),
              if (upcoming.isEmpty) const EmptyNote('No upcoming events.'),
              for (final s in upcoming)
                _EventRow(snapshot: s, timeZone: timeZone),
            ];
          },
        ),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.snapshot, required this.timeZone});

  final EventSnapshot snapshot;
  final String timeZone;

  @override
  Widget build(BuildContext context) {
    final event = snapshot.event;
    final time = DateFormat('EEE MMM d, h:mm a')
        .format(atVenue(event.serviceStart, timeZone));

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.row - 4),
      child: OpenRow(
        title: event.name,
        trailing: Tag(event.status.label, eventStatusTone(event.status)),
        meta: '${event.type.label} · $time · ${event.managerName}',
        onTap: () => context.go('/events/${event.id}'),
        below: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final dept in snapshot.departments)
              Tag(
                dept.state == ReadinessState.noTasks
                    ? '${dept.department.label} · no tasks'
                    : '${dept.department.label} ${(dept.percent * 100).round()}%',
                readinessTone(dept.state),
              ),
          ],
        ),
      ),
    );
  }
}
