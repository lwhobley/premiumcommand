import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/icons/phosphor.dart';

import '../../../core/time/venue_time.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../../core/widgets/tag.dart';
import '../../auth/application/session_controller.dart';
import '../application/event_providers.dart';

/// Event Workspace index: every event the session can see, opening into its workspace.
class EventListScreen extends ConsumerWidget {
  const EventListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshots = ref.watch(eventSnapshotsProvider);
    final zone = ref.watch(sessionProvider)?.timeZone ?? 'UTC';

    return PageScaffold(
      kicker: 'Events',
      title: 'Event Workspace',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/events/new'),
        icon: const PhosphorIcon(PhosphorIconsDuotone.plus),
        label: const Text('New event'),
      ),
      children: snapshots.when(
        loading: () => const [LinearProgressIndicator()],
        error: (error, _) => [Text('Could not load events. $error')],
        data: (items) {
          if (items.isEmpty) return const [EmptyNote('No events yet.')];
          return [
            for (final snapshot in items)
              OpenRow(
                title: snapshot.event.name,
                meta:
                    '${DateFormat('EEE MMM d, h:mm a').format(atVenue(snapshot.event.serviceStart, zone))} $zone · ${snapshot.event.type.label}',
                trailing: Tag(
                  '${(snapshot.overallPercent * 100).round()}% ready',
                  Tone.accent,
                ),
                onTap: () => context.go('/events/${snapshot.event.id}'),
              ),
          ];
        },
      ),
    );
  }
}
