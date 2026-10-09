import '../../../core/permissions/app_permission.dart';
import '../../events/domain/readiness.dart';
import 'service_request.dart';

/// Which departments a role works. Directors and premium managers see everything.
Set<Department> departmentsFor(Set<AppRole> roles) {
  const byRole = <AppRole, Set<Department>>{
    AppRole.suiteAttendant: {Department.suites},
    AppRole.banquetCaptain: {Department.banquets},
    AppRole.culinaryLead: {Department.culinary},
    AppRole.beverageLead: {Department.beverage},
    AppRole.runner: {Department.operations},
  };
  final result = <Department>{};
  for (final role in roles) {
    if (role == AppRole.director || role == AppRole.premiumManager) {
      return Department.values.toSet();
    }
    result.addAll(byRole[role] ?? const {});
  }
  return result;
}

/// Open requests that belong to this user: named to them, or to one of their departments.
List<ServiceRequest> requestsForShift({
  required List<ServiceRequest> requests,
  required String userId,
  required Set<Department> departments,
}) {
  return requests.where((request) {
    if (!request.status.isOpen) return false;
    if (request.assignedUserId == userId) return true;
    final dept = request.assignedDepartment;
    return dept != null && departments.any((d) => d.code == dept);
  }).toList();
}

/// Priority order for the dispatch board: escalated first, then urgency, then age.
int compareForDispatch(
  ServiceRequest a,
  ServiceRequest b,
  DateTime now, [
  Map<RequestPriority, Duration>? thresholds,
]) {
  final aEsc = a.isEscalated(now, thresholds) ? 0 : 1;
  final bEsc = b.isEscalated(now, thresholds) ? 0 : 1;
  if (aEsc != bEsc) return aEsc.compareTo(bEsc);
  final pri = b.priority.index.compareTo(a.priority.index);
  if (pri != 0) return pri;
  return a.createdAt.compareTo(b.createdAt);
}
