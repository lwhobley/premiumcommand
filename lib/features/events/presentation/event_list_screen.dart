import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_chip.dart';
import '../application/event_providers.dart';

/// Event Workspace index: every event the session can see, opening into its workspace.
class EventListScreen extends ConsumerWidget {
  const EventListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshots = ref.watch(eventSnapshotsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Event Workspace')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/events/new'),
        icon: const Icon(Icons.add),
        label: const Text('New event'),
      ),
      body: snapshots.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load events. $error')),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('No events yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final snapshot = items[index];
              final event = snapshot.event;
              return Card(
                child: ListTile(
                  title: Text(event.name),
                  subtitle: Text(
                    '${DateFormat('EEE MMM d, h:mm a').format(event.serviceStart)} · ${event.type.label}',
                  ),
                  trailing: StatusChip(
                    label: '${(snapshot.overallPercent * 100).round()}% ready',
                    color: snapshot.overallPercent >= 1 ? AppColors.ready : AppColors.inProgress,
                  ),
                  onTap: () => context.go('/events/${event.id}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
