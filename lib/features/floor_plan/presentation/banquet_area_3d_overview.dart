import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../admin/data/banquet_area_repository.dart';
import '../../admin/domain/banquet_area.dart';
import 'banquet_area_beo_links.dart';
import '../domain/banquet_area_scene.dart';
import 'floor_plan_3d_view.dart';

/// A conceptual 3D view of the verified area facts. It never supplies room
/// dimensions to the measured floor-plan and seating-layout workflow.
class BanquetArea3DOverview extends ConsumerStatefulWidget {
  const BanquetArea3DOverview({
    super.key,
    required this.venueId,
    required this.canManageAreaLinks,
  });

  final String venueId;
  final bool canManageAreaLinks;

  @override
  ConsumerState<BanquetArea3DOverview> createState() =>
      _BanquetArea3DOverviewState();
}

class _BanquetArea3DOverviewState extends ConsumerState<BanquetArea3DOverview> {
  String? _selectedId;
  bool _combined = false;

  @override
  Widget build(BuildContext context) {
    final areasAsync = ref.watch(banquetAreasProvider(widget.venueId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Banquet area 3D overview',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        const Text(
          'Schematic only. Room shapes, dimensions, doors, and furniture have not been verified.',
          style: TextStyle(color: AppColors.charcoalMuted),
        ),
        const SizedBox(height: 12),
        areasAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Text(
            'Area profiles unavailable. Apply the banquet area migration to enable this view.',
          ),
          data: (areas) {
            if (areas.isEmpty) {
              return const Text(
                'No banquet area profiles are configured for this venue.',
              );
            }
            final current =
                areas.where((area) => area.id == _selectedId).firstOrNull ??
                areas.first;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: current.id,
                  decoration: const InputDecoration(labelText: 'Banquet area'),
                  items: [
                    for (final area in areas)
                      DropdownMenuItem(value: area.id, child: Text(area.name)),
                  ],
                  onChanged: (value) => setState(() {
                    _selectedId = value;
                    _combined = false;
                  }),
                ),
                const SizedBox(height: 10),
                Text(_summary(current)),
                const SizedBox(height: 8),
                BanquetAreaBeoLinksButton(
                  area: current,
                  venueId: widget.venueId,
                  canManage: widget.canManageAreaLinks,
                ),
                if (current.canCombine && current.spaceCount > 1) ...[
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Separate rooms'),
                      ),
                      ButtonSegment(value: true, label: Text('Combined view')),
                    ],
                    selected: {_combined},
                    onSelectionChanged: (selected) =>
                        setState(() => _combined = selected.first),
                  ),
                  if (_combined && current.combinedCapacity == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Combined guest capacity has not been provided.',
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                FloorPlan3DView(
                  key: ValueKey('${current.id}-$_combined'),
                  sceneData: buildBanquetAreaSceneData(
                    current,
                    combined: _combined,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Illustrative, unscaled 3D schematic. Use a measured floor plan below for table placement.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.charcoalMuted,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  String _summary(BanquetArea area) => [
    if (area.spaceCount > 1) '${area.spaceCount} rooms',
    if (area.areaSquareFeet != null)
      '${NumberFormat.decimalPattern().format(area.areaSquareFeet)} sq ft',
    if (area.capacityPerSpace != null)
      area.spaceCount > 1
          ? 'Up to ${area.capacityPerSpace} guests each'
          : 'Up to ${area.capacityPerSpace} guests',
    if (area.hasFullServiceBar == true) 'Full-service bar',
  ].join(' · ');
}
