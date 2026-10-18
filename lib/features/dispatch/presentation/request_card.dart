import 'package:flutter/material.dart';

import '../../../core/icons/phosphor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../../core/widgets/tag.dart';
import '../../events/domain/readiness.dart';
import '../domain/service_request.dart';

/// A request row with the next step for its status, plus less common actions in a menu.
/// The parent screen owns dialogs (assign, reason) and the actual writes.
class RequestCard extends StatelessWidget {
  const RequestCard({
    super.key,
    required this.request,
    required this.now,
    required this.canManage,
    required this.canWork,
    required this.onAdvance,
    required this.onAssign,
    required this.onWithReason,
    this.thresholds,
  });

  final ServiceRequest request;
  final DateTime now;

  /// The venue's escalation limits. Null means the built-in defaults.
  final Map<RequestPriority, Duration>? thresholds;
  final bool canManage;
  final bool canWork;

  /// Moves to accepted, in progress, or completed without extra input.
  final void Function(RequestStatus to) onAdvance;

  /// Opens the department picker for assignment.
  final VoidCallback onAssign;

  /// Opens the reason prompt, then moves to blocked, rejected, or cancelled.
  final void Function(RequestStatus to) onWithReason;

  @override
  Widget build(BuildContext context) {
    final escalated = request.isEscalated(now, thresholds);
    final age = now.difference(request.createdAt).inMinutes;
    final primary = _primaryAction();
    final menuItems = _menuItems();
    final alert = escalated || request.status == RequestStatus.blocked;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: OpenRow(
        title: request.category.label,
        trailing: request.priority == RequestPriority.normal && !escalated
            ? null
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (request.priority != RequestPriority.normal)
                    Tag(
                      request.priority.label,
                      _priorityTone(request.priority),
                    ),
                  if (escalated) const Tag('Escalated', Tone.alert),
                ],
              ),
        below: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(request.description, style: AppText.body),
            const SizedBox(height: 3),
            Text(
              [
                request.status.label,
                if (request.location.isNotEmpty) request.location,
                if (request.assignedDepartment != null)
                  'For ${_deptLabel(request.assignedDepartment!)}',
                '${age}m ago',
              ].join(' · '),
              style: AppText.meta.copyWith(
                color: alert ? AppColors.accent2700 : AppColors.muted,
              ),
            ),
            if (primary != null || _canBlock || menuItems.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        if (primary != null)
                          FilledButton(
                            onPressed: primary.$2,
                            child: Text(primary.$1),
                          ),
                        if (_canBlock)
                          OutlinedButton(
                            onPressed: () =>
                                onWithReason(RequestStatus.blocked),
                            child: const Text('Block'),
                          ),
                      ],
                    ),
                  ),
                  if (menuItems.isNotEmpty) _menu(menuItems),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool get _hasMenu => request.status.isOpen && (canManage || canWork);

  /// Block is offered as its own button; the database allows it from any open status but new.
  bool get _canBlock =>
      _hasMenu &&
      canWork &&
      request.status != RequestStatus.blocked &&
      request.status != RequestStatus.isNew;

  /// The single most useful next step for this status, or null if the user may not take it.
  (String, VoidCallback)? _primaryAction() {
    final status = request.status;
    if ((status == RequestStatus.isNew || status == RequestStatus.blocked) &&
        canManage) {
      return ('Assign', onAssign);
    }
    if (status == RequestStatus.assigned && canWork) {
      return ('Accept', () => onAdvance(RequestStatus.accepted));
    }
    if (status == RequestStatus.accepted && canWork) {
      return ('Start', () => onAdvance(RequestStatus.inProgress));
    }
    if (status == RequestStatus.inProgress && canWork) {
      return ('Complete', () => onAdvance(RequestStatus.completed));
    }
    return null;
  }

  List<PopupMenuEntry<String>> _menuItems() {
    if (!_hasMenu) return const [];
    final status = request.status;
    return [
      // Reassignment: the database allows assign from new, assigned, accepted and blocked.
      // New and blocked already have the primary Assign button, so the menu covers the rest.
      if (canManage &&
          (status == RequestStatus.assigned ||
              status == RequestStatus.accepted))
        const PopupMenuItem(
          value: 'assign',
          child: Text('Reassign to department'),
        ),
      if (canWork &&
          (status == RequestStatus.isNew ||
              status == RequestStatus.assigned ||
              status == RequestStatus.accepted))
        const PopupMenuItem(
          value: 'reject',
          child: Text('Reject (give a reason)'),
        ),
      if (canManage)
        const PopupMenuItem(
          value: 'cancel',
          child: Text('Cancel (give a reason)'),
        ),
    ];
  }

  Widget _menu(List<PopupMenuEntry<String>> items) {
    return PopupMenuButton<String>(
      tooltip: 'More actions',
      icon: const PhosphorIcon(PhosphorIconsDuotone.dotsThree),
      onSelected: (action) {
        if (action == 'assign') {
          onAssign();
        } else if (action == 'reject') {
          onWithReason(RequestStatus.rejected);
        } else {
          onWithReason(RequestStatus.cancelled);
        }
      },
      itemBuilder: (_) => items,
    );
  }

  static String _deptLabel(String code) => Department.fromCode(code).label;

  static Tone _priorityTone(RequestPriority priority) =>
      priority == RequestPriority.urgent ? Tone.alert : Tone.neutral;
}
