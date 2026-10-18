import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/icons/phosphor.dart';

import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../auth/application/session_controller.dart';
import '../../dispatch/application/dispatch_providers.dart';
import '../../dispatch/domain/service_request.dart';
import '../../operations/application/operations_providers.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../../suites/domain/premium_level_layout.dart';
import 'banquet_areas_section.dart';
import 'people_section.dart';

/// Administration: venue details, suite configuration, and the checklist library.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final permissions = session?.permissions ?? const <AppPermission>{};
    final canConfigure = permissions.contains(
      AppPermission.manageConfiguration,
    );

    return PageScaffold(
      kicker: 'Administration',
      title: 'Administration & Configuration',
      floatingActionButton: canConfigure && backendAvailable && session != null
          ? FloatingActionButton.extended(
              onPressed: () => _addSuite(context, ref, session.venueId),
              icon: const PhosphorIcon(PhosphorIconsDuotone.plus),
              label: const Text('Add space'),
            )
          : null,
      children: [
        const SectionHeading('Venue', first: true),
        OpenRow(
          title: session?.venueName ?? '—',
          meta: 'Time zone: ${session?.timeZone ?? '—'}',
        ),
        if (canConfigure && backendAvailable) ...[
          const SizedBox(height: 12),
          OpenRow(
            leading: const PhosphorIcon(
              PhosphorIconsDuotone.identificationBadge,
              color: AppColors.accent700,
            ),
            title: 'Staff accounts',
            meta: 'Add staff, reset PINs, deactivate or remove accounts',
            trailing: const PhosphorIcon(PhosphorIconsDuotone.caretRight),
            onTap: () => context.push('/staff'),
          ),
        ],
        if (backendAvailable && session != null)
          BanquetAreasSection(
            venueId: session.venueId,
            canConfigure: canConfigure,
            canManageEvents: permissions.contains(AppPermission.manageEvents),
          ),
        const SectionHeading('Suites'),
        if (!backendAvailable)
          const EmptyNote('Connect a backend to manage suites.')
        else if (session == null)
          const SizedBox.shrink()
        else ...[
          _ServiceSuiteCountCard(
            venueId: session.venueId,
            canConfigure: canConfigure,
          ),
          const SizedBox(height: 12),
          _SuiteList(venueId: session.venueId, canConfigure: canConfigure),
        ],
        if (backendAvailable && session != null && canConfigure)
          PeopleSection(
            venueId: session.venueId,
            currentUserId: session.userId,
          ),
        const SectionHeading('Escalation limits'),
        if (!backendAvailable)
          const EmptyNote('Connect a backend to change escalation limits.')
        else if (session != null && canConfigure)
          _EscalationEditor(venueId: session.venueId)
        else
          const EmptyNote('Only managers can change escalation limits.'),
        const SectionHeading('Checklist library'),
        if (!backendAvailable)
          const EmptyNote('Connect a backend to view checklists.')
        else
          const _TemplateList(),
      ],
    );
  }

  Future<void> _addSuite(BuildContext context, WidgetRef ref, String venueId) =>
      _editSpace(context, ref, venueId);
}

/// Adds a premium space, or edits [space] (a `venue_suites` row): its name or number,
/// its place on the map, and its details. Administrators only; row level security
/// enforces manage_configuration.
Future<void> _editSpace(
  BuildContext context,
  WidgetRef ref,
  String venueId, {
  Map<String, dynamic>? space,
}) async {
  final existing = await ref.read(venueSuitesProvider(venueId).future);
  if (!context.mounted) return;
  final draft = await showDialog<_SuiteDraft>(
    context: context,
    builder: (_) => _SuiteDialog(
      initial: space,
      takenPositions: {
        for (final s in existing)
          if (s['id'] != space?['id']) ?(s['map_area'] as String?),
      },
      takenNames: {
        for (final s in existing)
          if (s['id'] != space?['id']) s['name'] as String,
      },
    ),
  );
  if (draft == null || !context.mounted) return;
  final repo = ref.read(planningRepositoryProvider);
  await runWrite(context, () async {
    if (space == null) {
      await repo.addVenueSuite(
        venueId: venueId,
        name: draft.name,
        location: draft.location,
        serviceZone: draft.zone,
        capacity: draft.capacity,
        mapArea: draft.mapArea,
      );
    } else {
      await repo.updateVenueSuite(
        space['id'] as String,
        name: draft.name,
        location: draft.location,
        serviceZone: draft.zone,
        capacity: draft.capacity,
        mapArea: draft.mapArea,
      );
    }
    ref.invalidate(venueSuitesProvider(venueId));
    ref.invalidate(suitesProvider);
  }, success: space == null ? 'Added.' : 'Saved.');
}

