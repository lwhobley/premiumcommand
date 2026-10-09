import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/application/session_controller.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../../operations/application/operations_providers.dart';
import '../../operations/domain/operations.dart';
import '../data/recap_pdf.dart';

/// Event closeout (recap, sign-offs, PDF) and cross-event trends.
class CloseoutScreen extends ConsumerWidget {
  const CloseoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!backendAvailable) return const BackendRequired(title: 'Event Closeout & Reports');

    final session = ref.watch(sessionProvider);
    final permissions = session?.permissions ?? const <AppPermission>{};
    final eventId = ref.watch(selectedEventIdProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Event Closeout & Reports'),
          bottom: const TabBar(tabs: [Tab(text: 'Closeout'), Tab(text: 'Trends')]),
        ),
        body: Column(
          children: [
            const EventPicker(),
            Expanded(
              child: TabBarView(
                children: [
                  eventId == null
                      ? const SizedBox.shrink()
                      : _CloseoutPanel(eventId: eventId, permissions: permissions),
                  const _Trends(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloseoutPanel extends ConsumerWidget {
  const _CloseoutPanel({required this.eventId, required this.permissions});

  final String eventId;
  final Set<AppPermission> permissions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final closeout = ref.watch(closeoutProvider(eventId));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        closeout.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text('$error'),
          data: (c) => _body(context, ref, c),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, Closeout? c) {
    final repo = ref.read(operationsRepositoryProvider);
    Future<void> run(Future<void> Function() action, String success) => runWrite(context, () async {
          await action();
          ref.invalidate(closeoutProvider(eventId));
          ref.invalidate(closeoutsProvider);
        }, success: success);

    if (c == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('No closeout yet. Starting one captures the recap as it stands now.'),
          const SizedBox(height: 12),
          if (permissions.contains(AppPermission.closeOutEvents))
            FilledButton(
              onPressed: () => run(() => repo.startCloseout(eventId), 'Closeout started.'),
              child: const Text('Start closeout'),
            ),
        ],
      );
    }

    final recap = c.recap;
    final tasks = (recap['tasks'] as Map?)?.cast<String, dynamic>() ?? const {};
    final requests = (recap['requests'] as Map?)?.cast<String, dynamic>() ?? const {};
    final inspections = (recap['inspections'] as Map?)?.cast<String, dynamic>() ?? const {};
    final canSubmit = c.status == 'open' && permissions.contains(AppPermission.closeOutEvents);
    final canManagerSign = c.status == 'submitted' && permissions.contains(AppPermission.manageEvents);
    final canDirectorSign = c.status == 'submitted' && c.managerSigned && !c.directorSigned &&
        permissions.contains(AppPermission.approveBeo);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Expanded(child: Text('Closeout status', style: TextStyle(fontWeight: FontWeight.w600))),
          StatusChip(
            label: c.status == 'signed' ? 'Signed' : c.status == 'submitted' ? 'Awaiting sign-off' : 'Open',
            color: c.status == 'signed' ? AppColors.ready : AppColors.attention,
          ),
        ]),
        const SizedBox(height: 12),
        _Metric(label: 'Required tasks', value: '${tasks['completed'] ?? 0} of ${tasks['required'] ?? 0}'),
        _Metric(label: 'Overdue tasks', value: '${tasks['overdue'] ?? 0}'),
        _Metric(label: 'Service requests', value: '${requests['completed'] ?? 0} of ${requests['total'] ?? 0} completed'),
        _Metric(label: 'Average response (min)', value: '${requests['avg_response_minutes'] ?? 0}'),
        _Metric(label: 'Failed inspection items', value: '${inspections['failed_items'] ?? 0}'),
        _Metric(label: 'Corrective actions', value: '${inspections['corrective_actions'] ?? 0}'),
        _Metric(label: 'Late deliveries', value: '${recap['late_deliveries'] ?? 0}'),
        _Metric(label: 'Incidents', value: '${recap['incidents'] ?? 0}'),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (canSubmit)
            FilledButton(
              onPressed: () => run(() => repo.signCloseout(eventId, 'submit'), 'Closeout submitted for sign-off.'),
              child: const Text('Submit for sign-off'),
            ),
          if (canManagerSign)
            FilledButton(
              onPressed: () => run(() => repo.signCloseout(eventId, 'manager'), 'Signed as event manager.'),
              child: const Text('Sign as event manager'),
            ),
          if (canDirectorSign)
            FilledButton(
              onPressed: () => run(() => repo.signCloseout(eventId, 'director'), 'Signed as director.'),
              child: const Text('Sign as director'),
            ),
          if (permissions.contains(AppPermission.viewReports))
            OutlinedButton.icon(
              onPressed: () => _export(context, c),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Export PDF'),
            ),
        ]),
        if (c.status == 'signed')
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('Signed. The event can now be closed in the Event Workspace.',
                style: TextStyle(color: AppColors.charcoalMuted)),
          ),
      ],
    );
  }

  Future<void> _export(BuildContext context, Closeout c) async {
    final bytes = await buildRecapPdf(c.recap, status: c.status);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'event-recap.pdf');
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(color: AppColors.charcoalMuted))),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _Trends extends ConsumerWidget {
  const _Trends();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final closeouts = ref.watch(closeoutsProvider);
    return closeouts.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (list) {
        if (list.isEmpty) {
          return const Center(child: Text('No closeouts yet. Trends appear once events are closed out.'));
        }
        final totalFailures = list.fold<int>(0, (s, c) => s + _n(c.recap, 'inspections', 'failed_items'));
        final totalLate = list.fold<int>(0, (s, c) => s + _int(c.recap['late_deliveries']));
        final totalIncidents = list.fold<int>(0, (s, c) => s + _int(c.recap['incidents']));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('${list.length} events · $totalFailures failed inspection items · '
                '$totalLate late deliveries · $totalIncidents incidents',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            for (final c in list)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text((c.recap['event'] as Map?)?['name']?.toString() ?? 'Event'),
                  subtitle: Text('${c.status} · ${_n(c.recap, 'tasks', 'completed')} of '
                      '${_n(c.recap, 'tasks', 'required')} tasks · '
                      '${_int(c.recap['late_deliveries'])} late deliveries'),
                ),
              ),
          ],
        );
      },
    );
  }

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  static int _n(Map<String, dynamic> recap, String group, String key) {
    final g = (recap[group] as Map?)?.cast<String, dynamic>() ?? const {};
    return _int(g[key]);
  }
}
