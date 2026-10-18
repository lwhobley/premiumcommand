import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/icons/phosphor.dart';

import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/venue_time.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../../core/widgets/tag.dart';
import '../../auth/application/session_controller.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../domain/premium_level_layout.dart';
import '../domain/suite.dart';
import '../domain/suite_order.dart';
import 'suite_map_view.dart';

/// How a suite is shown on the map for one event.
enum SuiteMapStatus {
  unassigned('Not in this event', AppColors.neutral200, Tone.neutral),
  noOrder('No order', AppColors.neutral400, Tone.neutral),
  draft('Order draft', AppColors.neutral600, Tone.neutral),
  confirmed('Order confirmed', AppColors.accent, Tone.accent),
  delivered('Delivered', AppColors.accent700, Tone.accent);

  const SuiteMapStatus(this.label, this.color, this.tone);

  final String label;

  /// Map fill, sent to the 3D page as hex.
  final Color color;

  /// Tag tone for the same status.
  final Tone tone;
}

/// Suite tile and map fill by state.
Color suiteStateColor(SuiteState state) => switch (state) {
  SuiteState.notStarted => AppColors.neutral300,
  SuiteState.setupInProgress => AppColors.accent300,
  SuiteState.ready => AppColors.accent,
  SuiteState.inService => AppColors.accent700,
  SuiteState.closing => AppColors.accent2300,
  SuiteState.closed => AppColors.neutral400,
};

/// Tag tone for a suite state: ready, in service and setup are accent; the rest neutral.
Tone suiteStateTone(SuiteState state) => switch (state) {
  SuiteState.setupInProgress ||
  SuiteState.ready ||
  SuiteState.inService => Tone.accent,
  SuiteState.notStarted ||
  SuiteState.closing ||
  SuiteState.closed => Tone.neutral,
};

/// Map status by map area (suite number or club). Spaces missing from the result are
/// not assigned to the event.
Map<String, SuiteMapStatus> suiteMapStatuses(
  List<SuiteAssignment> assignments,
  List<SuiteOrder> orders,
) {
  final orderByAssignment = {for (final o in orders) o.assignmentId: o};
  return {
    for (final a in assignments)
      ?a.planArea: switch (orderByAssignment[a.id]?.status) {
        null => SuiteMapStatus.noOrder,
        SuiteOrderStatus.draft => SuiteMapStatus.draft,
        SuiteOrderStatus.confirmed => SuiteMapStatus.confirmed,
        SuiteOrderStatus.delivered => SuiteMapStatus.delivered,
      },
  };
}

String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

List<List<double>> _points(Iterable<PlanPoint> points) => [
  for (final p in points) [p.$1, p.$2],
];

/// The payload the 3D page draws: plan outlines plus a color per space, keyed by
/// suite number, club, or arena floor map area. A space with no color is drawn muted.
/// Map labels by map area, from each space's configured name. Positions with no
/// space keep their plan label.
Map<String, String> mapLabelsFor(List<Map<String, dynamic>> venueSuites) => {
  for (final s in venueSuites) ?_areaOf(s): mapLabel(s['name'] as String),
};

Map<String, Object?> buildSuiteColorScene(
  Map<String, Color> colors, {
  String? selected,
  Map<String, String> labels = const {},
}) => {
  'center': [610.5, 415.2],
  'bowlEdge': _points(premiumLevelBowlEdge),
  'footprint': _points(premiumLevelFootprint),
  'selected': selected,
  'suites': [
    for (final suite in premiumLevelSuites)
      {
        'id': suite.number,
        'label': _suiteLabel(labels[suite.number] ?? suite.number),
        'points': _points(suite.points),
        'color': _hex(colors[suite.number] ?? SuiteMapStatus.unassigned.color),
        'muted': !colors.containsKey(suite.number),
      },
    for (final club in premiumLevelClubs)
      {
        'id': club.mapArea,
        'label': labels[club.mapArea] ?? club.label,
        'points': _points(club.points),
        'color': _hex(colors[club.mapArea] ?? SuiteMapStatus.unassigned.color),
        'muted': !colors.containsKey(club.mapArea),
      },
  ],
  // Drawn from bowlEdge at ground level; muted keeps the plain floor color.
  'floor': {
    'id': arenaFloorArea,
    'label': labels[arenaFloorArea] ?? 'Arena floor',
    'color': _hex(colors[arenaFloorArea] ?? SuiteMapStatus.unassigned.color),
    'muted': !colors.containsKey(arenaFloorArea),
  },
  // Drawn at ground level between footprint and bowlEdge, under the premium level.
  'concourse': {
    'id': concourseArea,
    'label': labels[concourseArea] ?? 'Concourse',
    'color': _hex(colors[concourseArea] ?? SuiteMapStatus.unassigned.color),
    'muted': !colors.containsKey(concourseArea),
  },
  // Seating sections, for orientation only: the scene draws them but never selects them.
  'sections': [
    for (final section in lowerBowlSections)
      {'id': section.name, 'kind': 'bowl', 'points': _points(section.points)},
    for (final section in westClubSections)
      {
        'id': section.name,
        'kind': 'club',
        'space': 'club_a',
        'points': _points(section.points),
      },
  ],
};

