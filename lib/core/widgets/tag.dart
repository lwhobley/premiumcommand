import 'package:flutter/material.dart';

import '../../features/events/domain/ops_event.dart';
import '../../features/events/domain/readiness.dart';
import '../theme/app_theme.dart';

/// The three status tones. Every status is one of these, always shown with a text label.
///
/// * [accent]: ready, in service, in progress, accepted.
/// * [alert]: blocked, delayed, urgent, escalated, uncovered, overdue, failed.
/// * [neutral]: everything else (draft, planning, not started, closed, low, normal).
enum Tone {
  accent,
  alert,
  neutral;

  /// Tag background.
  Color get background => switch (this) {
    accent => AppColors.accent100,
    alert => AppColors.accent2100,
    neutral => AppColors.neutralTag,
  };

  /// Tag text.
  Color get foreground => switch (this) {
    accent => AppColors.accent800,
    alert => AppColors.accent2800,
    neutral => AppColors.neutral800,
  };

  /// Standalone text in this tone, on the page background.
  Color get text => switch (this) {
    accent => AppColors.accent700,
    alert => AppColors.accent2700,
    neutral => AppColors.muted,
  };

  /// Solid fill: progress bars, legend swatches, map cells.
  Color get fill => switch (this) {
    accent => AppColors.accent,
    alert => AppColors.accent2,
    neutral => AppColors.neutral600,
  };
}

/// Compact status label: radius 2, no border, colored by [tone]. Never wraps.
class Tag extends StatelessWidget {
  const Tag(this.label, this.tone, {super.key});

  final String label;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: AppRadius.all,
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: AppText.tag.copyWith(color: tone.foreground),
      ),
    );
  }
}

Tone readinessTone(ReadinessState state) => switch (state) {
  ReadinessState.ready || ReadinessState.inProgress => Tone.accent,
  ReadinessState.attentionRequired ||
  ReadinessState.delayed ||
  ReadinessState.blocked => Tone.alert,
  ReadinessState.notStarted || ReadinessState.noTasks => Tone.neutral,
};

Tone eventStatusTone(EventStatus status) => switch (status) {
  EventStatus.ready ||
  EventStatus.inService ||
  EventStatus.setup ||
  EventStatus.breakdown => Tone.accent,
  EventStatus.draft ||
  EventStatus.planning ||
  EventStatus.approved ||
  EventStatus.closed ||
  EventStatus.cancelled => Tone.neutral,
};
