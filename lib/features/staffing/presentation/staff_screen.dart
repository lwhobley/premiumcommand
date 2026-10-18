import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/icons/phosphor.dart';
import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/venue_time.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../../core/widgets/tag.dart';
import '../../auth/application/session_controller.dart';
import '../../events/domain/readiness.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../domain/staffing.dart';
import 'staff_deployment_widgets.dart';

/// Staff Deployment: roster, uncovered positions, CSV import, and event briefings.
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!backendAvailable) {
      return const BackendRequired(title: 'Staff Deployment');
    }

    final session = ref.watch(sessionProvider);
    final permissions = session?.permissions ?? const <AppPermission>{};
    final eventId = ref.watch(selectedEventIdProvider);
    final canDeploy = permissions.contains(AppPermission.deployStaff);

    return PageScaffold(
      kicker: 'Operations',
      title: 'Staff Deployment',
      floatingActionButton: canDeploy && eventId != null
          ? FloatingActionButton.extended(
              onPressed: () =>
                  _addPosition(context, ref, session!.venueId, eventId),
              icon: const PhosphorIcon(PhosphorIconsDuotone.userPlus),
              label: const Text('Add position'),
            )
          : null,
      children: [
        const EventPicker(),
        if (session != null)
          StaffDirectoryPanel(
            venueId: session.venueId,
            eventId: eventId,
            canManage: canDeploy,
          ),
        if (eventId != null) ...[
          _Roster(
            eventId: eventId,
            canDeploy: canDeploy,
            venueId: session?.venueId ?? '',
          ),
          _Briefings(
            eventId: eventId,
            canPublish: canDeploy,
            venueId: session?.venueId ?? '',
          ),
        ],
      ],
    );
  }

  Future<void> _addPosition(
    BuildContext context,
    WidgetRef ref,
    String venueId,
    String eventId,
  ) async {
    final draft = await showDialog<_PositionDraft>(
      context: context,
      builder: (_) => const _PositionDialog(),
    );
    if (draft == null || !context.mounted) return;
    await runWrite(
      context,
      () async {
        await ref
            .read(planningRepositoryProvider)
            .addStaff(
              venueId: venueId,
              eventId: eventId,
              displayName: draft.name,
              roleLabel: draft.role,
              department: draft.department,
              zone: draft.zone,
              station: draft.station,
            );
        ref.invalidate(staffProvider(eventId));
      },
      success: draft.name.isEmpty
          ? 'Position added (uncovered).'
          : 'Position added.',
    );
  }
}

class _Roster extends ConsumerWidget {
  const _Roster({
    required this.eventId,
    required this.canDeploy,
    required this.venueId,
  });