/// Suite labels read like the seating chart: a bare number becomes 'S204'.
String _suiteLabel(String label) =>
    RegExp(r'^\d+$').hasMatch(label) ? 'S$label' : label;

Map<String, Object?> buildSuiteMapScene(
  Map<String, SuiteMapStatus> statuses, {
  String? selected,
  Map<String, String> labels = const {},
}) => buildSuiteColorScene(
  {for (final entry in statuses.entries) entry.key: entry.value.color},
  selected: selected,
  labels: labels,
);

/// Clickable 3D premium-level map for the selected event. Hidden when none of
/// the venue's configured suites match a suite number on the plan.
class SuiteMapSection extends ConsumerStatefulWidget {
  const SuiteMapSection({
    super.key,
    required this.venueId,
    required this.eventId,
  });

  final String venueId;
  final String eventId;

  @override
  ConsumerState<SuiteMapSection> createState() => _SuiteMapSectionState();
}

class _SuiteMapSectionState extends ConsumerState<SuiteMapSection> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final venueSuites =
        ref.watch(venueSuitesProvider(widget.venueId)).value ?? const [];
    if (!venueSuites.any((s) => _areaOf(s) != null)) {
      return const SizedBox.shrink();
    }
    final assignments =
        ref.watch(suitesProvider(widget.eventId)).value ?? const [];
    final orders =
        ref.watch(suiteOrdersProvider(widget.eventId)).value ?? const [];
    final statuses = suiteMapStatuses(assignments, orders);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading('Premium level map'),
        const Text(
          'Tap a suite, club, or the arena floor to open its order and the event BEO. Drag to rotate; pinch or scroll to zoom.',
          style: AppText.meta,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: AppSpace.m,
          runSpacing: 6,
          children: [
            for (final status in SuiteMapStatus.values)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: status.color,
                      borderRadius: AppRadius.all,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${status.label} (${status == SuiteMapStatus.unassigned ? premiumLevelAreaCount - statuses.length : statuses.values.where((s) => s == status).length})',
                    style: AppText.meta,
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: AppRadius.all,
          child: SizedBox(
            height: 460,
            child: SuiteMapView(
              sceneData: buildSuiteMapScene(
                statuses,
                selected: _selected,
                labels: mapLabelsFor(venueSuites),
              ),
              onSuiteTap: _open,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Traced from the labeled premium-level plan. The arena floor is the open center; proportional, not to scale.',
          style: AppText.meta,
        ),
      ],
    );
  }

  Future<void> _open(String area) async {
    setState(() => _selected = area);
    await showSuitePanel(
      context,
      venueId: widget.venueId,
      eventId: widget.eventId,
      areaId: area,
    );
    if (mounted) setState(() => _selected = null);
  }
}

String? _areaOf(Map<String, dynamic> venueSuite) =>
    planAreaId(venueSuite['name'] as String, venueSuite['map_area'] as String?);

/// Opens a suite's or club's event panel: its state, its order, and the event BEO.
/// [areaId] is a suite number on the plan or a club map area.
Future<void> showSuitePanel(
  BuildContext context, {
  required String venueId,
  required String eventId,
  required String areaId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) =>
      _SuitePanel(venueId: venueId, eventId: eventId, areaId: areaId),
);

class _SuitePanel extends ConsumerWidget {
  const _SuitePanel({
    required this.venueId,
    required this.eventId,
    required this.areaId,
  });

