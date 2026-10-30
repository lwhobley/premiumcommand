import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_section.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/icons/phosphor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../../core/widgets/tag.dart';
import '../../auth/application/session_controller.dart';
import '../../planning/application/planning_providers.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../../suites/application/service_day_providers.dart';
import '../../suites/presentation/service_day_picker.dart';
import '../domain/beo.dart';
import '../domain/beo_day.dart';

/// The event's BEO on the workspace: what it schedules, serves and pours on the chosen day,
/// with a link to the full BEO. Shares the day picked on Premium Spaces.
class EventBeoCard extends ConsumerWidget {
  const EventBeoCard({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!backendAvailable) return const SizedBox.shrink();
    final permissions = ref.watch(sessionProvider)?.permissions ?? const {};
    // The same people who can open BEO Management.
    if (!AppSection.beoManagement.allows(permissions)) {
      return const SizedBox.shrink();
    }
    final beo = ref.watch(beoProvider(eventId));
    final day = ref.watch(selectedServiceDayProvider(eventId));
    final days = ref.watch(eventServiceDaysProvider(eventId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'BEO',
          trailing: TextButton.icon(
            onPressed: () => context.push('/beo/event/$eventId'),
            icon: const PhosphorIcon(PhosphorIconsDuotone.fileText),
            label: const Text('Open BEO'),
          ),
        ),
        beo.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Text(userMessageFor(error)),
          data: (bundle) {
            // The approved revision is what staff work from; a newer draft is flagged.
            final shown = bundle?.approved ?? bundle?.latest;
            if (bundle == null || shown == null) {
              return const EmptyNote('No BEO for this event yet.');
            }
            final pending = bundle.latest?.status == RevisionStatus.draft
                ? bundle.latest
                : null;
            final parts = day == null ? null : beoDay(shown.content, day, days);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ServiceDayPicker(eventId: eventId),
                Wrap(
                  spacing: AppSpace.s,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      bundle.title,
                      style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    shown.status == RevisionStatus.approved
                        ? Tag(
                            'Approved · revision ${shown.revisionNo}',
                            Tone.accent,
                          )
                        : Tag(
                            'Awaiting approval · revision ${shown.revisionNo}',
                            Tone.neutral,
                          ),
                    if (pending != null && pending.id != shown.id)
                      Tag(
                        'Revision ${pending.revisionNo} awaiting approval',
                        Tone.neutral,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.m),
                if (parts == null || parts.isEmpty)
                  EmptyNote(
                    day == null
                        ? 'Nothing scheduled on the BEO.'
                        : 'Nothing on the BEO for ${serviceDayLabel(day)}.',
                  )
                else ...[
                  _Part('Schedule', parts.schedule),
                  _Part('Menu', parts.menu),
                  _Part('Beverage', parts.beverage),
                  _Part('Dietary', parts.dietary),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// A labelled list of BEO lines. Hidden when empty.
class _Part extends StatelessWidget {
  const _Part(this.label, this.lines);

  final String label;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.meta),
          const SizedBox(height: 4),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(line, style: AppText.body),
            ),
        ],
      ),
    );
  }
}
