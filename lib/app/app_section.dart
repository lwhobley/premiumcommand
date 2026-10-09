import 'package:flutter/material.dart';

import '../core/permissions/app_permission.dart';
import '../features/command_center/command_center_screen.dart';
import '../features/admin/presentation/admin_screen.dart';
import '../features/beo/presentation/beo_screen.dart';
import '../features/closeout/presentation/closeout_screen.dart';
import '../features/operations/presentation/communications_screen.dart';
import '../features/operations/presentation/culinary_screen.dart';
import '../features/operations/presentation/inspections_screen.dart';
import '../features/dispatch/presentation/dispatch_screen.dart';
import '../features/staffing/presentation/staff_screen.dart';
import '../features/suites/presentation/premium_spaces_screen.dart';
import '../features/dispatch/presentation/my_shift_screen.dart';
import '../features/events/presentation/event_calendar_screen.dart';
import '../features/events/presentation/event_list_screen.dart';

/// Primary navigation sections. Routes and nav items are both derived from this list.
/// A null [permission] means any signed-in user may open the section.
enum AppSection {
  commandCenter(
    path: '/command',
    label: 'Command Center',
    icon: Icons.dashboard_outlined,
    permission: AppPermission.viewOperations,
    phase: 1,
  ),
  eventCalendar(
    path: '/calendar',
    label: 'Event Calendar',
    icon: Icons.calendar_month_outlined,
    permission: AppPermission.viewOperations,
    phase: 1,
  ),
  eventWorkspace(
    path: '/events',
    label: 'Event Workspace',
    icon: Icons.event_note_outlined,
    permission: AppPermission.viewOperations,
    phase: 1,
  ),
  beoManagement(
    path: '/beo',
    label: 'BEO Management',
    icon: Icons.description_outlined,
    permission: AppPermission.viewOperations,
    phase: 2,
  ),
  premiumSpaces(
    path: '/spaces',
    label: 'Premium Spaces',
    icon: Icons.meeting_room_outlined,
    permission: AppPermission.viewOperations,
    phase: 2,
  ),
  banquetsCulinary(
    path: '/culinary',
    label: 'Banquets & Culinary',
    icon: Icons.restaurant_outlined,
    permission: AppPermission.viewCulinary,
    phase: 3,
  ),
  staffDeployment(
    path: '/staff',
    label: 'Staff Deployment',
    icon: Icons.groups_outlined,
    permission: AppPermission.deployStaff,
    phase: 2,
  ),
  liveDispatch(
    path: '/dispatch',
    label: 'Live Service Dispatch',
    icon: Icons.bolt_outlined,
    permission: AppPermission.manageRequests,
    phase: 2,
  ),
  myShift(
    path: '/my-shift',
    label: 'My Shift',
    icon: Icons.badge_outlined,
    permission: null,
    phase: 2,
  ),
  inspections(
    path: '/inspections',
    label: 'Inspections & Checklists',
    icon: Icons.checklist_outlined,
    permission: AppPermission.runInspections,
    phase: 3,
  ),
  communications(
    path: '/communications',
    label: 'Communications',
    icon: Icons.campaign_outlined,
    permission: null,
    phase: 3,
  ),
  closeout(
    path: '/closeout',
    label: 'Event Closeout & Reports',
    icon: Icons.assignment_turned_in_outlined,
    permission: AppPermission.viewReports,
    phase: 3,
  ),
  administration(
    path: '/admin',
    label: 'Administration & Configuration',
    icon: Icons.settings_outlined,
    permission: AppPermission.manageConfiguration,
    phase: 4,
  );

  const AppSection({
    required this.path,
    required this.label,
    required this.icon,
    required this.permission,
    required this.phase,
  });

  final String path;
  final String label;
  final IconData icon;
  final AppPermission? permission;
  final int phase;

  bool allows(Set<AppPermission> permissions) =>
      permission == null || permissions.contains(permission);

  /// Builds the screen for this section. Sections not yet built show a labeled placeholder.
  Widget buildScreen() {
    return switch (this) {
      AppSection.commandCenter => const CommandCenterScreen(),
      AppSection.eventCalendar => const EventCalendarScreen(),
      AppSection.eventWorkspace => const EventListScreen(),
      AppSection.liveDispatch => const DispatchScreen(),
      AppSection.myShift => const MyShiftScreen(),
      AppSection.beoManagement => const BeoScreen(),
      AppSection.premiumSpaces => const PremiumSpacesScreen(),
      AppSection.staffDeployment => const StaffScreen(),
      AppSection.banquetsCulinary => const CulinaryScreen(),
      AppSection.inspections => const InspectionsScreen(),
      AppSection.communications => const CommunicationsScreen(),
      AppSection.closeout => const CloseoutScreen(),
      AppSection.administration => const AdminScreen(),
    };
  }
}
