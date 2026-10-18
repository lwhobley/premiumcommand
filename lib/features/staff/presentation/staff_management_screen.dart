import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/icons/phosphor.dart';
import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../../core/widgets/tag.dart';
import '../../auth/application/session_controller.dart';
import '../../events/domain/readiness.dart';
import '../application/staff_providers.dart';
import '../domain/staff_profile.dart';
import 'staff_form_dialog.dart';

/// Staff matching the search text, department, and status. Null filters match everything.
List<StaffProfile> filterStaffProfiles(
  List<StaffProfile> staff, {
  String query = '',
  Department? department,
  StaffStatus? status,
}) {
  return [
    for (final profile in staff)
      if (matchesStaffSearch(profile, query) &&
          (department == null || profile.department == department) &&
          (status == null || profile.status == status))
        profile,
  ];
}

/// Administrators add, find, and open staff. Everyone else is redirected away from this page.
class StaffManagementScreen extends ConsumerStatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  ConsumerState<StaffManagementScreen> createState() =>
      _StaffManagementScreenState();
}

class _StaffManagementScreenState extends ConsumerState<StaffManagementScreen> {
  final _search = TextEditingController();
  Department? _department;
  StaffStatus? _status;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final canManage = session?.can(AppPermission.manageConfiguration) ?? false;
    if (session == null || !canManage) {
      return const PageScaffold(
        kicker: 'Administration',
        title: 'Staff accounts',
        children: [EmptyNote('Only administrators can manage staff.')],
      );
    }
    final staff = ref.watch(staffListProvider(session.venueId));

    return PageScaffold(
      kicker: 'Administration',
      title: 'Staff accounts',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(session.venueId),
        icon: const PhosphorIcon(PhosphorIconsDuotone.userPlus),
        label: const Text('Add staff'),
      ),
      children: staff.when(
        loading: () => const [LinearProgressIndicator()],
        error: (error, _) => [
          _Message(
            icon: PhosphorIconsDuotone.warningCircle,
            text: userMessageFor(error),
            action: TextButton(
              onPressed: () =>
                  ref.invalidate(staffListProvider(session.venueId)),
              child: const Text('Try again'),
            ),
          ),
        ],
        data: (all) {
          final shown = filterStaffProfiles(
            all,
            query: _search.text,
            department: _department,
            status: _status,
          );
          return [
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Search by name or employee ID',
                prefixIcon: PhosphorIcon(PhosphorIconsDuotone.magnifyingGlass),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<Department?>(
                    initialValue: _department,
                    decoration: const InputDecoration(labelText: 'Department'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All departments'),
                      ),
                      for (final d in Department.values)
                        DropdownMenuItem(value: d, child: Text(d.label)),
                    ],
                    onChanged: (value) => setState(() => _department = value),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<StaffStatus?>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All statuses'),
                      ),
                      for (final s in StaffStatus.values)
                        DropdownMenuItem(value: s, child: Text(s.label)),
                    ],
                    onChanged: (value) => setState(() => _status = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.l),
            if (all.isEmpty)
              const _Message(
                icon: PhosphorIconsDuotone.usersThree,
                text: 'No staff accounts yet. Add the first staff member.',
              )
            else if (shown.isEmpty)
              const _Message(
                icon: PhosphorIconsDuotone.magnifyingGlass,
                text: 'No staff match these filters.',
              )
            else
              for (final profile in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: OpenRow(
                    leading: CircleAvatar(child: Text(profile.initials)),
                    title: profile.fullName,
                    meta:
                        '${profile.employeeId} · ${profile.department.label}'
                        '${profile.jobTitle.isEmpty ? '' : ' · ${profile.jobTitle}'}',
                    trailing: Tag(
                      profile.status.label,
                      profile.isActive ? Tone.accent : Tone.neutral,
                    ),
                    onTap: () => context.push('/staff/${profile.id}'),
                  ),
                ),
          ];
        },
      ),
    );
  }

  Future<void> _add(String venueId) async {
    final value = await showStaffFormDialog(context);
    if (value == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final name = value.fields['full_name'] as String;
      await ref
          .read(staffRepositoryProvider)
          .create(
            venueId: venueId,
            fields: value.fields,
            roles: value.roles,
            pin: value.pin!,
          );
      ref.invalidate(staffListProvider(venueId));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('$name added'),
          content: Text(
            'Give this PIN to the staff member. It is shown only once.\n\n'
            'PIN: ${value.pin}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(userMessageFor(error))));
    }
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PhosphorIcon(icon, size: 40, color: AppColors.text),
          const SizedBox(height: 12),
          Text(text, style: AppText.body),
          ?action,
        ],
      ),
    );
  }
}
