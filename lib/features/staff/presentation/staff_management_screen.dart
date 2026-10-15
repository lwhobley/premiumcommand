import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_chip.dart';
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
      return const Scaffold(
        body: Center(child: Text('Only administrators can manage staff.')),
      );
    }
    final staff = ref.watch(staffListProvider(session.venueId));

    return Scaffold(
      appBar: AppBar(title: const Text('Staff accounts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(session.venueId),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add staff'),
      ),
      body: staff.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Message(
          icon: Icons.error_outline,
          text: userMessageFor(error),
          action: TextButton(
            onPressed: () => ref.invalidate(staffListProvider(session.venueId)),
            child: const Text('Try again'),
          ),
        ),
        data: (all) {
          final shown = filterStaffProfiles(
            all,
            query: _search.text,
            department: _department,
            status: _status,
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Search by name or employee ID',
                  prefixIcon: Icon(Icons.search),
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
                      decoration: const InputDecoration(
                        labelText: 'Department',
                      ),
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
              const SizedBox(height: 16),
              if (all.isEmpty)
                const _Message(
                  icon: Icons.groups_outlined,
                  text: 'No staff accounts yet. Add the first staff member.',
                )
              else if (shown.isEmpty)
                const _Message(
                  icon: Icons.search_off,
                  text: 'No staff match these filters.',
                )
              else
                for (final profile in shown)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(child: Text(profile.initials)),
                      title: Text(profile.fullName),
                      subtitle: Text(
                        '${profile.employeeId} · ${profile.department.label}'
                        '${profile.jobTitle.isEmpty ? '' : ' · ${profile.jobTitle}'}',
                      ),
                      trailing: StatusChip(
                        label: profile.status.label,
                        color: profile.isActive
                            ? AppColors.ready
                            : AppColors.neutral,
                      ),
                      onTap: () => context.push('/staff/${profile.id}'),
                    ),
                  ),
            ],
          );
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
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.charcoalMuted),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          ?action,
        ],
      ),
    );
  }
}