  final String eventId;
  final bool canDeploy;
  final String venueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(staffProvider(eventId));
    return staff.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: AppSpace.section),
        child: LinearProgressIndicator(),
      ),
      error: (error, _) => Text('$error'),
      data: (items) {
        final uncovered = items.where((s) => !s.isCovered).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeading(
              '${items.length - uncovered.length} of ${items.length} positions covered',
              trailing: canDeploy
                  ? TextButton.icon(
                      onPressed: () => _importCsv(context, ref),
                      icon: const PhosphorIcon(
                        PhosphorIconsDuotone.fileArrowUp,
                      ),
                      label: const Text('Import CSV'),
                    )
                  : null,
            ),
            if (uncovered.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${uncovered.length} uncovered position(s) need a person.',
                  style: AppText.body.copyWith(
                    color: AppColors.accent2700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            for (final s in items)
              _PositionRow(
                position: s,
                canDeploy: canDeploy,
                onTap: () => _assign(context, ref, s),
              ),
          ],
        );
      },
    );
  }

  Future<void> _assign(
    BuildContext context,
    WidgetRef ref,
    StaffPosition position,
  ) async {
    // Linking to a real account is what lets the person see this assignment and get notified.
    final members = await ref.read(venueMembersProvider(venueId).future);
    if (!context.mounted) return;
    final premiumSpaces = await ref.read(suitesProvider(eventId).future);
    if (!context.mounted) return;
    final choice = await showDialog<({String name, String? userId})>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Assign person'),
        children: [
          for (final m in members)
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(dialogContext, (name: m.name, userId: m.id)),
              child: Text(m.name),
            ),
          SimpleDialogOption(
            onPressed: () async {
              final typed = await showDialog<String>(
                context: dialogContext,
                builder: (_) => _NameDialog(initial: position.displayName),
              );
              if (typed != null && dialogContext.mounted) {
                Navigator.pop(dialogContext, (name: typed, userId: null));
              }
            },
            child: const Text('Type a name (no account)…'),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(dialogContext, (name: '', userId: null)),
            child: const Text('Leave uncovered'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    // Where the person works matters as much as who: a premium space, or any other area.
    final place = choice.name.isEmpty
        ? const PlaceChoice()
        : await showPlaceDialog(context, premiumSpaces: premiumSpaces);
    if (place == null || !context.mounted) return;
    await runWrite(
      context,
      () async {
        await ref
            .read(planningRepositoryProvider)
            .reassignStaff(
              position.id,
              displayName: choice.name,
              userId: choice.userId,
              suiteAssignmentId: place.suiteAssignmentId,
              department: place.department,
              zone: place.zone,
              station: place.station,
            );
        ref.invalidate(staffProvider(eventId));
      },
      success: choice.name.isEmpty
          ? 'Position is now uncovered.'
          : 'Assigned to ${choice.name}.',
    );
  }

  Future<void> _importCsv(BuildContext context, WidgetRef ref) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _CsvDialog(),
    );
    if (text == null || !context.mounted) return;
    final parsed = parseRosterCsv(text);
    if (parsed.errors.isNotEmpty && parsed.rows.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(parsed.errors.first)));
      return;
    }
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Import ${parsed.rows.length} rows?'),
        content: Text(
          parsed.errors.isEmpty
              ? 'Every row is valid.'
              : '${parsed.errors.length} row(s) will be skipped:\n${parsed.errors.take(6).join('\n')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;
    await runWrite(context, () async {
      await ref
          .read(planningRepositoryProvider)
          .importRoster(venueId: venueId, eventId: eventId, rows: parsed.rows);
      ref.invalidate(staffProvider(eventId));
    }, success: 'Imported ${parsed.rows.length} rows.');
  }
}

class _Briefings extends ConsumerWidget {
  const _Briefings({
    required this.eventId,
    required this.canPublish,
    required this.venueId,
  });

  final String eventId;
  final bool canPublish;
  final String venueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final briefings = ref.watch(briefingsProvider(eventId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'Briefings',
          trailing: canPublish
              ? TextButton.icon(
                  onPressed: () => _publish(context, ref),
                  icon: const PhosphorIcon(PhosphorIconsDuotone.megaphone),
                  label: const Text('Publish'),
                )
              : null,
        ),
        briefings.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('$error'),
          data: (items) {
            if (items.isEmpty) {
              return const EmptyNote('No briefings for this event yet.');
            }
            return Column(
              children: [
                for (final b in items)
                  OpenRow(
                    title: b.title,
                    below: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.body, style: AppText.body),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MMM d, h:mm a').format(
                            atVenue(
                              b.createdAt,
                              ref.watch(sessionProvider)?.timeZone ?? 'UTC',
                            ),
                          ),
                          style: AppText.meta,
                        ),
                        const SizedBox(height: 8),
                        if (b.acknowledgedByMe)
                          const Row(
                            children: [
                              PhosphorIcon(
                                PhosphorIconsDuotone.check,
                                size: 18,
                                color: AppColors.accent700,
                              ),
                              SizedBox(width: 6),
                              Text('You acknowledged this briefing'),
                            ],
                          )
                        else
                          FilledButton(
                            onPressed: () => runWrite(context, () async {
                              await ref
                                  .read(planningRepositoryProvider)
                                  .acknowledgeBriefing(
                                    venueId: venueId,
                                    briefingId: b.id,
                                  );
                              ref.invalidate(briefingsProvider(eventId));
                            }, success: 'Acknowledged.'),
                            child: const Text('Acknowledge'),
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

  Future<void> _publish(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _BriefingDialog(),
    );
    if (draft == null || !context.mounted) return;
    await runWrite(context, () async {
      await ref
          .read(planningRepositoryProvider)
          .createBriefing(
            venueId: venueId,
            eventId: eventId,
            title: draft.$1,
            body: draft.$2,
          );
      ref.invalidate(briefingsProvider(eventId));
    }, success: 'Briefing published.');
  }
}

/// A roster position as an open row. Uncovered positions read in the alert color with a tag.
class _PositionRow extends StatelessWidget {
  const _PositionRow({
    required this.position,
    required this.canDeploy,
    required this.onTap,
  });

  final StaffPosition position;
  final bool canDeploy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = position;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSpace.minTap),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.row / 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: PhosphorIcon(
                s.isCovered
                    ? PhosphorIconsDuotone.checkCircle
                    : PhosphorIconsDuotone.warningCircle,
                color: s.isCovered ? AppColors.accent700 : AppColors.text,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.isCovered ? s.displayName : 'Uncovered position',
                    style: AppText.rowTitle.copyWith(
                      color: s.isCovered
                          ? AppColors.text
                          : AppColors.accent2700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (s.roleLabel.isNotEmpty) s.roleLabel,
                      s.department.label,
                      if (s.zone.isNotEmpty) 'Zone ${s.zone}',
                      if (s.station.isNotEmpty) s.station,
                    ].join(' · '),
                    style: AppText.meta,
                  ),
                ],
              ),
            ),
            if (!s.isCovered) ...[
              const SizedBox(width: 12),
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Tag('Uncovered', Tone.alert),
              ),
            ],
            if (canDeploy) ...[
              const SizedBox(width: 12),
              const PhosphorIcon(
                PhosphorIconsDuotone.pencilSimple,
                color: AppColors.accent700,
              ),
            ],
          ],
        ),
      ),
    );
    if (!canDeploy) return content;
    return InkWell(onTap: onTap, borderRadius: AppRadius.all, child: content);
  }
}

