import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_chip.dart';
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
  });

  final ServiceRequest request;
  final DateTime now;
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
    final escalated = request.isEscalated(now);
    final age = now.difference(request.createdAt).inMinutes;
    final primary = _primaryAction();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: escalated ? AppColors.blocked : AppColors.border,
          width: escalated ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(request.category.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                StatusChip(label: request.status.label, color: _statusColor(request.status)),
                if (request.priority != RequestPriority.normal)
                  StatusChip(
                    label: request.priority.label,
                    color: request.priority == RequestPriority.urgent ? AppColors.blocked : AppColors.attention,
                  ),
                if (escalated) const StatusChip(label: 'Escalated', color: AppColors.blocked),
              ],
            ),
            const SizedBox(height: 8),
            Text(request.description),
            const SizedBox(height: 4),
            Text(
              [
                if (request.location.isNotEmpty) request.location,
                if (request.assignedDepartment != null) 'For ${_deptLabel(request.assignedDepartment!)}',
                '${age}m ago',
              ].join(' · '),
              style: const TextStyle(color: AppColors.charcoalMuted, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: primary == null
                      ? const SizedBox.shrink()
                      : FilledButton.tonal(onPressed: primary.$2, child: Text(primary.$1)),
                ),
                if (_hasMenu) _menu(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasMenu => request.status.isOpen && (canManage || canWork);

  /// The single most useful next step for this status, or null if the user may not take it.
  (String, VoidCallback)? _primaryAction() {
    final status = request.status;
    if ((status == RequestStatus.isNew || status == RequestStatus.blocked) && canManage) {
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

  Widget _menu() {
    final status = request.status;
    return PopupMenuButton<String>(
      tooltip: 'More actions',
      icon: const Icon(Icons.more_horiz),
      onSelected: (action) {
        if (action == 'assign') {
          onAssign();
        } else if (action == 'block') {
          onWithReason(RequestStatus.blocked);
        } else if (action == 'reject') {
          onWithReason(RequestStatus.rejected);
        } else {
          onWithReason(RequestStatus.cancelled);
        }
      },
      itemBuilder: (_) => [
        if (canManage && status != RequestStatus.assigned && status != RequestStatus.blocked)
          const PopupMenuItem(value: 'assign', child: Text('Assign to department')),
        if (canWork && status != RequestStatus.blocked && status != RequestStatus.isNew)
          const PopupMenuItem(value: 'block', child: Text('Block (give a reason)')),
        if (canWork && (status == RequestStatus.isNew || status == RequestStatus.assigned || status == RequestStatus.accepted))
          const PopupMenuItem(value: 'reject', child: Text('Reject (give a reason)')),
        if (canManage) const PopupMenuItem(value: 'cancel', child: Text('Cancel (give a reason)')),
      ],
    );
  }

  static String _deptLabel(String code) => Department.fromCode(code).label;

  static Color _statusColor(RequestStatus status) => switch (status) {
        RequestStatus.isNew => AppColors.attention,
        RequestStatus.assigned || RequestStatus.accepted || RequestStatus.inProgress => AppColors.inProgress,
        RequestStatus.blocked => AppColors.blocked,
        RequestStatus.completed => AppColors.ready,
        RequestStatus.rejected || RequestStatus.cancelled => AppColors.neutral,
      };
}
