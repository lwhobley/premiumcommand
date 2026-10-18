import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/icons/phosphor.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/broadsheet.dart';
import '../features/auth/application/session_controller.dart';
import 'app_section.dart';

/// Phone-width list of every section the user is permitted to open.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final sections = AppSection.values
        .where((s) => session != null && s.allows(session.permissions))
        .toList();

    return PageScaffold(
      kicker: session?.venueName,
      title: 'More',
      children: [
        for (final section in sections)
          _MoreRow(
            icon: section.icon,
            label: section.label,
            onTap: () => context.go(section.path),
          ),
        const SizedBox(height: AppSpace.l),
        _MoreRow(
          icon: PhosphorIconsDuotone.identificationBadge,
          label: 'My profile',
          onTap: () => context.go('/profile'),
        ),
        const SizedBox(height: AppSpace.xl),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => ref.read(sessionProvider.notifier).signOut(),
            icon: const PhosphorIcon(PhosphorIconsDuotone.signOut, size: 20),
            label: const Text('Sign out'),
          ),
        ),
      ],
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final PhosphorIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.all,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            PhosphorIcon(icon, size: 24, color: AppColors.accent700),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, color: AppColors.text),
              ),
            ),
            const PhosphorIcon(
              PhosphorIconsDuotone.caretRight,
              size: 18,
              color: AppColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}
