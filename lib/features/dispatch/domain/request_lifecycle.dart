import '../../../core/permissions/app_permission.dart';
import '../../events/domain/event_lifecycle.dart';
import 'service_request.dart';

/// Client-side mirror of `transition_service_request`. The database is authoritative.
/// [isAssignee] is true when the user is the named assignee, or when the request is
/// department-level and the user can work department requests.
TransitionDecision evaluateRequestTransition({
  required RequestStatus from,
  required RequestStatus to,
  required Set<AppPermission> permissions,
  required bool isAssignee,
  required String note,
  bool hasTarget = false,
}) {
  if (from.isTerminal) {
    return TransitionDecision.denied('This request is already ${from.label.toLowerCase()}.');
  }

  final isManager = permissions.contains(AppPermission.manageEvents);
  final canWork = isManager || isAssignee;
  final hasNote = note.trim().isNotEmpty;

  switch (to) {
    case RequestStatus.assigned:
      if (!isManager) return const TransitionDecision.denied('Only managers can assign requests.');
      if (!{RequestStatus.isNew, RequestStatus.assigned, RequestStatus.accepted, RequestStatus.blocked}.contains(from)) {
        return TransitionDecision.denied('Cannot assign a request that is ${from.label.toLowerCase()}.');
      }
      if (!hasTarget) return const TransitionDecision.denied('Choose a department or a person.');
      return const TransitionDecision.allowed();
    case RequestStatus.accepted:
      if (from != RequestStatus.assigned) return const TransitionDecision.denied('Only assigned requests can be accepted.');
      return canWork ? const TransitionDecision.allowed() : const TransitionDecision.denied('You cannot accept this request.');
    case RequestStatus.inProgress:
      if (from != RequestStatus.accepted) return const TransitionDecision.denied('Only accepted requests can be started.');
      return canWork ? const TransitionDecision.allowed() : const TransitionDecision.denied('You cannot start this request.');
    case RequestStatus.completed:
      if (from != RequestStatus.inProgress) return const TransitionDecision.denied('Only requests in progress can be completed.');
      return canWork ? const TransitionDecision.allowed() : const TransitionDecision.denied('You cannot complete this request.');
    case RequestStatus.blocked:
      if (!{RequestStatus.assigned, RequestStatus.accepted, RequestStatus.inProgress}.contains(from)) {
        return TransitionDecision.denied('Cannot block a request that is ${from.label.toLowerCase()}.');
      }
      if (!hasNote) return const TransitionDecision.denied('Give a reason to block this request.');
      return canWork ? const TransitionDecision.allowed() : const TransitionDecision.denied('You cannot block this request.');
    case RequestStatus.rejected:
      if (!{RequestStatus.isNew, RequestStatus.assigned, RequestStatus.accepted}.contains(from)) {
        return TransitionDecision.denied('Cannot reject a request that is ${from.label.toLowerCase()}.');
      }
      if (!hasNote) return const TransitionDecision.denied('Give a reason to reject this request.');
      return canWork ? const TransitionDecision.allowed() : const TransitionDecision.denied('You cannot reject this request.');
    case RequestStatus.cancelled:
      if (!isManager) return const TransitionDecision.denied('Only managers can cancel requests.');
      if (!hasNote) return const TransitionDecision.denied('Give a reason to cancel this request.');
      return const TransitionDecision.allowed();
    case RequestStatus.isNew:
      return const TransitionDecision.denied('Requests cannot return to new.');
  }
}