class _ServiceSuiteCountCard extends ConsumerWidget {
  const _ServiceSuiteCountCard({
    required this.venueId,
    required this.canConfigure,
  });

  final String venueId;
  final bool canConfigure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(serviceSuiteCountProvider(venueId));
    final profiles = ref.watch(venueSuitesProvider(venueId));
    return OpenRow(
      leading: const PhosphorIcon(
        PhosphorIconsDuotone.door,
        color: AppColors.accent700,
      ),
      title: count.when(
        loading: () => 'Loading suite service count…',
        error: (_, _) => 'Suite service count unavailable',
        data: (value) => value == null
            ? 'Suite service count not set'
            : '$value luxury suites available for service',
      ),
      meta: profiles.when(
        loading: () => null,
        error: (_, _) => null,
        data: (list) => '${list.length} suite profiles configured',
      ),
      trailing: canConfigure
          ? const PhosphorIcon(PhosphorIconsDuotone.pencilSimple)
          : null,
      onTap: canConfigure ? () => _editCount(context, ref, count.value) : null,
    );
  }

  Future<void> _editCount(
    BuildContext context,
    WidgetRef ref,
    int? current,
  ) async {
    final entered = await showDialog<String>(
      context: context,
      builder: (_) => _MinutesDialog(
        title: 'Luxury suites available for service',
        initial: current?.toString() ?? '',
      ),
    );
    if (entered == null || !context.mounted) return;
    final count = int.tryParse(entered);
    if (count == null || count < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a whole number of suites, zero or greater.'),
        ),
      );
      return;
    }
    await runWrite(context, () async {
      await ref
          .read(planningRepositoryProvider)
          .setServiceSuiteCount(venueId, count);
      ref.invalidate(serviceSuiteCountProvider(venueId));
    }, success: 'Suite service count updated.');
  }
}

/// Minutes an unacknowledged request may wait before it escalates, per priority.
class _EscalationEditor extends ConsumerWidget {
  const _EscalationEditor({required this.venueId});

  final String venueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final limits = ref.watch(escalationThresholdsProvider);
    return limits.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Text('$error'),
      data: (map) => Column(
        children: [
          for (final p in RequestPriority.values)
            OpenRow(
              title: p.label,
              meta:
                  'Escalates after ${map[p]!.inMinutes} minutes without acknowledgment',
              trailing: const PhosphorIcon(PhosphorIconsDuotone.pencilSimple),
              onTap: () async {
                final text = await showDialog<String>(
                  context: context,
                  builder: (_) => _MinutesDialog(
                    title: '${p.label} escalation (minutes)',
                    initial: '${map[p]!.inMinutes}',
                  ),
                );
                if (text == null || !context.mounted) return;
                final minutes = int.tryParse(text);
                if (minutes == null || minutes < 1 || minutes > 1440) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Enter whole minutes between 1 and 1440.'),
                    ),
                  );
                  return;
                }
                await runWrite(context, () async {
                  await ref
                      .read(dispatchRepositoryProvider)
                      .setEscalationThreshold(venueId, p, minutes);
                  ref.invalidate(escalationThresholdsProvider);
                }, success: '${p.label} escalation set to $minutes minutes.');
              },
            ),
        ],
      ),
    );
  }
}

class _MinutesDialog extends StatefulWidget {
  const _MinutesDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_MinutesDialog> createState() => _MinutesDialogState();
}

class _MinutesDialogState extends State<_MinutesDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        autofocus: true,
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

class _SuiteList extends ConsumerWidget {
  const _SuiteList({required this.venueId, required this.canConfigure});

  final String venueId;
  final bool canConfigure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suites = ref.watch(venueSuitesProvider(venueId));
    return suites.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Text('$error'),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyNote('No suites yet.');
        }
        return Column(
          children: [
            for (final s in list)
              OpenRow(
                title: s['name'] as String,
                meta: [
                  _positionLabel(s),
                  if ((s['location'] as String?)?.isNotEmpty ?? false)
                    s['location'] as String,
                  if ((s['service_zone'] as String?)?.isNotEmpty ?? false)
                    'Zone ${s['service_zone']}',
                  if (s['capacity'] != null) 'Capacity ${s['capacity']}',
                ].join(' · '),
                trailing: canConfigure
                    ? const PhosphorIcon(PhosphorIconsDuotone.pencilSimple)
                    : null,
                onTap: canConfigure
                    ? () => _editSpace(context, ref, venueId, space: s)
                    : null,
              ),
          ],
        );
      },
    );
  }
}

