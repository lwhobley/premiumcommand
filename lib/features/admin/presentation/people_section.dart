import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_chip.dart';
import '../../events/domain/readiness.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../data/people_repository.dart';

/// Lists everyone with venue access, with role, department, and suspension controls.
class PeopleSection extends ConsumerWidget {
  const PeopleSection({super.key, required this.venueId, required this.currentUserId});

  final String venueId;
  final String currentUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(peopleProvider(venueId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text('People and access', style: Theme.of(context).textTheme.titleMedium)),
          TextButton.icon(
            onPressed: () => _addPerson(context, ref),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add by email'),
          ),
        ]),
        const SizedBox(height: 4),
        const Text(
          'Accounts are created in Supabase Auth. Add them here by email, then set their roles and departments.',
          style: TextStyle(color: AppColors.charcoalMuted, fontSize: 13),
        ),
        const SizedBox(height: 8),
        people.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('$error'),
          data: (list) {
            if (list.isEmpty) return const Text('No one has access yet.');
            return Column(
              children: [
                for (final p in list)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ExpansionTile(
                      title: Text(p.name.isEmpty ? p.email : p.name),
                      subtitle: Text([
                        p.email,
                        if (p.roles.isNotEmpty) p.roles.map((r) => r.label).join(', ') else 'No role',
                      ].join(' · ')),
                      trailing: StatusChip(
                        label: p.active ? 'Active' : 'Suspended',
                        color: p.active ? AppColors.ready : AppColors.neutral,
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Roles', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final role in AppRole.values)
                            FilterChip(
                              label: Text(role.label),
                              selected: p.roles.contains(role),
                              onSelected: (on) => _run(context, ref, () => ref
                                  .read(peopleRepositoryProvider)
                                  .setRole(venueId, p.userId, role, on)),
                            ),
                        ]),
                        const SizedBox(height: 12),
                        const Text('Departments', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final dept in Department.values)
                            FilterChip(
                              label: Text(dept.label),
                              selected: p.departments.contains(dept),
                              onSelected: (on) => _run(context, ref, () => ref
                                  .read(peopleRepositoryProvider)
                                  .setDepartment(venueId, p.userId, dept, on)),
                            ),
                        ]),
                        const SizedBox(height: 12),
                        if (p.userId != currentUserId)
                          OutlinedButton(
                            onPressed: () => _run(context, ref, () => ref
                                .read(peopleRepositoryProvider)
                                .setActive(venueId, p.userId, !p.active)),
                            child: Text(p.active ? 'Suspend access' : 'Restore access'),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    await runWrite(context, () async {
      await action();
      ref.invalidate(peopleProvider(venueId));
    });
  }

  Future<void> _addPerson(BuildContext context, WidgetRef ref) async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) => const _EmailDialog(),
    );
    if (email == null || email.isEmpty || !context.mounted) return;
    await runWrite(context, () async {
      await ref.read(peopleRepositoryProvider).addByEmail(venueId, email);
      ref.invalidate(peopleProvider(venueId));
    }, success: 'Added. Now set their roles and departments.');
  }
}

class _EmailDialog extends StatefulWidget {
  const _EmailDialog();

  @override
  State<_EmailDialog> createState() => _EmailDialogState();
}

class _EmailDialogState extends State<_EmailDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add person'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Email of an existing account'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _controller.text.trim()), child: const Text('Add')),
      ],
    );
  }
}
