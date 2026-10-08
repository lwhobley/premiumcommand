import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/application/session_controller.dart';
import '../application/event_providers.dart';
import '../domain/event_lifecycle.dart';
import '../domain/ops_event.dart';
import '../domain/readiness.dart';

class EventWorkspaceScreen extends ConsumerWidget {
  const EventWorkspaceScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(eventSnapshotProvider(eventId));

    return Scaffold(
      appBar: AppBar(title: const Text('Event workspace')),
      body: snapshot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(userMessageFor(error))),
        data: (data) => _WorkspaceBody(snapshot: data),
      ),
    );
  }
}

class _WorkspaceBody extends ConsumerWidget {
  const _WorkspaceBody({required this.snapshot});

  final EventSnapshot snapshot;

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(userMessageFor(error))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final permissions = session?.permissions ?? const <AppPermission>{};
    final event = snapshot.event;
    final actions = ref.read(eventActionsProvider);
    final time = DateFormat('EEE MMM d, y · h:mm a').format(event.serviceStart);
    final end = DateFormat('h:mm a').format(event.serviceEnd);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(event.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
            StatusChip(label: event.status.label, color: eventStatusColor(event.status)),
          ],
        ),
        const SizedBox(height: 6),
        Text('${event.type.label} · $time – $end',
            style: const TextStyle(color: AppColors.charcoalMuted)),
        Text('Manager: ${event.managerName.isEmpty ? 'Unassigned' : event.managerName} · '
            'Guaranteed guests: ${event.guaranteedGuests}',
            style: const TextStyle(color: AppColors.charcoalMuted)),
        if (event.notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(event.notes),
        ],
        const SizedBox(height: 24),
        _LifecyclePanel(snapshot: snapshot, permissions: permissions, onMove: (to) => _run(context, () => actions.moveTo(snapshot, to))),
        const SizedBox(height: 24),
        Text('Department readiness',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        for (final dept in snapshot.departments)
          _ReadinessRow(readiness: dept),
        const SizedBox(height: 24),
        Text('Tasks',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (snapshot.tasks.isEmpty)
          const Text('No tasks yet.', style: TextStyle(color: AppColors.charcoalMuted)),
        for (final task in snapshot.tasks)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: CheckboxListTile(
              value: task.status == TaskStatus.completed,
              title: Text(task.title),
              subtitle: Text(
                '${task.department.label}${task.isRequired ? '' : ' · optional'} · ${task.status.label}'
                '${task.isOverdue ? ' · overdue' : ''}',
              ),
              onChanged: permissions.contains(AppPermission.updateTasks)
                  ? (checked) => _run(
                        context,
                        () => actions.setTaskStatus(
                          task,
                          checked == true ? TaskStatus.completed : TaskStatus.notStarted,
                        ),
                      )
                  : null,
            ),
          ),
      ],
    );
  }
}

class _LifecyclePanel extends StatelessWidget {
  const _LifecyclePanel({required this.snapshot, required this.permissions, required this.onMove});

  final EventSnapshot snapshot;
  final Set<AppPermission> permissions;
  final void Function(EventStatus to) onMove;

  @override
  Widget build(BuildContext context) {
    final current = snapshot.event.status;

    // Only the next forward step plus sensitive alternatives. Blocked options show their reason.
    final currentIndex = lifecycleOrder.indexOf(current);
    final next = currentIndex >= 0 && currentIndex + 1 < lifecycleOrder.length
        ? lifecycleOrder[currentIndex + 1]
        : null;
    final options = <EventStatus>[
      ?next,
      if (current != EventStatus.cancelled && current != EventStatus.closed) EventStatus.cancelled,
      if (current == EventStatus.cancelled) EventStatus.planning,
      if (current == EventStatus.closed) EventStatus.breakdown,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lifecycle', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Current: ${current.label}', style: const TextStyle(color: AppColors.charcoalMuted)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final to in options)
                  _TransitionButton(
                    to: to,
                    decision: evaluateTransition(
                      from: current,
                      to: to,
                      permissions: permissions,
                      requiredTasksComplete: snapshot.requiredTasksComplete,
                    ),
                    onMove: onMove,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TransitionButton extends StatelessWidget {
  const _TransitionButton({required this.to, required this.decision, required this.onMove});

  final EventStatus to;
  final TransitionDecision decision;
  final void Function(EventStatus to) onMove;

  @override
  Widget build(BuildContext context) {
    final label = switch (to) {
      EventStatus.cancelled => 'Cancel event',
      _ => 'Move to ${to.label}',
    };
    final button = FilledButton.tonal(
      onPressed: decision.allowed ? () => onMove(to) : null,
      child: Text(label),
    );
    if (decision.allowed || decision.reason == null) return button;
    return Tooltip(message: decision.reason!, child: button);
  }
}

class _ReadinessRow extends StatelessWidget {
  const _ReadinessRow({required this.readiness});

  final DepartmentReadiness readiness;

  @override
  Widget build(BuildContext context) {
    final color = readinessColor(readiness.state);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(readiness.department.label)),
              Text('${readiness.completedCount}/${readiness.requiredCount} required'),
              const SizedBox(width: 12),
              StatusChip(label: readiness.state.label, color: color),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: readiness.percent,
              minHeight: 6,
              color: color,
              backgroundColor: AppColors.surfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}
