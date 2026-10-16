import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Administration & Configuration')),
      floatingActionButton: canConfigure && backendAvailable && session != null
          ? FloatingActionButton.extended(
              onPressed: () => _addSuite(context, ref, session.venueId),
              icon: const Icon(Icons.add),
              label: const Text('Add space'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Text('Venue', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              title: Text(session?.venueName ?? '—'),
              subtitle: Text('Time zone: ${session?.timeZone ?? '—'}'),
            ),
          ),
          if (canConfigure && backendAvailable) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Staff accounts'),
                subtitle: const Text(
                  'Add staff, reset PINs, deactivate or remove accounts',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/staff'),
              ),
            ),
          ],
          if (backendAvailable && session != null) ...[
            const SizedBox(height: 20),
            BanquetAreasSection(
              venueId: session.venueId,
              canConfigure: canConfigure,
              canManageEvents: permissions.contains(AppPermission.manageEvents),
            ),
          ],
          const SizedBox(height: 20),
          Text('Suites', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (!backendAvailable)
            const Text(
              'Connect a backend to manage suites.',
              style: TextStyle(color: AppColors.charcoalMuted),
            )
          else if (session == null)
            const SizedBox.shrink()
          else ...[
            _ServiceSuiteCountCard(
              venueId: session.venueId,
              canConfigure: canConfigure,
            ),
            const SizedBox(height: 8),
            _SuiteList(venueId: session.venueId),
          ],
          const SizedBox(height: 20),
          if (backendAvailable && session != null && canConfigure) ...[
            PeopleSection(
              venueId: session.venueId,
              currentUserId: session.userId,
            ),
            const SizedBox(height: 20),
          ],
          Text(
            'Escalation limits',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (!backendAvailable)
            const Text(
              'Connect a backend to change escalation limits.',
              style: TextStyle(color: AppColors.charcoalMuted),
            )
          else if (session != null && canConfigure)
            _EscalationEditor(venueId: session.venueId)
          else
            const Text(
              'Only managers can change escalation limits.',
              style: TextStyle(color: AppColors.charcoalMuted),
            ),
          const SizedBox(height: 20),
          Text(
            'Checklist library',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (!backendAvailable)
            const Text(
              'Connect a backend to view checklists.',
              style: TextStyle(color: AppColors.charcoalMuted),
            )
          else
            const _TemplateList(),
        ],
      ),
    );
  }

  Future<void> _addSuite(
    BuildContext context,
    WidgetRef ref,
    String venueId,
  ) async {
    final existing = await ref.read(venueSuitesProvider(venueId).future);
    if (!context.mounted) return;
    final draft = await showDialog<_SuiteDraft>(
      context: context,
      builder: (_) => _SuiteDialog(
        placedClubs: {for (final s in existing) ?(s['map_area'] as String?)},
      ),
    );
    if (draft == null || !context.mounted) return;
    await runWrite(context, () async {
      await ref
          .read(planningRepositoryProvider)
          .addVenueSuite(
            venueId: venueId,
            name: draft.name,
            location: draft.location,
            serviceZone: draft.zone,
            capacity: draft.capacity,
            mapArea: draft.mapArea,
          );
      ref.invalidate(venueSuitesProvider(venueId));
    }, success: 'Added.');
  }
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
    return Card(
      child: ListTile(
        leading: const Icon(Icons.meeting_room_outlined),
        title: count.when(
          loading: () => const Text('Loading suite service count…'),
          error: (_, _) => const Text('Suite service count unavailable'),
          data: (value) => Text(
            value == null
                ? 'Suite service count not set'
                : '$value luxury suites available for service',
          ),
        ),
        subtitle: profiles.when(
          loading: () => null,
          error: (_, _) => null,
          data: (list) => Text('${list.length} suite profiles configured'),
        ),
        trailing: canConfigure ? const Icon(Icons.edit_outlined) : null,
        onTap: canConfigure
            ? () => _editCount(context, ref, count.value)
            : null,
      ),
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
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(p.label),
                subtitle: Text(
                  'Escalates after ${map[p]!.inMinutes} minutes without acknowledgment',
                ),
                trailing: const Icon(Icons.edit_outlined),
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
                        content: Text(
                          'Enter whole minutes between 1 and 1440.',
                        ),
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
  const _SuiteList({required this.venueId});

  final String venueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suites = ref.watch(venueSuitesProvider(venueId));
    return suites.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Text('$error'),
      data: (list) {
        if (list.isEmpty) {
          return const Text(
            'No suites yet.',
            style: TextStyle(color: AppColors.charcoalMuted),
          );
        }
        return Column(
          children: [
            for (final s in list)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(s['name'] as String),
                  subtitle: Text(
                    [
                      if ((s['location'] as String?)?.isNotEmpty ?? false)
                        s['location'] as String,
                      if ((s['service_zone'] as String?)?.isNotEmpty ?? false)
                        'Zone ${s['service_zone']}',
                      if (s['capacity'] != null) 'Capacity ${s['capacity']}',
                      if (_clubLabel(s['map_area'] as String?) case final club?)
                        '$club on the map',
                    ].join(' · '),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
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
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                title: Text(t.name),
                subtitle: Text('${t.items.length} items'),
                children: [
                  for (final item in t.items)
                    ListTile(
                      dense: true,
                      title: Text(item.label),
                      subtitle: Text(
                        '${item.responseType.replaceAll('_', ' ')}'
                        '${item.requiresManagerApproval ? ' · needs manager approval' : ''}',
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String? _clubLabel(String? mapArea) => mapArea == arenaFloorArea
    ? 'Arena floor'
    : premiumLevelClubs.where((c) => c.mapArea == mapArea).firstOrNull?.label;

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

  /// The club outline this space is drawn as; null for a suite.
  final String? mapArea;
}

class _SuiteDialog extends StatefulWidget {
  const _SuiteDialog({required this.placedClubs});

  /// Clubs already placed on the map, which cannot be placed twice.
  final Set<String> placedClubs;

  @override
  State<_SuiteDialog> createState() => _SuiteDialogState();
}

class _SuiteDialogState extends State<_SuiteDialog> {
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _zone = TextEditingController();
  final _capacity = TextEditingController();
  String? _mapArea;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _location, _zone, _capacity]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add premium space'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String?>(
              initialValue: _mapArea,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'On the map'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Suite: matched by the number in its name'),
                ),
                for (final club in premiumLevelClubs)
                  if (!widget.placedClubs.contains(club.mapArea))
                    DropdownMenuItem(
                      value: club.mapArea,
                      child: Text(
                        '${club.label}, ${club.place}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                if (!widget.placedClubs.contains(arenaFloorArea))
                  const DropdownMenuItem(
                    value: arenaFloorArea,
                    child: Text('Arena floor, the open center'),
                  ),
              ],
              onChanged: (value) => setState(() => _mapArea = value),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: _mapArea == null ? 'Suite name' : 'Name',
                errorText: _error,
              ),
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
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) {
              setState(
                () => _error = _mapArea == null
                    ? 'Name the suite.'
                    : 'Name this space.',
              );
              return;
            }
            final capText = _capacity.text.trim();
            final capacity = capText.isEmpty ? null : int.tryParse(capText);
            if (capText.isNotEmpty && (capacity == null || capacity < 0)) {
              setState(() => _error = 'Capacity must be a whole number.');
              return;
            }
            Navigator.pop(
              context,
              _SuiteDraft(
                name: _name.text.trim(),
                location: _location.text.trim(),
                zone: _zone.text.trim(),
                capacity: capacity,
                mapArea: _mapArea,
              ),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
