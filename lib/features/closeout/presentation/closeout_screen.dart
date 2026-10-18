import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/icons/phosphor.dart';

import 'package:printing/printing.dart';

import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../../core/widgets/tag.dart';
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
    if (!backendAvailable) {
      return const BackendRequired(title: 'Event Closeout & Reports');
    }

    final session = ref.watch(sessionProvider);
    final permissions = session?.permissions ?? const <AppPermission>{};
    final eventId = ref.watch(selectedEventIdProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ScreenHeader(
                kicker: 'Reports',
                title: 'Event Closeout & Reports',
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpace.screen - 16),
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'Closeout'),
                    Tab(text: 'Trends'),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpace.screen,
                  AppSpace.m,
                  AppSpace.screen,
                  0,
                ),
                child: EventPicker(),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    eventId == null
                        ? const SizedBox.shrink()
                        : _CloseoutPanel(
                            eventId: eventId,
                            permissions: permissions,
                          ),
                    const _Trends(),
                  ],
                ),
              ),
            ],
          ),
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
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screen,
        AppSpace.l,
        AppSpace.screen,
        96,
      ),
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
    Future<void> run(Future<void> Function() action, String success) =>
        runWrite(context, () async {
          await action();
          ref.invalidate(closeoutProvider(eventId));
          ref.invalidate(closeoutsProvider);
        }, success: success);

    if (c == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No closeout yet. Starting one captures the recap as it stands now.',
            style: AppText.body,
          ),
          const SizedBox(height: 12),
          if (permissions.contains(AppPermission.closeOutEvents))
            FilledButton(
              onPressed: () =>
                  run(() => repo.startCloseout(eventId), 'Closeout started.'),
              child: const Text('Start closeout'),
            ),
        ],
      );
    }

    final recap = c.recap;
    final tasks = (recap['tasks'] as Map?)?.cast<String, dynamic>() ?? const {};
    final requests =
        (recap['requests'] as Map?)?.cast<String, dynamic>() ?? const {};
    final inspections =
        (recap['inspections'] as Map?)?.cast<String, dynamic>() ?? const {};
    final canSubmit =
        c.status == 'open' &&
        permissions.contains(AppPermission.closeOutEvents);
    final canManagerSign =
        c.status == 'submitted' &&
        permissions.contains(AppPermission.manageEvents);
    final canDirectorSign =
        c.status == 'submitted' &&
        c.managerSigned &&
        !c.directorSigned &&
        permissions.contains(AppPermission.approveBeo);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'Closeout status',
          first: true,
          trailing: Tag(
            c.status == 'signed'
                ? 'Signed'
                : c.status == 'submitted'
                ? 'Awaiting sign-off'
                : 'Open',
            c.status == 'signed' ? Tone.accent : Tone.neutral,
          ),
        ),
        FactGrid(
          facts: [
            (
              'Required tasks',
              '${tasks['completed'] ?? 0} of ${tasks['required'] ?? 0}',
            ),
            (
              'Service requests',
              '${requests['completed'] ?? 0} of ${requests['total'] ?? 0} completed',
            ),
          ],
        ),
        const SizedBox(height: AppSpace.l),
        MetricGrid(
          metrics: [
            Metric(
              label: 'Overdue tasks',
              value: '${tasks['overdue'] ?? 0}',
              alert: _positive(tasks['overdue']),
            ),
            Metric(
              label: 'Average response (min)',
              value: '${requests['avg_response_minutes'] ?? 0}',
            ),
            Metric(
              label: 'Failed inspection items',
              value: '${inspections['failed_items'] ?? 0}',
              alert: _positive(inspections['failed_items']),
            ),
            Metric(
              label: 'Corrective actions',
              value: '${inspections['corrective_actions'] ?? 0}',
            ),
            Metric(
              label: 'Late deliveries',
              value: '${recap['late_deliveries'] ?? 0}',
              alert: _positive(recap['late_deliveries']),
            ),
            Metric(label: 'Incidents', value: '${recap['incidents'] ?? 0}'),
          ],
        ),
        const SizedBox(height: AppSpace.section),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (canSubmit)
              FilledButton(
                onPressed: () => run(
                  () => repo.signCloseout(eventId, 'submit'),
                  'Closeout submitted for sign-off.',
                ),
                child: const Text('Submit for sign-off'),
              ),
            if (canManagerSign)
              FilledButton(
                onPressed: () => run(
                  () => repo.signCloseout(eventId, 'manager'),
                  'Signed as event manager.',
                ),
                child: const Text('Sign as event manager'),
              ),
            if (canDirectorSign)
              FilledButton(
                onPressed: () => run(
                  () => repo.signCloseout(eventId, 'director'),
                  'Signed as director.',
                ),
                child: const Text('Sign as director'),
              ),
            if (permissions.contains(AppPermission.viewReports))
              OutlinedButton.icon(
                onPressed: () => _export(context, ref, c),
                icon: const PhosphorIcon(PhosphorIconsDuotone.filePdf),
                label: const Text('Export PDF'),
              ),
          ],
        ),
        if (c.status == 'signed')
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Signed. The event can now be closed in the Event Workspace.',
              style: AppText.meta,
            ),
          ),
      ],
    );
  }

  static bool _positive(Object? v) => v is num && v > 0;

  Future<void> _export(BuildContext context, WidgetRef ref, Closeout c) async {
    final bytes = await buildRecapPdf(
      c.recap,
      status: c.status,
      timeZone: ref.read(sessionProvider)?.timeZone ?? 'UTC',
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'event-recap.pdf',
    );
  }
}

class _Trends extends ConsumerWidget {
  const _Trends();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final closeouts = ref.watch(closeoutsProvider);
    const padding = EdgeInsets.fromLTRB(
      AppSpace.screen,
      AppSpace.l,
      AppSpace.screen,
      96,
    );
    return closeouts.when(
      loading: () => const Align(
        alignment: Alignment.topCenter,
        child: LinearProgressIndicator(),
      ),
      error: (error, _) =>
          ListView(padding: padding, children: [Text('$error')]),
      data: (list) {
        if (list.isEmpty) {
          return ListView(
            padding: padding,
            children: const [
              EmptyNote(
                'No closeouts yet. Trends appear once events are closed out.',
              ),
            ],
          );
        }
        final totalFailures = list.fold<int>(
          0,
          (s, c) => s + _n(c.recap, 'inspections', 'failed_items'),
        );
        final totalLate = list.fold<int>(
          0,
          (s, c) => s + _int(c.recap['late_deliveries']),
        );
        final totalIncidents = list.fold<int>(
          0,
          (s, c) => s + _int(c.recap['incidents']),
        );
        return ListView(
          padding: padding,
          children: [
            Text(
              '${list.length} events · $totalFailures failed inspection items · '
              '$totalLate late deliveries · $totalIncidents incidents',
              style: AppText.body.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpace.m),
            for (final c in list)
              OpenRow(
                title:
                    (c.recap['event'] as Map?)?['name']?.toString() ?? 'Event',
                meta:
                    '${c.status} · ${_n(c.recap, 'tasks', 'completed')} of '
                    '${_n(c.recap, 'tasks', 'required')} tasks · '
                    '${_int(c.recap['late_deliveries'])} late deliveries',
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
