import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/application/session_controller.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../domain/suite.dart';
import 'suite_map_section.dart';

/// Premium Spaces: suite board for one event. Each card shows state, attendant, and the next step.
class PremiumSpacesScreen extends ConsumerWidget {
  const PremiumSpacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!backendAvailable) {
      return const BackendRequired(title: 'Premium Spaces');
    }

    final session = ref.watch(sessionProvider);
    final permissions = session?.permissions ?? const <AppPermission>{};
    final eventId = ref.watch(selectedEventIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Premium Spaces')),
      floatingActionButton:
          permissions.contains(AppPermission.manageEvents) && eventId != null
          ? FloatingActionButton.extended(
              onPressed: () =>
                  _addSuite(context, ref, session!.venueId, eventId),
              icon: const Icon(Icons.add),
              label: const Text('Add space'),
            )
          : null,
      body: ListView(
        children: [
          const EventPicker(),
          if (eventId != null && session != null)
            SuiteMapSection(venueId: session.venueId, eventId: eventId),
          if (eventId != null)
            _Board(eventId: eventId, permissions: permissions),
        ],
      ),
    );
  }

  Future<void> _addSuite(
    BuildContext context,
    WidgetRef ref,
    String venueId,
    String eventId,
  ) async {
    final suites = await ref.read(venueSuitesProvider(venueId).future);
    final assigned = await ref.read(suitesProvider(eventId).future);
    final assignedIds = assigned.map((suite) => suite.suiteId).toSet();
    final available = suites
        .where((suite) => !assignedIds.contains(suite['id']))
        .toList();
    if (!context.mounted) return;
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            suites.isEmpty
                ? 'No premium spaces are configured for this venue yet. Ask an administrator to add them.'
                : 'All configured spaces are already assigned to this event.',
          ),
        ),
      );
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add a space to the event'),
        children: [
          for (final s in available)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(s['id'] as String),
              child: Text(s['name'] as String),
            ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    await runWrite(context, () async {
      await ref
          .read(planningRepositoryProvider)
          .assignSuite(venueId: venueId, eventId: eventId, suiteId: picked);
      ref.invalidate(suitesProvider(eventId));
    }, success: 'Added to the event.');
  }
}

class _Board extends ConsumerWidget {
  const _Board({required this.eventId, required this.permissions});

  final String eventId;
  final Set<AppPermission> permissions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suites = ref.watch(suitesProvider(eventId));
    return suites.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(error.toString()),
      ),
      data: (items) {
        final summary = suiteSummary(items);
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${summary.ready} of ${summary.total} spaces ready · ${summary.notStarted} not started',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Text(
                  'No spaces assigned to this event yet.',
                  style: TextStyle(color: AppColors.charcoalMuted),
                ),
              for (final suite in items)
                _SuiteCard(
                  suite: suite,
                  canOperate: permissions.contains(AppPermission.updateTasks),
                  canEdit: permissions.contains(AppPermission.deployStaff),
                  onAdvance: () => _advance(context, ref, suite),
                  onEdit: () => _edit(context, ref, suite),
                  onOpenBeo: () => context.push('/beo/event/${suite.eventId}'),
                  onOpenOrder: suite.planArea == null
                      ? null
                      : () => showSuitePanel(
                          context,
                          venueId: ref.read(sessionProvider)!.venueId,
                          eventId: eventId,
                          areaId: suite.planArea!,
                        ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _advance(
    BuildContext context,
    WidgetRef ref,
    SuiteAssignment suite,
  ) async {
    final next = suite.state.next;
    if (next == null) return;
    await runWrite(context, () async {
      await ref
          .read(planningRepositoryProvider)
          .setSuiteState(suite.id, next, suite.version);
      ref.invalidate(suitesProvider(eventId));
    });
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    SuiteAssignment suite,
  ) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _SuiteDetailsDialog(suite: suite),
    );
    if (result == null || !context.mounted) return;
    await runWrite(context, () async {
      await ref
          .read(planningRepositoryProvider)
          .updateSuiteDetails(
            suite.id,
            attendantName: result['attendant']!,
            runnerName: result['runner']!,
            guestContact: result['guest']!,
            dietaryNotes: result['dietary']!,
            specialInstructions: result['instructions']!,
          );
      ref.invalidate(suitesProvider(eventId));
    }, success: 'Suite details saved.');
  }
}

class _SuiteCard extends StatelessWidget {
  const _SuiteCard({
    required this.suite,
    required this.canOperate,
    required this.canEdit,
    required this.onAdvance,
    required this.onEdit,
    required this.onOpenBeo,
    this.onOpenOrder,
  });

  final SuiteAssignment suite;
  final bool canOperate;
  final bool canEdit;
  final VoidCallback onAdvance;
  final VoidCallback onEdit;
  final VoidCallback onOpenBeo;
  final VoidCallback? onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final next = suite.state.next;
    final color = suiteStateColor(suite.state);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenBeo,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      suite.suiteName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  StatusChip(label: suite.state.label, color: color),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (suite.location.isNotEmpty) suite.location,
                  if (suite.serviceZone.isNotEmpty) 'Zone ${suite.serviceZone}',
                  'Attendant: ${suite.attendantName.isEmpty ? 'unassigned' : suite.attendantName}',
                ].join(' · '),
                style: const TextStyle(
                  color: AppColors.charcoalMuted,
                  fontSize: 13,
                ),
              ),
              if (suite.dietaryNotes.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Dietary: ${suite.dietaryNotes}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (next != null && canOperate)
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: onAdvance,
                        child: Text('Mark ${next.label.toLowerCase()}'),
                      ),
                    )
                  else
                    const Expanded(child: SizedBox.shrink()),
                  if (onOpenOrder != null)
                    IconButton(
                      tooltip: 'Suite order',
                      onPressed: onOpenOrder,
                      icon: const Icon(Icons.room_service_outlined),
                    ),
                  if (canEdit)
                    IconButton(
                      tooltip: 'Edit details',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'Open this event’s BEO',
                style: TextStyle(color: AppColors.brass, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuiteDetailsDialog extends StatefulWidget {
  const _SuiteDetailsDialog({required this.suite});

  final SuiteAssignment suite;

  @override
  State<_SuiteDetailsDialog> createState() => _SuiteDetailsDialogState();
}

class _SuiteDetailsDialogState extends State<_SuiteDetailsDialog> {
  late final _attendant = TextEditingController(
    text: widget.suite.attendantName,
  );
  late final _runner = TextEditingController(text: widget.suite.runnerName);
  late final _guest = TextEditingController(text: widget.suite.guestContact);
  late final _dietary = TextEditingController(text: widget.suite.dietaryNotes);
  late final _instructions = TextEditingController(
    text: widget.suite.specialInstructions,
  );

  @override
  void dispose() {
    for (final c in [_attendant, _runner, _guest, _dietary, _instructions]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.suite.suiteName} details'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _attendant,
              decoration: const InputDecoration(labelText: 'Attendant'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _runner,
              decoration: const InputDecoration(labelText: 'Runner'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _guest,
              decoration: const InputDecoration(
                labelText: 'Guest or account contact',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _dietary,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Dietary notes'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _instructions,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Special instructions',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            'attendant': _attendant.text.trim(),
            'runner': _runner.text.trim(),
            'guest': _guest.text.trim(),
            'dietary': _dietary.text.trim(),
            'instructions': _instructions.text.trim(),
          }),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
