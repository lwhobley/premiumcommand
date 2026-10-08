import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/status_chip.dart';
import '../events/application/event_providers.dart';
import '../events/domain/ops_event.dart';
import '../events/domain/readiness.dart';

class CommandCenterScreen extends ConsumerWidget {
  const CommandCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshots = ref.watch(eventSnapshotsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Command Center')),
      body: snapshots.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load events. ${error.toString()}')),
        data: (items) {
          final active = items.where((s) => s.event.status.isActive).toList();
          final upcoming = items.where((s) => !s.event.status.isActive && s.event.status != EventStatus.closed && s.event.status != EventStatus.cancelled).toList();
          final overdue = active.fold<int>(0, (sum, s) => sum + s.overdueCount);
          final blocked = active.fold<int>(0, (sum, s) => sum + s.blockedCount);

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _Metric(label: 'Active events', value: '${active.length}'),
                  _Metric(label: 'Upcoming events', value: '${upcoming.length}'),
                  _Metric(label: 'Overdue required tasks', value: '$overdue', alert: overdue > 0),
                  _Metric(label: 'Blocked required tasks', value: '$blocked', alert: blocked > 0),
                ],
              ),
              const SizedBox(height: 24),
              _SectionHeader('Active now'),
              if (active.isEmpty) const _Empty('No active events.'),
              for (final s in active) _SnapshotCard(snapshot: s),
              const SizedBox(height: 24),
              _SectionHeader('Upcoming'),
              if (upcoming.isEmpty) const _Empty('No upcoming events.'),
              for (final s in upcoming) _SnapshotCard(snapshot: s),
            ],
          );
        },
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.alert = false});

  final String label;
  final String value;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final color = alert ? AppColors.blocked : AppColors.charcoal;
    return SizedBox(
      width: 200,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: AppColors.charcoalMuted, fontSize: 13)),
              const SizedBox(height: 6),
              Text(value, style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text, style: const TextStyle(color: AppColors.charcoalMuted)),
    );
  }
}

class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({required this.snapshot});

  final EventSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final event = snapshot.event;
    final time = DateFormat('EEE MMM d, h:mm a').format(event.serviceStart);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/events/${event.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(event.name,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  StatusChip(label: event.status.label, color: eventStatusColor(event.status)),
                ],
              ),
              const SizedBox(height: 4),
              Text('${event.type.label} · $time · ${event.managerName}',
                  style: const TextStyle(color: AppColors.charcoalMuted, fontSize: 13)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final dept in snapshot.departments)
                    StatusChip(
                      label: '${dept.department.label} ${(dept.percent * 100).round()}%',
                      color: readinessColor(dept.state),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