class _PositionDraft {
  const _PositionDraft({
    required this.name,
    required this.role,
    required this.department,
    required this.zone,
    required this.station,
  });

  final String name;
  final String role;
  final Department department;
  final String zone;
  final String station;
}

class _PositionDialog extends StatefulWidget {
  const _PositionDialog();

  @override
  State<_PositionDialog> createState() => _PositionDialogState();
}

class _PositionDialogState extends State<_PositionDialog> {
  final _name = TextEditingController();
  final _role = TextEditingController();
  final _zone = TextEditingController();
  final _station = TextEditingController();
  Department _dept = Department.operations;

  @override
  void dispose() {
    for (final c in [_name, _role, _zone, _station]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add position'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Person (leave blank if uncovered)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _role,
              decoration: const InputDecoration(labelText: 'Role'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<Department>(
              initialValue: _dept,
              decoration: const InputDecoration(labelText: 'Department'),
              items: [
                for (final d in Department.values)
                  DropdownMenuItem(value: d, child: Text(d.label)),
              ],
              onChanged: (v) => setState(() => _dept = v ?? _dept),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _zone,
              decoration: const InputDecoration(labelText: 'Zone'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _station,
              decoration: const InputDecoration(labelText: 'Station'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _PositionDraft(
              name: _name.text.trim(),
              role: _role.text.trim(),
              department: _dept,
              zone: _zone.text.trim(),
              station: _station.text.trim(),
            ),
          ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Assign person'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Name (clear to leave uncovered)',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _CsvDialog extends StatefulWidget {
  const _CsvDialog();

  @override
  State<_CsvDialog> createState() => _CsvDialogState();
}

class _CsvDialogState extends State<_CsvDialog> {
  final _text = TextEditingController(
    text: 'name,role,department,zone,station\n',
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import roster CSV'),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: _text,
          minLines: 6,
          maxLines: 12,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            helperText: 'Header: name,role,department,zone,station. Department codes: suites, banquets, culinary, beverage, lounge, operations.',
            helperMaxLines: 3,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _text.text),
          child: const Text('Review'),
        ),
      ],
    );
  }
}

class _BriefingDialog extends StatefulWidget {
  const _BriefingDialog();

  @override
  State<_BriefingDialog> createState() => _BriefingDialogState();
}

class _BriefingDialogState extends State<_BriefingDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Publish briefing'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _body,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Briefing'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) return;
            Navigator.pop(context, (_title.text.trim(), _body.text.trim()));
          },
          child: const Text('Publish'),
        ),
      ],
    );
  }
}