  final String venueId;
  final String eventId;
  final String areaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final permissions = session?.permissions ?? const <AppPermission>{};
    final timeZone = session?.timeZone ?? 'UTC';
    final venueSuite =
        (ref.watch(venueSuitesProvider(venueId)).value ?? const [])
            .where((s) => _areaOf(s) == areaId)
            .firstOrNull;
    final assignment = (ref.watch(suitesProvider(eventId)).value ?? const [])
        .where((a) => a.planArea == areaId)
        .firstOrNull;
    final club = premiumLevelClubs
        .where((c) => c.mapArea == areaId)
        .firstOrNull;
    final isFloor = areaId == arenaFloorArea;
    final isConcourse = areaId == concourseArea;
    final noun = isFloor
        ? 'arena floor'
        : isConcourse
        ? 'concourse'
        : (club == null ? 'suite' : 'club');
    final order = assignment == null
        ? null
        : (ref.watch(suiteOrdersProvider(eventId)).value ?? const [])
              .where((o) => o.assignmentId == assignment.id)
              .firstOrNull;
    final canManage = permissions.contains(AppPermission.manageEvents);

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
            Text(
              (venueSuite?['name'] as String?) ??
                  (isFloor
                      ? 'Arena floor'
                      : isConcourse
                      ? 'Concourse'
                      : club == null
                      ? 'Suite $areaId'
                      : club.label),
              style: AppText.sectionHeading,
            ),
            const SizedBox(height: 10),
            if (venueSuite == null)
              Text(
                'The $noun is not set up as a service area yet.',
                style: AppText.body,
              )
            else if (assignment == null) ...[
              Text(
                'Not assigned to this event.',
                style: AppText.body.copyWith(color: AppColors.muted),
              ),
              if (canManage) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => runWrite(context, () async {
                    await ref
                        .read(planningRepositoryProvider)
                        .assignSuite(
                          venueId: venueId,
                          eventId: eventId,
                          suiteId: venueSuite['id'] as String,
                        );
                    ref.invalidate(suitesProvider(eventId));
                  }, success: 'Added to the event.'),
                  icon: const PhosphorIcon(PhosphorIconsDuotone.plus),
                  label: const Text('Add to this event'),
                ),
              ],
            ] else ...[
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  Tag(assignment.state.label, suiteStateTone(assignment.state)),
                  Tag(
                    order == null
                        ? 'No order'
                        : 'Order ${order.status.label.toLowerCase()}',
                    switch (order?.status) {
                      null => SuiteMapStatus.noOrder.tone,
                      SuiteOrderStatus.draft => SuiteMapStatus.draft.tone,
                      SuiteOrderStatus.confirmed =>
                        SuiteMapStatus.confirmed.tone,
                      SuiteOrderStatus.delivered =>
                        SuiteMapStatus.delivered.tone,
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                [
                  'Attendant: ${assignment.attendantName.isEmpty ? 'unassigned' : assignment.attendantName}',
                  if (assignment.guestContact.isNotEmpty)
                    'Contact: ${assignment.guestContact}',
                ].join(' · '),
                style: AppText.meta,
              ),
              if (assignment.dietaryNotes.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Dietary: ${assignment.dietaryNotes}',
                  style: AppText.body,
                ),
              ],
              const SectionHeading('Order'),
              if (order == null)
                Text(
                  'No order yet.',
                  style: AppText.body.copyWith(color: AppColors.muted),
                )
              else ...[
                if (order.deliverAt != null)
                  Text(
                    'Deliver ${DateFormat('EEE MMM d, h:mm a').format(atVenue(order.deliverAt!, timeZone))}',
                    style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                if (order.items.isEmpty)
                  Text(
                    'No items yet.',
                    style: AppText.body.copyWith(color: AppColors.muted),
                  ),
                for (final item in order.items)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${item.quantity} × ${item.name}${item.notes.isEmpty ? '' : ' — ${item.notes}'}',
                      style: AppText.body,
                    ),
                  ),
                if (order.notes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Notes: ${order.notes}', style: AppText.meta),
                ],
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canManage && order?.status != SuiteOrderStatus.delivered)
                    OutlinedButton.icon(
                      onPressed: () =>
                          _editOrder(context, ref, assignment, order, timeZone),
                      icon: const PhosphorIcon(
                        PhosphorIconsDuotone.pencilSimple,
                      ),
                      label: Text(order == null ? 'Start order' : 'Edit order'),
                    ),
                  if (canManage &&
                      order != null &&
                      order.status == SuiteOrderStatus.draft &&
                      order.items.isNotEmpty)
                    FilledButton(
                      onPressed: () => _setStatus(
                        context,
                        ref,
                        order,
                        SuiteOrderStatus.confirmed,
                      ),
                      child: const Text('Confirm order'),
                    ),
                  if (permissions.contains(AppPermission.updateTasks) &&
                      order?.status == SuiteOrderStatus.confirmed)
                    FilledButton(
                      onPressed: () => _setStatus(
                        context,
                        ref,
                        order!,
                        SuiteOrderStatus.delivered,
                      ),
                      child: const Text('Mark delivered'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpace.l),
            Transform.translate(
              offset: const Offset(-10, 0),
              child: TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/beo/event/$eventId');
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

  Future<void> _editOrder(
    BuildContext context,
    WidgetRef ref,
    SuiteAssignment assignment,
    SuiteOrder? order,
    String timeZone,
  ) async {
    final result = await showDialog<_OrderDraft>(
      context: context,
      builder: (_) => _SuiteOrderDialog(
        suiteName: assignment.suiteName,
        order: order,
        timeZone: timeZone,
      ),
    );
    if (result == null || !context.mounted) return;
    await runWrite(
      context,
      () async {
        await ref
            .read(planningRepositoryProvider)
            .saveSuiteOrder(
              assignment.id,
              items: result.items,
              deliverAt: result.deliverAt,
              notes: result.notes,
              expectedVersion: order?.version ?? 0,
            );
        ref.invalidate(suiteOrdersProvider(eventId));
      },
      success: order?.status == SuiteOrderStatus.confirmed
          ? 'Order saved. It is back in draft until confirmed again.'
          : 'Order saved.',
    );
  }

  Future<void> _setStatus(
    BuildContext context,
    WidgetRef ref,
    SuiteOrder order,
    SuiteOrderStatus to,
  ) => runWrite(context, () async {
    await ref
        .read(planningRepositoryProvider)
        .setSuiteOrderStatus(order.id, to, order.version);
    ref.invalidate(suiteOrdersProvider(eventId));
  }, success: 'Order ${to.label.toLowerCase()}.');
}

typedef _OrderDraft = ({
  List<SuiteOrderItem> items,
  DateTime? deliverAt,
  String notes,
});

class _ItemFields {
  _ItemFields([SuiteOrderItem? item])
    : name = TextEditingController(text: item?.name ?? ''),
      quantity = TextEditingController(text: '${item?.quantity ?? 1}'),
      notes = TextEditingController(text: item?.notes ?? '');

  final TextEditingController name;
  final TextEditingController quantity;
  final TextEditingController notes;

  void dispose() {
    name.dispose();
    quantity.dispose();
    notes.dispose();
  }
}

class _SuiteOrderDialog extends StatefulWidget {
  const _SuiteOrderDialog({
    required this.suiteName,
    required this.order,
    required this.timeZone,
  });

  final String suiteName;
  final SuiteOrder? order;
  final String timeZone;

  @override
  State<_SuiteOrderDialog> createState() => _SuiteOrderDialogState();
}

class _SuiteOrderDialogState extends State<_SuiteOrderDialog> {
  late final List<_ItemFields> _items = [
    for (final item in widget.order?.items ?? const <SuiteOrderItem>[])
      _ItemFields(item),
    if (widget.order?.items.isEmpty ?? true) _ItemFields(),
  ];
  late final _notes = TextEditingController(text: widget.order?.notes ?? '');
  late DateTime? _deliverAt = widget.order?.deliverAt;
  String? _error;

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    final items = <SuiteOrderItem>[];
    for (final fields in _items) {
      final name = fields.name.text.trim();
      if (name.isEmpty) continue;
      final quantity = int.tryParse(fields.quantity.text.trim());
      if (quantity == null || quantity < 1 || quantity > 999) {
        setState(
          () => _error =
              'Quantity for "$name" must be a whole number from 1 to 999.',
        );
        return;
      }
      items.add(
        SuiteOrderItem(
          name: name,
          quantity: quantity,
          notes: fields.notes.text.trim(),
        ),
      );
    }
    Navigator.of(context).pop<_OrderDraft>((
      items: items,
      deliverAt: _deliverAt,
      notes: _notes.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.suiteName} order'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (index, fields) in _items.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 64,
                        child: TextField(
                          controller: fields.quantity,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Qty'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          children: [
                            TextField(
                              controller: fields.name,
                              decoration: const InputDecoration(
                                labelText: 'Item',
                              ),
                            ),
                            TextField(
                              controller: fields.notes,
                              decoration: const InputDecoration(
                                labelText: 'Item notes (optional)',
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove item',
                        onPressed: () {
                          final removed = _items.removeAt(index);
                          setState(() {});
                          // The fields still use these controllers until the next frame.
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => removed.dispose(),
                          );
                        },
                        icon: const PhosphorIcon(PhosphorIconsDuotone.x),
                      ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: () => setState(() => _items.add(_ItemFields())),
                icon: const PhosphorIcon(PhosphorIconsDuotone.plus),
                label: const Text('Add item'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _deliverAt == null
                          ? 'No delivery time'
                          : 'Deliver ${DateFormat('EEE MMM d, h:mm a').format(atVenue(_deliverAt!, widget.timeZone))}',
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await pickDateTime(
                        context,
                        _deliverAt ??
                            DateTime.now().add(const Duration(hours: 1)),
                        timeZone: widget.timeZone,
                      );
                      if (picked != null) setState(() => _deliverAt = picked);
                    },
                    child: const Text('Set time'),
                  ),
                  if (_deliverAt != null)
                    IconButton(
                      tooltip: 'Clear delivery time',
                      onPressed: () => setState(() => _deliverAt = null),
                      icon: const PhosphorIcon(PhosphorIconsDuotone.x),
                    ),
                ],
              ),
              TextField(
                controller: _notes,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Order notes'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: AppText.body.copyWith(color: AppColors.accent2700),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save order')),
      ],
    );
  }
}
