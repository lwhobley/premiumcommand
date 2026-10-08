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
import '../../events/domain/readiness.dart';
import '../domain/routing.dart';
import '../domain/service_request.dart';
import 'request_card.dart';
import 'request_dialogs.dart';

/// The signed-in user's open work across active events: requests named to them or to their departments.
class MyShiftScreen extends ConsumerStatefulWidget {
  const MyShiftScreen({super.key});

  @override
  ConsumerState<MyShiftScreen> createState() => _MyShiftScreenState();
}

class _MyShiftScreenState extends ConsumerState<MyShiftScreen> {
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
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
    final reason = await showReasonDialog(
      context,
      title: to == RequestStatus.blocked ? 'Why is this blocked?' : 'Why is this being rejected?',
    );
    if (reason == null) return;
    await _run(() => ref.read(dispatchActionsProvider).move(request, to: to, note: reason));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final snapshots = ref.watch(eventSnapshotsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Shift')),
      body: session == null
          ? const SizedBox.shrink()
          : snapshots.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text(userMessageFor(error))),
              data: (items) {
                final active = items
                    .map((s) => s.event)
                    .where((e) => e.status.isActive)
                    .toList();
                if (active.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No active events right now.', style: TextStyle(color: AppColors.charcoalMuted)),
                    ),
                  );
                }
                final departments = departmentsFor(session.roles);
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final event in active)
                      _ShiftSection(
                        event: event,
                        userId: session.userId,
                        departments: departments,
                        permissions: session.permissions,
                        now: _now,
                        onAdvance: (request, to) => _run(() => ref.read(dispatchActionsProvider).move(request, to: to)),
                        onWithReason: _withReason,
                        onAssign: _assign,
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _ShiftSection extends ConsumerWidget {
  const _ShiftSection({
    required this.event,
    required this.userId,
    required this.departments,
    required this.permissions,
    required this.now,
    required this.onAdvance,
    required this.onWithReason,
    required this.onAssign,
  });

  final OpsEvent event;
  final String userId;
  final Set<Department> departments;
  final Set<AppPermission> permissions;
  final DateTime now;
  final void Function(ServiceRequest request, RequestStatus to) onAdvance;
  final void Function(ServiceRequest request, RequestStatus to) onWithReason;
  final void Function(ServiceRequest request) onAssign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(eventRequestsProvider(event.id));
    final canWork = permissions.contains(AppPermission.manageRequests);
    final canManage = permissions.contains(AppPermission.manageEvents);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(event.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 8),
          requests.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            ),
            error: (error, _) => Text(userMessageFor(error)),
            data: (all) {
              final mine = requestsForShift(
                requests: all,
                userId: userId,
                departments: departments,
              )..sort((a, b) => compareForDispatch(a, b, now));
              if (mine.isEmpty) {
                return const Text('Nothing assigned to you right now.', style: TextStyle(color: AppColors.charcoalMuted));
              }
              return Column(
                children: [
                  for (final request in mine)
                    RequestCard(
                      request: request,
                      now: now,
                      canManage: canManage,
                      canWork: canWork,
                      onAdvance: (to) => onAdvance(request, to),
                      onAssign: () => onAssign(request),
                      onWithReason: (to) => onWithReason(request, to),
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
