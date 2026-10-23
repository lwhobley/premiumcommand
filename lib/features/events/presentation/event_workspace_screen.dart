import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/venue_time.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../../core/widgets/tag.dart';
import '../../auth/application/session_controller.dart';
import '../../floor_plan/presentation/event_floor_plan_card.dart';
import '../../meeting_notes/presentation/event_meeting_notes_card.dart';
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
    final back = Navigator.of(context).canPop() ? const BackLink() : null;

    return snapshot.when(
      loading: () => PageScaffold(
        back: back,
        kicker: 'Events',
        title: 'Event workspace',
        children: const [LinearProgressIndicator()],
      ),
      error: (error, _) => PageScaffold(
        back: back,
        kicker: 'Events',
        title: 'Event workspace',
        children: [Text(userMessageFor(error))],
      ),
      data: (data) => _WorkspaceBody(snapshot: data, back: back),
    );
  }
}

class _WorkspaceBody extends ConsumerWidget {
  const _WorkspaceBody({required this.snapshot, required this.back});

  final EventSnapshot snapshot;
  final BackLink? back;

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
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
    final zone = session?.timeZone ?? 'UTC';
    final time = DateFormat('EEE MMM d, y · h:mm a')
        .format(atVenue(event.serviceStart, zone));
    final end = DateFormat('h:mm a').format(atVenue(event.serviceEnd, zone));
    final hasIssues = snapshot.overdueCount > 0 || snapshot.blockedCount > 0;

    return PageScaffold(
      back: back,
      kicker: event.type.label,
      title: event.name,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Tag(event.status.label, eventStatusTone(event.status)),
        ),
        const SizedBox(height: AppSpace.l),
        FactGrid(
          facts: [
            ('Service', '$time – $end $zone'),
            (
              'Manager',
              event.managerName.isEmpty ? 'Unassigned' : event.managerName,
            ),
            ('Guaranteed guests', '${event.guaranteedGuests}'),
          ],
        ),
        if (event.notes.isNotEmpty) ...[
          const SizedBox(height: AppSpace.m),
          Text(event.notes, style: AppText.body),
        ],
        const SectionHeading('Department readiness'),
        for (final dept in snapshot.departments) _ReadinessRow(readiness: dept),
        Text(
          '${snapshot.overdueCount} overdue · ${snapshot.blockedCount} blocked',
          style: AppText.meta.copyWith(
            color: hasIssues ? AppColors.accent2700 : AppColors.muted,
          ),
        ),
        _LifecyclePanel(
          snapshot: snapshot,
          permissions: permissions,
          onMove: (to) => _run(context, () => actions.moveTo(snapshot, to)),
        ),
        EventMeetingNotesCard(eventId: event.id),
        const SectionHeading('Tasks'),
        if (snapshot.tasks.isEmpty) const EmptyNote('No tasks yet.'),
        for (final task in snapshot.tasks)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: task.status == TaskStatus.completed,
            title: Text(task.title),
            subtitle: Text(
              '${task.department.label}${task.isRequired ? '' : ' · optional'} · ${task.status.label}'
              '${task.isOverdueAt(DateTime.now()) ? ' · overdue' : ''}'
              '${task.needsReview ? '\nBEO changed: ${task.reviewReason}' : ''}',
            ),
            onChanged: permissions.contains(AppPermission.updateTasks)
                ? (checked) => _run(
                    context,
                    () => actions.setTaskStatus(
                      task,
                      checked == true
                          ? TaskStatus.completed
                          : TaskStatus.notStarted,
                    ),
                  )
                : null,
          ),
        EventFloorPlanCard(
          eventId: event.id,
          guaranteedGuests: event.guaranteedGuests,
        ),
      ],
    );
  }
}

class _LifecyclePanel extends StatelessWidget {
  const _LifecyclePanel({
    required this.snapshot,
    required this.permissions,
    required this.onMove,
  });

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
      if (current != EventStatus.cancelled && current != EventStatus.closed)
        EventStatus.cancelled,
      if (current == EventStatus.cancelled) EventStatus.planning,
      if (current == EventStatus.closed) EventStatus.breakdown,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading('Lifecycle'),
        Text('Current: ${current.label}', style: AppText.meta),
        const SizedBox(height: AppSpace.m),
        Wrap(
          spacing: AppSpace.s,
          runSpacing: AppSpace.s,
          children: [
            for (final to in options)
              _TransitionButton(
                to: to,
                primary: to == next,
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
    );
  }
}

class _TransitionButton extends StatelessWidget {
  const _TransitionButton({
    required this.to,
    required this.primary,
    required this.decision,
    required this.onMove,
  });

  final EventStatus to;

  /// The next forward step is the primary action; alternatives are outlined.
  final bool primary;
  final TransitionDecision decision;
  final void Function(EventStatus to) onMove;

  @override
  Widget build(BuildContext context) {
    final label = switch (to) {
      EventStatus.cancelled => 'Cancel event',
      _ => 'Move to ${to.label}',
    };
    final onPressed = decision.allowed ? () => onMove(to) : null;
    final button = primary
        ? FilledButton(onPressed: onPressed, child: Text(label))
        : OutlinedButton(onPressed: onPressed, child: Text(label));
    if (decision.allowed || decision.reason == null) return button;
    return Tooltip(message: decision.reason!, child: button);
  }
}

class _ReadinessRow extends StatelessWidget {
  const _ReadinessRow({required this.readiness});

  final DepartmentReadiness readiness;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.row),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  readiness.department.label,
                  style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${readiness.completedCount}/${readiness.requiredCount} required',
                style: AppText.meta,
              ),
              const SizedBox(width: 12),
              Tag(readiness.state.label, readinessTone(readiness.state)),
            ],
          ),
          const SizedBox(height: 6),
          ProgressLine(
            value: readiness.percent,
            // The bar takes the readiness state's tone, so it never contradicts the tag.
            tone: readinessTone(readiness.state),
          ),
        ],
      ),
    );
  }
}
