import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Shown for sections whose build phase has not started yet.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title, required this.plannedPhase});

  final String title;
  final int plannedPhase;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.construction_outlined, size: 40, color: AppColors.charcoalMuted),
              const SizedBox(height: 12),
              Text('Planned for Phase $plannedPhase',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Not built yet. This section is part of the roadmap.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.charcoalMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
