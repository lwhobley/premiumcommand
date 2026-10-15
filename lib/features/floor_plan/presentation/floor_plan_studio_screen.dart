import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/session_controller.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../application/floor_plan_providers.dart';
import '../data/floor_plan_pdf.dart';
import '../domain/floor_plan.dart';
import 'banquet_area_3d_overview.dart';
import 'floor_plan_3d_view.dart';

/// Floor Plan Studio: measure a venue space, generate a round-table layout for a
/// guest count, save it, and preview it in 3D. One floor plan per venue space.
class FloorPlanStudioScreen extends ConsumerWidget {
  const FloorPlanStudioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!backendAvailable) {
      return const BackendRequired(title: 'Floor Plan Studio');
    }

    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final spacesAsync = ref.watch(venueSpacesProvider(session.venueId));

    return Scaffold(
      appBar: AppBar(title: const Text('Floor Plan Studio')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          BanquetArea3DOverview(
            venueId: session.venueId,
            canManageAreaLinks: session.permissions.contains(
              AppPermission.manageEvents,
            ),
          ),
          const Divider(height: 40),
          Text(
            'Measured floor plans',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter measured width and depth before generating a seating layout. Square footage alone does not establish a room shape.',
            style: TextStyle(color: AppColors.charcoalMuted),
          ),
          const SizedBox(height: 12),
          spacesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('$error')),
            data: (spaces) {
              if (spaces.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No individually named spaces are configured for measured floor plans yet.',
                    style: TextStyle(color: AppColors.charcoalMuted),
                  ),
                );
              }
              final selectedId = ref.watch(selectedVenueSpaceIdProvider);
              final current = spaces.any((s) => s.id == selectedId)
                  ? selectedId!
                  : spaces.first.id;
              if (current != selectedId) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  ref
                      .read(selectedVenueSpaceIdProvider.notifier)
                      .select(current);
                });
              }
              final canEdit = (session.permissions).contains(
                AppPermission.manageConfiguration,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: current,
                    decoration: const InputDecoration(labelText: 'Venue space'),
                    items: [
                      for (final s in spaces)
                        DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                    onChanged: (value) => ref
                        .read(selectedVenueSpaceIdProvider.notifier)
                        .select(value),
                  ),
                  const SizedBox(height: 16),
                  _FloorPlanEditor(
                    key: ValueKey(current),
                    venueId: session.venueId,
                    venueSpaceId: current,
                    spaceName: spaces.firstWhere((s) => s.id == current).name,
                    venueName: session.venueName,
                    canEdit: canEdit,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FloorPlanEditor extends ConsumerStatefulWidget {
  const _FloorPlanEditor({
    super.key,
    required this.venueId,
    required this.venueSpaceId,
    required this.spaceName,
    required this.venueName,
    required this.canEdit,
  });

  final String venueId;
  final String venueSpaceId;
  final String spaceName;
  final String venueName;
  final bool canEdit;

  @override
  ConsumerState<_FloorPlanEditor> createState() => _FloorPlanEditorState();
}

class _FloorPlanEditorState extends ConsumerState<_FloorPlanEditor> {
  final _width = TextEditingController();
  final _depth = TextEditingController();
  final _guests = TextEditingController();
  var _verified = false;
  List<FloorPlanOption> _options = const [];
  int _selectedOption = 0;
  String? _error;
  var _loaded = false;
  var _show3D = false;

  @override
  void dispose() {
    _width.dispose();
    _depth.dispose();
    _guests.dispose();
    super.dispose();
  }

  void _loadFrom(VenueSpaceFloorPlan? plan) {
    if (_loaded) return;
    _loaded = true;
    if (plan == null) return;
    _width.text = plan.widthFeet.toStringAsFixed(1);
    _depth.text = plan.depthFeet.toStringAsFixed(1);
    _verified = plan.verified;
  }

  void _generate(VenueSpaceFloorPlan? existing) {
    final width = double.tryParse(_width.text);
    final depth = double.tryParse(_depth.text);
    final guests = int.tryParse(_guests.text);
    if (width == null || depth == null || guests == null) {
      setState(() => _error = 'Enter room width, depth, and a guest count.');
      return;
    }
    try {
      final options = generateRoundTableLayouts(
        widthFeet: width,
        depthFeet: depth,
        guestCount: guests,
        tableDiameterFeet:
            existing?.tableDiameterFeet ?? defaultTableDiameterFeet,
        seatsPerTable: existing?.seatsPerTable ?? defaultSeatsPerTable,
      );
      setState(() {
        _options = options;
        _selectedOption = 0;
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() {
        _options = const [];
        _error = e.message;
      });
    }
  }

  Future<void> _save(VenueSpaceFloorPlan? existing) async {
    final width = double.tryParse(_width.text);
    final depth = double.tryParse(_depth.text);
    if (width == null || depth == null) {
      setState(() => _error = 'Enter room width and depth.');
      return;
    }
    if (_options.isEmpty) {
      setState(() => _error = 'Generate a layout before saving.');
      return;
    }
    final plan = VenueSpaceFloorPlan(
      venueId: widget.venueId,
      venueSpaceId: widget.venueSpaceId,
      widthFeet: width,
      depthFeet: depth,
      verified: _verified,
      tableDiameterFeet:
          existing?.tableDiameterFeet ?? defaultTableDiameterFeet,
      seatsPerTable: existing?.seatsPerTable ?? defaultSeatsPerTable,
      tables: _options[_selectedOption].tables,
    );
    final issues = validateFloorPlanLayout(plan);
    if (issues.isNotEmpty) {
      setState(() => _error = issues.join(' '));
      return;
    }
    await runWrite(context, () async {
      await ref
          .read(floorPlanRepositoryProvider)
          .saveFloorPlan(widget.venueId, plan);
      ref.invalidate(floorPlanProvider(widget.venueSpaceId));
    }, success: 'Floor plan saved.');
  }

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(floorPlanProvider(widget.venueSpaceId));
    return planAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text('$error'),
      data: (existing) {
        _loadFrom(existing);
        final previewTables = _options.isNotEmpty
            ? _options[_selectedOption].tables
            : existing?.tables ?? const [];
        final previewPlan = VenueSpaceFloorPlan(
          venueId: widget.venueId,
          venueSpaceId: widget.venueSpaceId,
          widthFeet: double.tryParse(_width.text) ?? existing?.widthFeet ?? 0,
          depthFeet: double.tryParse(_depth.text) ?? existing?.depthFeet ?? 0,
          verified: _verified,
          tableDiameterFeet:
              existing?.tableDiameterFeet ?? defaultTableDiameterFeet,
          seatsPerTable: existing?.seatsPerTable ?? defaultSeatsPerTable,
          tables: previewTables,
        );
        final issues = previewTables.isEmpty
            ? const <String>[]
            : validateFloorPlanLayout(previewPlan);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (existing != null) ...[
              OutlinedButton.icon(
                onPressed: () => shareFloorPlanPdf(
                  spaceName: widget.spaceName,
                  plan: existing,
                  venueName: widget.venueName,
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Export floor plan PDF'),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _width,
                    enabled: widget.canEdit,
                    onChanged: (_) => setState(() {
                      _options = const [];
                      _error = null;
                    }),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Width (feet)',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _depth,
                    enabled: widget.canEdit,
                    onChanged: (_) => setState(() {
                      _options = const [];
                      _error = null;
                    }),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Depth (feet)',
                    ),
                  ),
                ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _verified,
              onChanged: widget.canEdit
                  ? (value) => setState(() => _verified = value ?? false)
                  : null,
              title: const Text('I verified these measurements'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _guests,
                    enabled: widget.canEdit,
                    onChanged: (_) => setState(() {
                      _options = const [];
                      _error = null;
                    }),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Guest count for layout',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: widget.canEdit ? () => _generate(existing) : null,
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Generate layouts'),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.blocked),
                ),
              ),
            if (_options.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Compare layouts'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < _options.length; i++)
                    _LayoutOptionPreview(
                      option: _options[i],
                      widthFeet: previewPlan.widthFeet,
                      depthFeet: previewPlan.depthFeet,
                      selected: _selectedOption == i,
                      onTap: () => setState(() => _selectedOption = i),
                    ),
                ],
              ),
            ],
            if (previewTables.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                issues.isEmpty
                    ? 'No table boundary or clearance conflicts detected.'
                    : issues.join('\n'),
                style: TextStyle(
                  color: issues.isEmpty ? AppColors.ready : AppColors.blocked,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed:
                    widget.canEdit && _options.isNotEmpty && issues.isEmpty
                    ? () => _save(existing)
                    : null,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save floor plan'),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => setState(() => _show3D = !_show3D),
                icon: const Icon(Icons.view_in_ar_outlined),
                label: Text(_show3D ? 'Hide 3D preview' : 'Show 3D preview'),
              ),
              if (_show3D) ...[
                const SizedBox(height: 10),
                FloorPlan3DView(
                  sceneData: buildFloorPlanSceneData(
                    plan: previewPlan,
                    guestCount:
                        int.tryParse(_guests.text) ??
                        previewTables.length * previewPlan.seatsPerTable,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '3D preview is an illustrative render of this layout, not a photograph. '
                  'People and food are stylized placeholders, not the actual guests or menu.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.charcoalMuted,
                  ),
                ),
              ],
            ] else if (existing == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Enter the room measurements and a guest count, then generate layouts.',
                  style: TextStyle(color: AppColors.charcoalMuted),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LayoutOptionPreview extends StatelessWidget {
  const _LayoutOptionPreview({
    required this.option,
    required this.widthFeet,
    required this.depthFeet,
    required this.selected,
    required this.onTap,
  });

  final FloorPlanOption option;
  final double widthFeet;
  final double depthFeet;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 184,
    child: Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(option.name, style: Theme.of(context).textTheme.labelLarge),
              Text('${option.tables.length} tables'),
              const SizedBox(height: 8),
              SizedBox(
                height: 112,
                width: double.infinity,
                child: CustomPaint(
                  painter: _LayoutPreviewPainter(
                    tables: option.tables,
                    widthFeet: widthFeet,
                    depthFeet: depthFeet,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _LayoutPreviewPainter extends CustomPainter {
  const _LayoutPreviewPainter({
    required this.tables,
    required this.widthFeet,
    required this.depthFeet,
    required this.color,
  });

  final List<FloorPlanTable> tables;
  final double widthFeet;
  final double depthFeet;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (widthFeet <= 0 || depthFeet <= 0) return;
    const inset = 6.0;
    final scale = math.min(
      (size.width - inset * 2) / widthFeet,
      (size.height - inset * 2) / depthFeet,
    );
    final room = Size(widthFeet * scale, depthFeet * scale);
    final left = (size.width - room.width) / 2;
    final top = (size.height - room.height) / 2;
    canvas.drawRect(
      Rect.fromLTWH(left, top, room.width, room.height),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    for (final table in tables) {
      canvas.drawCircle(
        Offset(left + table.x * scale, top + table.y * scale),
        math.min(8.0, math.max(2.0, defaultTableDiameterFeet * scale / 2)),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LayoutPreviewPainter oldDelegate) =>
      oldDelegate.tables != tables ||
      oldDelegate.widthFeet != widthFeet ||
      oldDelegate.depthFeet != depthFeet ||
      oldDelegate.color != color;
}
