import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../../core/widgets/tag.dart';
import '../../auth/application/session_controller.dart';
import '../../dispatch/application/dispatch_providers.dart';
import '../../dispatch/data/dispatch_repository.dart';
import '../../dispatch/domain/service_request.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../../suites/domain/suite.dart';
import '../application/guest_service_providers.dart';
import '../domain/guest_service.dart';
import 'guest_preference_sheet.dart';

/// The guest service desk: one-tap requests per suite, comps, and the runner's location status.
class GuestServiceScreen extends ConsumerWidget {
  const GuestServiceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!backendAvailable) {
      return const BackendRequired(title: 'Guest Service');
    }
    final eventId = ref.watch(selectedEventIdProvider);
    // Watched here so location sharing starts whenever the runner is on this screen or the shell.
    final sharing = ref.watch(runnerLocationSharingProvider);
    return PageScaffold(
      kicker: 'Service',
      title: 'Guest Service',
      children: [
        const EventPicker(),
        if (sharing != null) ...[
          Text(sharing, style: AppText.meta),
          const SizedBox(height: AppSpace.m),
        ],
        if (eventId != null) _ServiceBody(eventId: eventId),
      ],
    );
  }
}

class _ServiceBody extends ConsumerWidget {
  const _ServiceBody({required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final permissions = session?.permissions ?? const <AppPermission>{};
    final canRequest = permissions.contains(AppPermission.manageRequests);
    final canDecide =
        permissions.contains(AppPermission.manageEvents) ||
        permissions.contains(AppPermission.manageConfiguration);
    final suites = ref.watch(suitesProvider(eventId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading('Suites'),
        suites.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text(userMessageFor(error), style: AppText.body),
          data: (items) {
            final tiles = items
                .where((s) => s.state != SuiteState.closed)
                .toList();
            if (tiles.isEmpty) {
              return const EmptyNote('No suites assigned to this event yet.');
            }
            return Column(
              children: [
                for (final suite in tiles)
                  _SuiteServiceRow(
                    eventId: eventId,
                    suite: suite,
                    canRequest: canRequest,
                    canEditPreferences: canRequest,
                  ),
              ],
            );
          },
        ),
        const SectionHeading('Comps'),
        if (canRequest)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () => _requestComp(context, ref, eventId),
              child: const Text('Request a comp'),
            ),
          ),
        const SizedBox(height: AppSpace.s),
        _CompList(eventId: eventId, canDecide: canDecide),
      ],
    );
  }

  Future<void> _requestComp(
    BuildContext context,
    WidgetRef ref,
    String eventId,
  ) async {
    final request = await showModalBottomSheet<_CompDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CompRequestSheet(),
    );
    if (request == null || !context.mounted) return;
    final session = ref.read(sessionProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(guestServiceRepositoryProvider)
          .requestComp(
            venueId: session?.venueId ?? '',
            eventId: eventId,
            amountCents: request.amountCents,
            reason: request.reason,
          );
      ref.invalidate(eventCompsProvider(eventId));
      messenger.showSnackBar(
        const SnackBar(content: Text('Comp sent for approval.')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(userMessageFor(error))));
    }
  }
}

/// One suite with one-tap service buttons. Each tap sends a request straight to dispatch.
class _SuiteServiceRow extends ConsumerWidget {
  const _SuiteServiceRow({
    required this.eventId,
    required this.suite,
    required this.canRequest,
    required this.canEditPreferences,
  });

  final String eventId;
  final SuiteAssignment suite;
  final bool canRequest;
  final bool canEditPreferences;

  static const _quick = [
    (RequestCategory.ice, 'Ice'),
    (RequestCategory.beverageReplenishment, 'Drinks'),
    (RequestCategory.glassware, 'Glassware'),
    (RequestCategory.cleanup, 'Cleanup'),
    (RequestCategory.guestAssistance, 'Guest help'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.row),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              suite.suiteName,
              style: AppText.body.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 8,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (category, label) in _quick)
                  OutlinedButton(
                    onPressed: canRequest
                        ? () => _send(context, ref, category, label)
                        : null,
                    child: Text(label),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Preference card',
            onPressed: () => showGuestPreferenceSheet(
              context,
              venueId: ref.read(sessionProvider)?.venueId ?? '',
              eventId: eventId,
              suiteAssignmentId: suite.id,
              suiteName: suite.suiteName,
              canEdit: canEditPreferences,
            ),
            icon: const Icon(Icons.assignment_outlined),
          ),
        ],
      ),
    );
  }

  Future<void> _send(
    BuildContext context,
    WidgetRef ref,
    RequestCategory category,
    String label,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final draft = ServiceRequestDraft(
      clientRequestId: newClientRequestId(),
      category: category,
      location: suite.suiteName,
      description: '$label for ${suite.suiteName}',
      priority: RequestPriority.normal,
    );
    try {
      await ref.read(dispatchActionsProvider).create(eventId, draft);
      messenger.showSnackBar(
        SnackBar(content: Text('$label requested for ${suite.suiteName}.')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(userMessageFor(error))));
    }
  }
}

class _CompList extends ConsumerWidget {
  const _CompList({required this.eventId, required this.canDecide});

  final String eventId;
  final bool canDecide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comps = ref.watch(eventCompsProvider(eventId));
    return comps.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Text(userMessageFor(error), style: AppText.body),
      data: (items) {
        if (items.isEmpty) {
          return const EmptyNote('No comps requested for this event.');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final comp in items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.row),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '\$${(comp.amountCents / 100).toStringAsFixed(2)} · ${comp.reason}',
                            style: AppText.body,
                          ),
                        ),
                        Tag(
                          comp.status.label,
                          comp.status == CompStatus.approved
                              ? Tone.accent
                              : Tone.neutral,
                        ),
                      ],
                    ),
                    if (comp.status == CompStatus.pending && canDecide)
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => _decide(
                              context,
                              ref,
                              comp,
                              CompStatus.approved,
                            ),
                            child: const Text('Approve'),
                          ),
                          TextButton(
                            onPressed: () => _decide(
                              context,
                              ref,
                              comp,
                              CompStatus.rejected,
                            ),
                            child: const Text('Reject'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    Comp comp,
    CompStatus decision,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(guestServiceRepositoryProvider)
          .decideComp(
            comp.id,
            decision: decision,
            expectedVersion: comp.version,
          );
      ref.invalidate(eventCompsProvider(eventId));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(userMessageFor(error))));
    }
  }
}

class _CompDraft {
  const _CompDraft({required this.amountCents, required this.reason});

  final int amountCents;
  final String reason;
}

class _CompRequestSheet extends StatefulWidget {
  const _CompRequestSheet();

  @override
  State<_CompRequestSheet> createState() => _CompRequestSheetState();
}

class _CompRequestSheetState extends State<_CompRequestSheet> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final cents = parseDollarsToCents(_amount.text);
    if (cents == null) {
      setState(() => _error = 'Enter an amount such as 12.50.');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Give a reason for the comp.');
      return;
    }
    Navigator.of(context)
        .pop(_CompDraft(amountCents: cents, reason: _reason.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpace.screen,
          AppSpace.screen,
          AppSpace.screen,
          MediaQuery.viewInsetsOf(context).bottom + AppSpace.screen,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Request a comp',
              style: AppText.body.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpace.m),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Amount (\$)'),
            ),
            const SizedBox(height: AppSpace.s),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpace.s),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.accent2700),
              ),
            ],
            const SizedBox(height: AppSpace.m),
            FilledButton(
              onPressed: _submit,
              child: const Text('Send for approval'),
            ),
          ],
        ),
      ),
    );
  }
}
