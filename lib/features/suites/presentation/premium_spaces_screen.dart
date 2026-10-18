import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/icons/phosphor.dart';

import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../../core/widgets/tag.dart';
import '../../auth/application/session_controller.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../domain/premium_level_layout.dart';
import '../domain/suite.dart';
import 'suite_map_section.dart';

/// Premium Spaces: suite board for one event. Suites are tiles filled by state; clubs and
/// the floor are listed below. Tapping a space opens its state, attendant, and next step.
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

    return PageScaffold(
      kicker: 'Operations',
      title: 'Premium Spaces',
      floatingActionButton:
          permissions.contains(AppPermission.manageEvents) && eventId != null
          ? FloatingActionButton.extended(
              onPressed: () =>
                  _addSuite(context, ref, session!.venueId, eventId),
              icon: const PhosphorIcon(PhosphorIconsDuotone.plus),
              label: const Text('Add space'),
            )
          : null,
      children: [
        const EventPicker(),
        if (eventId != null && session != null)
          SuiteMapSection(venueId: session.venueId, eventId: eventId),
        if (eventId != null) _Board(eventId: eventId, permissions: permissions),
      ],
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

/// Tile label color with at least 4 to 1 contrast on [suiteStateColor]: paper on the
/// dark accent700 fill, ink on every other fill.
Color _tileTextColor(SuiteState state) =>
    state == SuiteState.inService ? AppColors.background : AppColors.text;

/// True for a club, the arena floor, or the concourse: spaces listed rather than tiled.
bool _isClubOrFloor(SuiteAssignment suite) {
  final area = suite.planArea;
  return area != null &&
      (isClubArea(area) || area == arenaFloorArea || area == concourseArea);
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
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Align(
          alignment: Alignment.centerLeft,
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(error.toString(), style: AppText.body),
      ),
      data: (items) {
        final summary = suiteSummary(items);
        final tiles = items.where((s) => !_isClubOrFloor(s)).toList();
        final listed = items.where(_isClubOrFloor).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeading('Suites'),
            Text(
              '${summary.ready} of ${summary.total} spaces ready · ${summary.notStarted} not started',
              style: AppText.body.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const EmptyNote('No spaces assigned to this event yet.'),
            if (tiles.isNotEmpty) ...[
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisExtent: 56,
                  mainAxisSpacing: AppSpace.xs,
                  crossAxisSpacing: AppSpace.xs,
                ),
                itemCount: tiles.length,
                itemBuilder: (context, index) => _SuiteTile(
                  suite: tiles[index],
                  onTap: () => _openDetail(context, ref, tiles[index]),
                ),
              ),
              const SizedBox(height: AppSpace.m),
              const _Legend(),
            ],
            if (listed.isNotEmpty) ...[
              const SectionHeading('Clubs and floor'),
              for (final space in listed)
                OpenRow(
                  title: space.suiteName,
                  trailing: Tag(space.state.label, suiteStateTone(space.state)),
                  meta: _metaLine(space),
                  onTap: () => _openDetail(context, ref, space),
                ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _openDetail(
    BuildContext context,
    WidgetRef ref,
    SuiteAssignment suite,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SuiteSheet(
      eventId: eventId,
      assignmentId: suite.id,
      canOperate: permissions.contains(AppPermission.updateTasks),
      canEdit: permissions.contains(AppPermission.deployStaff),
      onAdvance: (current) => _advance(context, ref, current),
      onEdit: (current) => _edit(context, ref, current),
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
  );

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

String _metaLine(SuiteAssignment suite) => [
  if (suite.location.isNotEmpty) suite.location,
  if (suite.serviceZone.isNotEmpty) 'Zone ${suite.serviceZone}',
  'Attendant: ${suite.attendantName.isEmpty ? 'unassigned' : suite.attendantName}',
].join(' · ');

/// One suite: a 56-high tile filled by its state, labeled with its short name.
class _SuiteTile extends StatelessWidget {
  const _SuiteTile({required this.suite, required this.onTap});

  final SuiteAssignment suite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${suite.suiteName}, ${suite.state.label}',
      excludeSemantics: true,
      child: Tooltip(
        message: '${suite.suiteName} · ${suite.state.label}',
        child: Material(
          color: suiteStateColor(suite.state),
          borderRadius: AppRadius.all,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.all,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  mapLabel(suite.suiteName),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  // 19 w600 is large text, which keeps the label legible on every fill.
                  style: AppText.rowTitle.copyWith(
                    fontSize: 19,
                    color: _tileTextColor(suite.state),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A swatch and label for each suite state.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpace.m,
      runSpacing: 6,
      children: [
        for (final state in SuiteState.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: suiteStateColor(state),
                  borderRadius: AppRadius.all,
                ),
              ),
              const SizedBox(width: 6),
              Text(state.label, style: AppText.meta),
            ],
          ),
      ],
    );
  }
}

/// A space's detail sheet: state, attendant, runner, dietary notes, the next-state
/// button, and links to the suite order and the event BEO.
class _SuiteSheet extends ConsumerWidget {
  const _SuiteSheet({
    required this.eventId,
    required this.assignmentId,
    required this.canOperate,
    required this.canEdit,
    required this.onAdvance,
    required this.onEdit,
    required this.onOpenBeo,
    this.onOpenOrder,
  });

  final String eventId;
  final String assignmentId;
  final bool canOperate;
  final bool canEdit;
  final ValueChanged<SuiteAssignment> onAdvance;
  final ValueChanged<SuiteAssignment> onEdit;
  final VoidCallback onOpenBeo;
  final VoidCallback? onOpenOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suite = (ref.watch(suitesProvider(eventId)).value ?? const [])
        .where((s) => s.id == assignmentId)
        .firstOrNull;
    if (suite == null) return const SizedBox.shrink();
    final next = suite.state.next;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.screen,
          0,
          AppSpace.screen,
          AppSpace.screen,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(suite.suiteName, style: AppText.sectionHeading),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Tag(suite.state.label, suiteStateTone(suite.state)),
                ),
              ],
            ),
            if (suite.location.isNotEmpty || suite.serviceZone.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                [
                  if (suite.location.isNotEmpty) suite.location,
                  if (suite.serviceZone.isNotEmpty) 'Zone ${suite.serviceZone}',
                ].join(' · '),
                style: AppText.meta,
              ),
            ],
            const SizedBox(height: AppSpace.l),
            FactGrid(
              facts: [
                (
                  'Attendant',
                  suite.attendantName.isEmpty
                      ? 'unassigned'
                      : suite.attendantName,
                ),
                (
                  'Runner',
                  suite.runnerName.isEmpty ? 'unassigned' : suite.runnerName,
                ),
              ],
            ),
            if (suite.dietaryNotes.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Dietary: ${suite.dietaryNotes}', style: AppText.body),
            ],
            const SizedBox(height: AppSpace.l),
            if (next != null && canOperate) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => onAdvance(suite),
                  child: Text('Mark ${next.label.toLowerCase()}'),
                ),
              ),
              const SizedBox(height: AppSpace.s),
            ],
            Wrap(
              spacing: AppSpace.s,
              runSpacing: AppSpace.s,
              children: [
                if (onOpenOrder != null)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onOpenOrder!();
                    },
                    icon: const PhosphorIcon(
                      PhosphorIconsDuotone.bellSimpleRinging,
                    ),
                    label: const Text('Suite order'),
                  ),
                if (canEdit)
                  OutlinedButton.icon(
                    onPressed: () => onEdit(suite),
                    icon: const PhosphorIcon(PhosphorIconsDuotone.pencilSimple),
                    label: const Text('Edit details'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.s),
            Transform.translate(
              offset: const Offset(-10, 0),
              child: TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onOpenBeo();
                },
                icon: const PhosphorIcon(PhosphorIconsDuotone.fileText),
                label: const Text('Open this event’s BEO'),
              ),
            ),
          ],
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
