import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/icons/phosphor.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/time/venue_time.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../auth/application/session_controller.dart';
import '../../events/application/event_providers.dart';
import '../../events/domain/ops_event.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../data/banquet_area_beo_repository.dart';
import '../../admin/domain/banquet_area.dart';

class BanquetAreaBeoLinksButton extends StatelessWidget {
  const BanquetAreaBeoLinksButton({
    super.key,
    required this.area,
    required this.venueId,
    required this.canManage,
    this.label = 'View area BEOs',
  });

  final BanquetArea area;
  final String venueId;
  final bool canManage;
  final String label;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: () => showBanquetAreaBeoLinks(
      context,
      area: area,
      venueId: venueId,
      canManage: canManage,
    ),
    icon: const PhosphorIcon(PhosphorIconsDuotone.fileText),
    label: Text(label),
  );
}

Future<void> showBanquetAreaBeoLinks(
  BuildContext context, {
  required BanquetArea area,
  required String venueId,
  required bool canManage,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BanquetAreaBeoLinksPanel(
      area: area,
      venueId: venueId,
      canManage: canManage,
    ),
  );
}

class _BanquetAreaBeoLinksPanel extends ConsumerStatefulWidget {
  const _BanquetAreaBeoLinksPanel({
    required this.area,
    required this.venueId,
    required this.canManage,
  });

  final BanquetArea area;
  final String venueId;
  final bool canManage;

  @override
  ConsumerState<_BanquetAreaBeoLinksPanel> createState() =>
      _BanquetAreaBeoLinksPanelState();
}

class _BanquetAreaBeoLinksPanelState
    extends ConsumerState<_BanquetAreaBeoLinksPanel> {
  String? _eventToLink;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final zone = ref.watch(sessionProvider)?.timeZone ?? 'UTC';
    final links = ref.watch(banquetAreaBeosProvider(widget.area.id));
    final events = ref.watch(eventSnapshotsProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpace.screen,
          AppSpace.l,
          AppSpace.screen,
          AppSpace.l + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.area.name} · Event BEOs',
                style: AppText.sectionHeading,
              ),
              const SizedBox(height: 4),
              const Text(
                'Each event has one BEO document. Open it to review the current order or preorder instructions.',
                style: AppText.meta,
              ),
              if (widget.canManage) ...[
                const SizedBox(height: 16),
                events.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text('$error'),
                  data: (snapshots) => links.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (error, _) => Text('$error'),
                    data: (items) {
                      final linkedIds = items
                          .map((link) => link.eventId)
                          .toSet();
                      final available = snapshots
                          .map((snapshot) => snapshot.event)
                          .where(
                            (event) =>
                                event.venueId == widget.venueId &&
                                event.status != EventStatus.cancelled &&
                                !linkedIds.contains(event.id),
                          )
                          .toList();
                      if (available.isEmpty) {
                        return const Text(
                          'All available events are linked to this area.',
                          style: AppText.meta,
                        );
                      }
                      final selected =
                          available.any((event) => event.id == _eventToLink)
                          ? _eventToLink
                          : available.first.id;
                      return Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selected,
                              decoration: const InputDecoration(
                                labelText: 'Link an event',
                              ),
                              items: [
                                for (final event in available)
                                  DropdownMenuItem(
                                    value: event.id,
                                    child: Text(
                                      '${event.name} · ${DateFormat('MMM d').format(atVenue(event.serviceStart, zone))}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _eventToLink = value),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _saving || selected == null
                                ? null
                                : () => _link(selected),
                            child: _saving
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Add'),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: links.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Text('$error'),
                  data: (items) => items.isEmpty
                      ? EmptyNote(
                          widget.canManage
                              ? 'No events are linked yet. Add an event above to connect its BEO to this area.'
                              : 'No event BEOs are linked to this area yet.',
                        )
                      : ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final link = items[index];
                            return OpenRow(
                              leading: const PhosphorIcon(
                                PhosphorIconsDuotone.fileText,
                              ),
                              title: link.beoTitle ?? link.eventName,
                              meta:
                                  '${DateFormat('EEE, MMM d · h:mm a').format(atVenue(link.serviceStart, zone))} $zone · '
                                  '${link.beoId == null ? 'No BEO created yet' : 'Event BEO available'}',
                              trailing: Wrap(
                                spacing: 0,
                                children: [
                                  IconButton(
                                    tooltip: link.beoId == null
                                        ? 'Create event BEO'
                                        : 'Open event BEO',
                                    onPressed: () => _openBeo(link.eventId),
                                    icon: const PhosphorIcon(
                                      PhosphorIconsDuotone.arrowSquareOut,
                                    ),
                                  ),
                                  if (widget.canManage)
                                    IconButton(
                                      tooltip: 'Unlink event',
                                      onPressed: () => _unlink(link.eventId),
                                      icon: const PhosphorIcon(
                                        PhosphorIconsDuotone.linkBreak,
                                      ),
                                    ),
                                ],
                              ),
                              onTap: () => _openBeo(link.eventId),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _link(String eventId) async {
    setState(() => _saving = true);
    final success = await runWrite(context, () async {
      await ref
          .read(banquetAreaBeoRepositoryProvider)
          .linkEvent(
            venueId: widget.venueId,
            areaId: widget.area.id,
            eventId: eventId,
          );
      ref.invalidate(banquetAreaBeosProvider(widget.area.id));
    }, success: 'Event linked to ${widget.area.name}.');
    if (mounted) setState(() => _saving = false);
    if (success && mounted) setState(() => _eventToLink = null);
  }

  Future<void> _unlink(String eventId) async {
    await runWrite(context, () async {
      await ref
          .read(banquetAreaBeoRepositoryProvider)
          .unlinkEvent(areaId: widget.area.id, eventId: eventId);
      ref.invalidate(banquetAreaBeosProvider(widget.area.id));
    }, success: 'Event unlinked from ${widget.area.name}.');
  }

  void _openBeo(String eventId) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go('/beo/event/$eventId');
  }
}
