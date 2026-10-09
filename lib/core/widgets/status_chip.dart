import 'package:flutter/material.dart';

import '../../features/events/domain/ops_event.dart';
import '../../features/events/domain/readiness.dart';
import '../theme/app_theme.dart';

/// Compact status indicator. Color is paired with a text label, never used alone.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

Color readinessColor(ReadinessState state) => switch (state) {
      ReadinessState.ready => AppColors.ready,
      ReadinessState.inProgress => AppColors.inProgress,
      ReadinessState.attentionRequired => AppColors.attention,
      ReadinessState.delayed => AppColors.delayed,
      ReadinessState.blocked => AppColors.blocked,
      ReadinessState.notStarted || ReadinessState.noTasks => AppColors.neutral,
    };

Color eventStatusColor(EventStatus status) => switch (status) {
      EventStatus.inService || EventStatus.ready => AppColors.ready,
      EventStatus.setup || EventStatus.breakdown => AppColors.inProgress,
      EventStatus.approved || EventStatus.planning => AppColors.attention,
      EventStatus.cancelled => AppColors.blocked,
      EventStatus.draft || EventStatus.closed => AppColors.neutral,
    };
