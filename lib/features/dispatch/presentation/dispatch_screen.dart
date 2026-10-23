import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/icons/phosphor.dart';
import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../auth/application/session_controller.dart';
import '../../events/application/event_providers.dart';
import '../../events/domain/ops_event.dart';
import '../application/dispatch_providers.dart';
import '../domain/routing.dart';
import '../domain/service_request.dart';
import 'request_card.dart';
import 'request_dialogs.dart';

/// Live service dispatch board for one event at a time.
class DispatchScreen extends ConsumerStatefulWidget {
  const DispatchScreen({super.key});

  @override
  ConsumerState<DispatchScreen> createState() => _DispatchScreenState();
}

class _DispatchScreenState extends ConsumerState<DispatchScreen> {
  String? _eventId;
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Re-evaluates escalation while the board is open, without needing a data change.
    _clock = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(userMessageFor(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final permissions = session?.permissions ?? const <AppPermission>{};
    final canManage = permissions.contains(AppPermission.manageEvents);
    final canWork = permissions.contains(AppPermission.manageRequests);
    final snapshots = ref.watch(eventSnapshotsProvider);

    return PageScaffold(
      kicker: 'Live service',
      title: 'Live Service Dispatch',
      floatingActionButton: canWork && _eventId != null
          ? FloatingActionButton.extended(
              onPressed: () => _createRequest(),
              icon: const PhosphorIcon(PhosphorIconsDuotone.plus),
              label: const Text('New request'),
            )
          : null,
      children: snapshots.when(
        loading: () => const [LinearProgressIndicator()],
        error: (error, _) => [Text(userMessageFor(error), style: AppText.body)],
        data: (items) {
          final events = items
              .map((s) => s.event)
              .where(
                (e) =>
                    e.status != EventStatus.closed &&
                    e.status != EventStatus.cancelled,
              )
              .toList();
          if (events.isEmpty) {
            return const [EmptyNote('No open events to dispatch for.')];
          }
          _eventId ??= events.first.id;
          final selected =
              events.where((e) => e.id == _eventId).firstOrNull ?? events.first;
          _eventId = selected.id;
          return [
            DropdownButtonFormField<String>(
              initialValue: selected.id,
              decoration: const InputDecoration(labelText: 'Event'),
              items: [
                for (final e in events)
                  DropdownMenuItem(
                    value: e.id,
                    child: Text(e.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _eventId = value),
            ),
            const SizedBox(height: AppSpace.l),
            _Board(
              eventId: selected.id,
              now: _now,
              canManage: canManage,
              canWork: canWork,
              onAdvance: (request, to) => _run(
                () => ref.read(dispatchActionsProvider).move(request, to: to),
              ),
              onAssign: (request) => _assign(request),
              onWithReason: (request, to) => _withReason(request, to),
            ),
          ];
        },
      ),
    );
  }

  Future<void> _createRequest() async {
    final draft = await showNewRequestDialog(context);
    if (draft == null || !mounted || _eventId == null) return;
    final eventId = _eventId!;
    await _run(() async {
      await ref.read(dispatchActionsProvider).create(eventId, draft);
    });
  }

  Future<void> _assign(ServiceRequest request) async {
    final dept = await showAssignDialog(context);
    if (dept == null || !mounted) return;
    await _run(
      () => ref
          .read(dispatchActionsProvider)
          .move(request, to: RequestStatus.assigned, department: dept.code),
    );
  }

  Future<void> _withReason(ServiceRequest request, RequestStatus to) async {
    final title = switch (to) {
      RequestStatus.blocked => 'Why is this blocked?',
      RequestStatus.rejected => 'Why is this being rejected?',
      _ => 'Why is this being cancelled?',
    };
    final reason = await showReasonDialog(context, title: title);
    if (reason == null || !mounted) return;
    await _run(
      () =>
          ref.read(dispatchActionsProvider).move(request, to: to, note: reason),
    );
  }
}

class _Board extends ConsumerWidget {
  const _Board({
    required this.eventId,
    required this.now,
    required this.canManage,
    required this.canWork,
    required this.onAdvance,
    required this.onAssign,
    required this.onWithReason,
  });

  final String eventId;
  final DateTime now;
  final bool canManage;
  final bool canWork;
  final void Function(ServiceRequest request, RequestStatus to) onAdvance;
  final void Function(ServiceRequest request) onAssign;
  final void Function(ServiceRequest request, RequestStatus to) onWithReason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(eventRequestsProvider(eventId));
    final thresholds = ref.watch(escalationThresholdsProvider).value;

    return requests.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Text(userMessageFor(error), style: AppText.body),
      data: (all) {
        final open = all.where((r) => r.status.isOpen).toList()
          ..sort((a, b) => compareForDispatch(a, b, now, thresholds));
        final closed = all.where((r) => r.status.isTerminal).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final escalated = escalatedCount(open, now, thresholds);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${open.length} open${escalated > 0 ? ' · $escalated escalated' : ''}',
                style: AppText.meta.copyWith(
                  color: escalated > 0 ? AppColors.accent2700 : AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (open.isEmpty) const EmptyNote('No open requests.'),
            for (final request in open)
              RequestCard(
                request: request,
                now: now,
                canManage: canManage,
                canWork: canWork,
                onAdvance: (to) => onAdvance(request, to),
                onAssign: () => onAssign(request),
                thresholds: thresholds,
                onWithReason: (to) => onWithReason(request, to),
              ),
            if (closed.isNotEmpty) ...[
              const SectionHeading('Closed'),
              for (final request in closed.take(10))
                RequestCard(
                  request: request,
                  now: now,
                  canManage: false,
                  canWork: false,
                  onAdvance: (_) {},
                  onAssign: () {},
                  onWithReason: (_) {},
                ),
            ],
          ],
        );
      },
    );
  }
}
