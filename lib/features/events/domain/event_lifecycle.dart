import '../../../core/permissions/app_permission.dart';
import 'ops_event.dart';

/// Forward lifecycle order: Draft → Planning → Approved → Setup → Ready → In Service → Breakdown → Closed.
const lifecycleOrder = [
  EventStatus.draft,
  EventStatus.planning,
  EventStatus.approved,
  EventStatus.setup,
  EventStatus.ready,
  EventStatus.inService,
  EventStatus.breakdown,
  EventStatus.closed,
];

class TransitionDecision {
  const TransitionDecision.allowed()
      : allowed = true,
        reason = null;

  const TransitionDecision.denied(this.reason) : allowed = false;

  final bool allowed;
  final String? reason;
}

/// Client-side mirror of the `transition_event` database function. The database
/// remains authoritative; this exists so the UI can explain a denial before calling it.
TransitionDecision evaluateTransition({
  required EventStatus from,
  required EventStatus to,
  required Set<AppPermission> permissions,
  required bool requiredTasksComplete,
}) {
  if (from == to) {
    return TransitionDecision.denied('Event is already ${to.label.toLowerCase()}.');
  }

  if (to == EventStatus.cancelled) {
    if (from == EventStatus.closed) {
      return const TransitionDecision.denied('Closed events cannot be cancelled.');
    }
    if (!permissions.contains(AppPermission.cancelOrReopenEvents)) {
      return const TransitionDecision.denied('Only directors can cancel events.');
    }
    return const TransitionDecision.allowed();
  }

  if (from == EventStatus.cancelled) {
    if (to != EventStatus.planning) {
      return const TransitionDecision.denied('A cancelled event can only be reopened to planning.');
    }
    if (!permissions.contains(AppPermission.cancelOrReopenEvents)) {
      return const TransitionDecision.denied('Only directors can reopen events.');
    }
    return const TransitionDecision.allowed();
  }

  if (from == EventStatus.closed && to == EventStatus.breakdown) {
    if (!permissions.contains(AppPermission.cancelOrReopenEvents)) {
      return const TransitionDecision.denied('Only directors can reopen closed events.');
    }
    return const TransitionDecision.allowed();
  }

  final fromIndex = lifecycleOrder.indexOf(from);
  final toIndex = lifecycleOrder.indexOf(to);
  if (fromIndex < 0 || toIndex != fromIndex + 1) {
    return TransitionDecision.denied('Events move one lifecycle step at a time.');
  }

  if (!permissions.contains(AppPermission.manageEvents)) {
    return const TransitionDecision.denied('You do not have permission to manage events.');
  }
  if (to == EventStatus.approved && !permissions.contains(AppPermission.approveBeo)) {
    return const TransitionDecision.denied('Approving an event requires BEO approval permission.');
  }
  if (to == EventStatus.ready && !requiredTasksComplete) {
    return const TransitionDecision.denied('Required tasks are not all complete.');
  }

  return const TransitionDecision.allowed();
}
