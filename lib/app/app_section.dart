import 'package:flutter/material.dart';

import '../core/icons/phosphor.dart';

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
import '../features/sales/presentation/sales_screen.dart';
import '../features/dispatch/presentation/my_shift_screen.dart';
import '../features/events/presentation/event_calendar_screen.dart';
import '../features/events/presentation/event_list_screen.dart';
import '../features/floor_plan/presentation/floor_plan_studio_screen.dart';
import '../features/chat/presentation/chat_screen.dart';
import '../features/meeting_notes/presentation/meeting_notes_screen.dart';
import '../features/staff/presentation/staff_management_screen.dart';

/// Primary navigation sections. Routes and nav items are both derived from this list.
/// A null [permission] means any signed-in user may open the section.
enum AppSection {
  commandCenter(
    path: '/command',
    label: 'Command Center',
    icon: PhosphorIconsDuotone.squaresFour,
    permission: AppPermission.viewOperations,
    phase: 1,
  ),
  eventCalendar(
    path: '/calendar',
    label: 'Event Calendar',
    icon: PhosphorIconsDuotone.calendarBlank,
    permission: AppPermission.viewOperations,
    phase: 1,
  ),
  eventWorkspace(
    path: '/events',
    label: 'Event Workspace',
    icon: PhosphorIconsDuotone.calendarCheck,
    permission: AppPermission.viewOperations,
    phase: 1,
  ),
  beoManagement(
    path: '/beo',
    label: 'BEO Management',
    icon: PhosphorIconsDuotone.fileText,
    permission: AppPermission.viewOperations,
    phase: 2,
  ),
  premiumSpaces(
    path: '/spaces',
    label: 'Premium Spaces',
    icon: PhosphorIconsDuotone.door,
    permission: AppPermission.viewOperations,
    phase: 2,
  ),
  sales(
    path: '/sales',
    label: 'Sales',
    icon: PhosphorIconsDuotone.tag,
    permission: AppPermission.viewOperations,
    phase: 4,
  ),
  banquetsCulinary(
    path: '/culinary',
    label: 'Banquets & Culinary',
    icon: PhosphorIconsDuotone.forkKnife,
    permission: AppPermission.viewCulinary,
    phase: 3,
  ),
  staffDeployment(
    path: '/staff',
    label: 'Staff Deployment',
    icon: PhosphorIconsDuotone.usersThree,
    permission: AppPermission.viewDeployment,
    phase: 2,
  ),
  liveDispatch(
    path: '/dispatch',
    label: 'Live Service Dispatch',
    icon: PhosphorIconsDuotone.lightning,
    permission: AppPermission.manageRequests,
    phase: 2,
  ),
  myShift(
    path: '/my-shift',
    label: 'My Shift',
    icon: PhosphorIconsDuotone.identificationBadge,
    permission: null,
    phase: 2,
  ),
  inspections(
    path: '/inspections',
    label: 'Inspections & Checklists',
    icon: PhosphorIconsDuotone.listChecks,
    permission: AppPermission.runInspections,
    phase: 3,
  ),
  communications(
    path: '/communications',
    label: 'Communications',
    icon: PhosphorIconsDuotone.megaphone,
    permission: null,
    phase: 3,
  ),
  chat(
    path: '/chat',
    label: 'Chat',
    icon: PhosphorIconsDuotone.chatCircleText,
    permission: null,
    phase: 3,
  ),
  closeout(
    path: '/closeout',
    label: 'Event Closeout & Reports',
    icon: PhosphorIconsDuotone.clipboardText,
    permission: AppPermission.viewReports,
    phase: 3,
  ),
  meetingNotes(
    path: '/meeting-notes',
    label: 'Meeting Notes',
    icon: PhosphorIconsDuotone.notePencil,
    // Administrators only. The assistant re-checks this server-side.
    permission: AppPermission.manageConfiguration,
    phase: 4,
  ),
  administration(
    path: '/admin',
    label: 'Administration & Configuration',
    icon: PhosphorIconsDuotone.gear,
    permission: AppPermission.manageConfiguration,
    phase: 4,
  ),
  staffManagement(
    path: '/staff',
    label: 'Staff Management',
    icon: PhosphorIconsDuotone.userList,
    permission: AppPermission.manageConfiguration,
    phase: 4,
  ),
  floorPlanStudio(
    path: '/floor-plan',
    label: 'Floor Plan Studio',
    icon: PhosphorIconsDuotone.cube,
    // Anyone with operations access may view plans. Only administrators can edit them,
    // which the studio enforces with its manage_configuration check.
    permission: AppPermission.viewOperations,
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
  final PhosphorIconData icon;
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
      AppSection.sales => const SalesScreen(),
      AppSection.staffDeployment => const StaffScreen(),
      AppSection.banquetsCulinary => const CulinaryScreen(),
      AppSection.inspections => const InspectionsScreen(),
      AppSection.communications => const CommunicationsScreen(),
      AppSection.chat => const ChatScreen(),
      AppSection.staffManagement => const StaffManagementScreen(),
      AppSection.closeout => const CloseoutScreen(),
      AppSection.meetingNotes => const MeetingNotesScreen(),
      AppSection.administration => const AdminScreen(),
      AppSection.floorPlanStudio => const FloorPlanStudioScreen(),
    };
  }
}
