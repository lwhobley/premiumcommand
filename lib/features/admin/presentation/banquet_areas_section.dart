import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/icons/phosphor.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../data/banquet_area_repository.dart';
import '../domain/banquet_area.dart';
import '../../floor_plan/presentation/banquet_area_beo_links.dart';

class BanquetAreasSection extends ConsumerWidget {
  const BanquetAreasSection({
    super.key,
    required this.venueId,
    required this.canConfigure,
    required this.canManageEvents,
  });

  final String venueId;
  final bool canConfigure;
  final bool canManageEvents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areas = ref.watch(banquetAreasProvider(venueId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'Banquet areas',
          trailing: canConfigure
              ? TextButton.icon(
                  onPressed: () => _edit(context, ref),
                  icon: const PhosphorIcon(PhosphorIconsDuotone.plus),
                  label: const Text('Add area'),
                )
              : null,
        ),
        areas.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const EmptyNote('Banquet areas unavailable.'),
          data: (items) => items.isEmpty
              ? const EmptyNote('No banquet areas configured.')
              : Column(
                  children: [
                    for (final area in items)
                      OpenRow(
                        title: area.name,
                        meta: _description(area),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: 'View area BEOs',
                              onPressed: () => showBanquetAreaBeoLinks(
                                context,
                                area: area,
                                venueId: venueId,
                                canManage: canManageEvents,
                              ),
                              icon: const PhosphorIcon(
                                PhosphorIconsDuotone.fileText,
                              ),
                            ),
                            if (canConfigure)
                              IconButton(
                                tooltip: 'Edit area',
                                onPressed: () => _edit(context, ref, area),
                                icon: const PhosphorIcon(
                                  PhosphorIconsDuotone.pencilSimple,
                                ),
                              ),
                          ],
                        ),
                        onTap: () => showBanquetAreaBeoLinks(
                          context,
                          area: area,
                          venueId: venueId,
                          canManage: canManageEvents,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  String _description(BanquetArea area) {
    final parts = <String>[
      if (area.spaceCount > 1) '${area.spaceCount} rooms',
      if (area.areaSquareFeet != null)
        '${NumberFormat.decimalPattern().format(area.areaSquareFeet)} sq ft',
      if (area.capacityPerSpace != null)
        area.spaceCount > 1
            ? 'Up to ${area.capacityPerSpace} guests each'
            : 'Up to ${area.capacityPerSpace} guests',
      if (area.hasFullServiceBar == true) 'Full-service bar',
      if (area.canCombine) 'Rooms can combine',
      if (area.canCombine && area.combinedCapacity == null)
        'Combined capacity not provided',
      if (area.combinedCapacity != null)
        'Combined capacity: ${area.combinedCapacity}',
    ];
    return parts.join(' · ');
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    BanquetArea? area,
  ]) async {
    final draft = await showDialog<_AreaDraft>(
      context: context,
      builder: (_) => _AreaDialog(area: area),
    );
    if (draft == null || !context.mounted) return;
    await runWrite(context, () async {
      await ref
          .read(banquetAreaRepositoryProvider)
          .save(
            id: area?.id,
            venueId: venueId,
            name: draft.name,
            kind: draft.kind,
            spaceCount: draft.spaceCount,
            capacityPerSpace: draft.capacityPerSpace,
            areaSquareFeet: draft.areaSquareFeet,
            canCombine: draft.canCombine,
            combinedCapacity: draft.combinedCapacity,
            hasFullServiceBar: draft.hasFullServiceBar,
          );
      ref.invalidate(banquetAreasProvider(venueId));
    }, success: 'Banquet area saved.');
  }
}

class _AreaDraft {
  const _AreaDraft({
    required this.name,
    required this.kind,
    required this.spaceCount,
    this.capacityPerSpace,
    this.areaSquareFeet,
    required this.canCombine,
    this.combinedCapacity,
    this.hasFullServiceBar,
  });

  final String name;
  final String kind;
  final int spaceCount;
  final int? capacityPerSpace;
  final int? areaSquareFeet;
  final bool canCombine;
  final int? combinedCapacity;
  final bool? hasFullServiceBar;
}

class _AreaDialog extends StatefulWidget {
  const _AreaDialog({this.area});

  final BanquetArea? area;

  @override
  State<_AreaDialog> createState() => _AreaDialogState();
}

class _AreaDialogState extends State<_AreaDialog> {
  static const _kinds = <String, String>{
    'arena_floor': 'Arena floor',
    'premium_lounge': 'Premium lounge',
    'meeting_room_group': 'Meeting rooms',
    'banquet_room': 'Banquet room',
    'other': 'Other',
  };

  late final _name = TextEditingController(text: widget.area?.name ?? '');
  late final _count = TextEditingController(
    text: '${widget.area?.spaceCount ?? 1}',
  );
  late final _capacity = TextEditingController(
    text: widget.area?.capacityPerSpace?.toString() ?? '',
  );
  late final _area = TextEditingController(
    text: widget.area?.areaSquareFeet?.toString() ?? '',
  );
  late final _combined = TextEditingController(
    text: widget.area?.combinedCapacity?.toString() ?? '',
  );
  late String _kind = widget.area?.kind ?? 'other';
  late bool _canCombine = widget.area?.canCombine ?? false;
  late bool? _bar = widget.area?.hasFullServiceBar;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_name, _count, _capacity, _area, _combined]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.area == null ? 'Add banquet area' : 'Edit banquet area',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Area name'),
              ),
              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Area type'),
                items: [
                  if (!_kinds.containsKey(_kind))
                    DropdownMenuItem(
                      value: _kind,
                      child: Text('Current type: $_kind'),
                    ),
                  for (final entry in _kinds.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (value) => setState(() => _kind = value ?? _kind),
              ),
              TextField(
                controller: _count,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Number of rooms in this area',
                ),
              ),
              TextField(
                controller: _capacity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Maximum guests per room (optional)',
                ),
              ),
              TextField(
                controller: _area,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Area in square feet (optional)',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Rooms can combine'),
                value: _canCombine,
                onChanged: (value) => setState(() => _canCombine = value),
              ),
              if (_canCombine)
                TextField(
                  controller: _combined,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Combined capacity (optional)',
                  ),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                tristate: true,
                title: const Text('Full-service bar'),
                subtitle: const Text('Leave unset if not confirmed.'),
                value: _bar,
                onChanged: (value) => setState(() => _bar = value),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: AppText.body.copyWith(color: AppColors.accent2700),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  void _save() {
    final name = _name.text.trim();
    final count = int.tryParse(_count.text.trim());
    final capacity = _optionalPositive(_capacity.text);
    final area = _optionalPositive(_area.text);
    final combined = _canCombine ? _optionalPositive(_combined.text) : null;
    if (name.isEmpty ||
        count == null ||
        count < 1 ||
        capacity == -1 ||
        area == -1 ||
        combined == -1) {
      setState(
        () => _error = 'Enter a name, at least one room, and positive values for any filled numbers.',
      );
      return;
    }
    Navigator.pop(
      context,
      _AreaDraft(
        name: name,
        kind: _kind,
        spaceCount: count,
        capacityPerSpace: capacity,
        areaSquareFeet: area,
        canCombine: _canCombine,
        combinedCapacity: combined,
        hasFullServiceBar: _bar,
      ),
    );
  }

  int? _optionalPositive(String input) {
    if (input.trim().isEmpty) return null;
    final parsed = int.tryParse(input.trim());
    return parsed != null && parsed > 0 ? parsed : -1;
  }
}