/// Where a space is on the map, for the list.
String _positionLabel(Map<String, dynamic> space) {
  final area = planAreaId(
    space['name'] as String,
    space['map_area'] as String?,
  );
  if (area == null) return 'Not on the map';
  final position = mapPositions.where((p) => p.id == area).firstOrNull;
  return 'Map: ${position?.label ?? area}';
}

class _TemplateList extends ConsumerWidget {
  const _TemplateList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesProvider);
    return templates.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Text('$error'),
      data: (list) => Column(
        children: [
          for (final t in list)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 12),
              shape: const Border(),
              collapsedShape: const Border(),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              title: Text(t.name, style: AppText.rowTitle),
              subtitle: Text('${t.items.length} items', style: AppText.meta),
              children: [
                for (final item in t.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.label, style: AppText.body),
                        Text(
                          '${item.responseType.replaceAll('_', ' ')}'
                          '${item.requiresManagerApproval ? ' · needs manager approval' : ''}',
                          style: AppText.meta,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SuiteDraft {
  const _SuiteDraft({
    required this.name,
    required this.location,
    required this.zone,
    this.capacity,
    this.mapArea,
  });

  final String name;
  final String location;
  final String zone;
  final int? capacity;

  /// The map position: a plan suite number, a club, or the arena floor; null when
  /// the space is not on the map.
  final String? mapArea;
}

class _SuiteDialog extends StatefulWidget {
  const _SuiteDialog({
    this.initial,
    required this.takenPositions,
    required this.takenNames,
  });

  /// The space being edited, or null to add one.
  final Map<String, dynamic>? initial;

  /// Map positions other spaces already use.
  final Set<String> takenPositions;

  /// Names other spaces already use. Names are unique per venue.
  final Set<String> takenNames;

  @override
  State<_SuiteDialog> createState() => _SuiteDialogState();
}

class _SuiteDialogState extends State<_SuiteDialog> {
  late final _name = TextEditingController(
    text: widget.initial?['name'] as String? ?? '',
  );
  late final _location = TextEditingController(
    text: widget.initial?['location'] as String? ?? '',
  );
  late final _zone = TextEditingController(
    text: widget.initial?['service_zone'] as String? ?? '',
  );
  late final _capacity = TextEditingController(
    text: widget.initial?['capacity']?.toString() ?? '',
  );
  // An existing space keeps the position the map shows today, pinned from now on.
  late String? _mapArea = widget.initial == null
      ? null
      : planAreaId(
          widget.initial!['name'] as String,
          widget.initial!['map_area'] as String?,
        );
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _location, _zone, _capacity]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name or number.');
      return;
    }
    if (widget.takenNames.contains(name)) {
      setState(() => _error = 'Another space is already called $name.');
      return;
    }
    final capText = _capacity.text.trim();
    final capacity = capText.isEmpty ? null : int.tryParse(capText);
    if (capText.isNotEmpty && (capacity == null || capacity < 0)) {
      setState(() => _error = 'Capacity must be a whole number.');
      return;
    }
    // A new suite named with a free plan number goes to that position.
    var mapArea = _mapArea;
    if (widget.initial == null && mapArea == null) {
      final number = planSuiteNumber(name);
      if (number != null && !widget.takenPositions.contains(number)) {
        mapArea = number;
      }
    }
    Navigator.pop(
      context,
      _SuiteDraft(
        name: name,
        location: _location.text.trim(),
        zone: _zone.text.trim(),
        capacity: capacity,
        mapArea: mapArea,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return AlertDialog(
      title: Text(editing ? 'Edit space' : 'Add premium space'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: 'Name or number',
                hintText: 'Suite 204, Owners Club, Main Arena Floor',
                helperText: editing
                    ? 'Renaming keeps the space in the same place on the map.'
                    : null,
                errorText: _error,
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: _mapArea,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'On the map'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Not on the map'),
                ),
                for (final position in mapPositions)
                  if (!widget.takenPositions.contains(position.id))
                    DropdownMenuItem(
                      value: position.id,
                      child: Text(
                        position.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
              onChanged: (value) => setState(() => _mapArea = value),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _location,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _zone,
              decoration: const InputDecoration(labelText: 'Service zone'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _capacity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Capacity (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: Text(editing ? 'Save' : 'Add')),
      ],
    );
  }
}
