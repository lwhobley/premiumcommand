import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_chip.dart';
import '../application/event_providers.dart';
import '../domain/readiness.dart';

/// Events grouped by service day, in venue-local time.
class EventCalendarScreen extends ConsumerWidget {
  const EventCalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshots = ref.watch(eventSnapshotsProvider);
    final dayFormat = DateFormat('EEEE, MMMM d');
    final timeFormat = DateFormat('h:mm a');

    return Scaffold(
      appBar: AppBar(title: const Text('Event Calendar')),
      body: snapshots.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load events. $error')),
        data: (items) {
          final byDay = <String, List<EventSnapshot>>{};
          for (final snapshot in items) {
            final key = dayFormat.format(snapshot.event.serviceStart);
            byDay.putIfAbsent(key, () => []).add(snapshot);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final entry in byDay.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(entry.key,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                ),
                for (final snapshot in entry.value)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(snapshot.event.name),
                      subtitle: Text(
                        '${timeFormat.format(snapshot.event.serviceStart)} – ${timeFormat.format(snapshot.event.serviceEnd)} · ${snapshot.event.type.label}',
                      ),
                      trailing: StatusChip(
                        label: snapshot.event.status.label,
                        color: eventStatusColor(snapshot.event.status),
                      ),
                      onTap: () => context.go('/events/${snapshot.event.id}'),
                    ),
                  ),
              ],
              if (byDay.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No events scheduled.', style: TextStyle(color: AppColors.charcoalMuted)),
                ),
            ],
          );
        },
      ),
    );
  }
}
