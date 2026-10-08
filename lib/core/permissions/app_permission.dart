/// Granular permissions. The [code] values match `permissions.code` in the database
/// and are the same values enforced by RLS and the `transition_event` function.
enum AppPermission {
  viewOperations('view_operations'),
  manageEvents('manage_events'),
  approveBeo('approve_beo'),
  cancelOrReopenEvents('cancel_or_reopen_events'),
  deployStaff('deploy_staff'),
  updateTasks('update_tasks'),
  manageRequests('manage_requests'),
  runInspections('run_inspections'),
  reviewInspections('review_inspections'),
  viewCulinary('view_culinary'),
  manageBanquets('manage_banquets'),
  closeOutEvents('close_out_events'),
  viewReports('view_reports'),
  manageConfiguration('manage_configuration');

  const AppPermission(this.code);

  final String code;
}

/// Venue roles. Users may hold several roles at one venue.
enum AppRole {
  director('director', 'Director of Premium'),
  premiumManager('premium_manager', 'Premium Manager'),
  banquetCaptain('banquet_captain', 'Banquet Captain'),
  suiteAttendant('suite_attendant', 'Suite Attendant'),
  runner('runner', 'Runner'),
  culinaryLead('culinary_lead', 'Executive Chef / Culinary Lead'),
  beverageLead('beverage_lead', 'Bartender / Beverage Lead');

  const AppRole(this.code, this.label);

  final String code;
  final String label;

  static AppRole? fromCode(String code) {
    for (final role in values) {
      if (role.code == code) return role;
    }
    return null;
  }
}

/// Default permission grants per role. The database `role_permissions` table is
/// authoritative for enforcement; this mirrors its seed data for UI gating.
const Map<AppRole, Set<AppPermission>> defaultRolePermissions = {
  AppRole.director: {...AppPermission.values},
  AppRole.premiumManager: {
    AppPermission.viewOperations,
    AppPermission.manageEvents,
    AppPermission.deployStaff,
    AppPermission.updateTasks,
    AppPermission.manageRequests,
    AppPermission.runInspections,
    AppPermission.reviewInspections,
    AppPermission.viewCulinary,
    AppPermission.viewReports,
  },
  AppRole.banquetCaptain: {
    AppPermission.viewOperations,
    AppPermission.updateTasks,
    AppPermission.manageBanquets,
    AppPermission.closeOutEvents,
    AppPermission.runInspections,
    AppPermission.manageRequests,
    AppPermission.viewCulinary,
  },
  AppRole.suiteAttendant: {
    AppPermission.viewOperations,
    AppPermission.updateTasks,
    AppPermission.runInspections,
    AppPermission.manageRequests,
  },
  AppRole.runner: {
    AppPermission.viewOperations,
    AppPermission.updateTasks,
    AppPermission.manageRequests,
  },
  AppRole.culinaryLead: {
    AppPermission.viewOperations,
    AppPermission.viewCulinary,
    AppPermission.updateTasks,
    AppPermission.manageRequests,
    AppPermission.runInspections,
  },
  AppRole.beverageLead: {
    AppPermission.viewOperations,
    AppPermission.updateTasks,
    AppPermission.runInspections,
    AppPermission.manageRequests,
  },
};

Set<AppPermission> permissionsFor(Iterable<AppRole> roles) {
  return {for (final role in roles) ...?defaultRolePermissions[role]};
}
