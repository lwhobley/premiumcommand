import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
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
    _clock = Timer.periodic(const Duration(seconds: 30), (_) => setState(() => _now = DateTime.now()));
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
      messenger.showSnackBar(SnackBar(content: Text(userMessageFor(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final permissions = session?.permissions ?? const <AppPermission>{};
    final canManage = permissions.contains(AppPermission.manageEvents);
    final canWork = permissions.contains(AppPermission.manageRequests);
    final snapshots = ref.watch(eventSnapshotsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Live Service Dispatch')),
      floatingActionButton: canWork && _eventId != null
          ? FloatingActionButton.extended(
              onPressed: () => _createRequest(),
              icon: const Icon(Icons.add),
              label: const Text('New request'),
            )
          : null,
      body: snapshots.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(userMessageFor(error))),
        data: (items) {
          final events = items
              .map((s) => s.event)
              .where((e) => e.status != EventStatus.closed && e.status != EventStatus.cancelled)
              .toList();
          if (events.isEmpty) {
            return const Center(child: Text('No open events to dispatch for.'));
          }
          _eventId ??= events.first.id;
          final selected = events.where((e) => e.id == _eventId).firstOrNull ?? events.first;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: DropdownButtonFormField<String>(
                  initialValue: selected.id,
                  decoration: const InputDecoration(labelText: 'Event'),
                  items: [
                    for (final e in events) DropdownMenuItem(value: e.id, child: Text(e.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (value) => setState(() => _eventId = value),
                ),
              ),
              Expanded(child: _Board(
                eventId: selected.id,
                now: _now,
                canManage: canManage,
                canWork: canWork,
                onAdvance: (request, to) => _run(() => ref.read(dispatchActionsProvider).move(request, to: to)),
                onAssign: (request) => _assign(request),
                onWithReason: (request, to) => _withReason(request, to),
              )),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createRequest() async {
    final draft = await showNewRequestDialog(context);
    if (draft == null || _eventId == null) return;
    await _run(() async {
      await ref.read(dispatchActionsProvider).create(_eventId!, draft);
    });
  }

  Future<void> _assign(ServiceRequest request) async {
    final dept = await showAssignDialog(context);
    if (dept == null) return;
    await _run(() => ref.read(dispatchActionsProvider).move(
          request,
          to: RequestStatus.assigned,
          department: dept.code,
        ));
  }

  Future<void> _withReason(ServiceRequest request, RequestStatus to) async {
    final title = switch (to) {
      RequestStatus.blocked => 'Why is this blocked?',
      RequestStatus.rejected => 'Why is this being rejected?',
      _ => 'Why is this being cancelled?',
    };
    final reason = await showReasonDialog(context, title: title);
    if (reason == null) return;
    await _run(() => ref.read(dispatchActionsProvider).move(request, to: to, note: reason));
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
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(userMessageFor(error))),
      data: (all) {
        final open = all.where((r) => r.status.isOpen).toList()
          ..sort((a, b) => compareForDispatch(a, b, now, thresholds));
        final closed = all.where((r) => r.status.isTerminal).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final escalatedCount = open.where((r) => r.isEscalated(now, thresholds)).length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${open.length} open${escalatedCount > 0 ? ' · $escalatedCount escalated' : ''}',
                style: TextStyle(
                  color: escalatedCount > 0 ? AppColors.blocked : AppColors.charcoalMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (open.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No open requests.', style: TextStyle(color: AppColors.charcoalMuted)),
              ),
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
              const Padding(
                padding: EdgeInsets.only(top: 16, bottom: 8),
                child: Text('Closed', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
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
