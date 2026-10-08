import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/application/session_controller.dart';
import 'app_section.dart';

const _wideBreakpoint = 840.0;

/// Phone bottom bar: the primary live-service actions. Everything else lives under "More".
const _mobilePrimary = [
  AppSection.commandCenter,
  AppSection.eventWorkspace,
  AppSection.liveDispatch,
  AppSection.myShift,
];

class ShellScaffold extends ConsumerWidget {
  const ShellScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session == null) return child;

    final location = GoRouterState.of(context).uri.path;
    final visible = AppSection.values.where((s) => s.allows(session.permissions)).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideBreakpoint) {
          return Scaffold(
            body: Row(
              children: [
                _Sidebar(sections: visible, location: location, venueName: session.venueName),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            ),
          );
        }

        final primary = _mobilePrimary.where(visible.contains).toList();
        final selected = primary.indexWhere((s) => location.startsWith(s.path));
        return Scaffold(
          body: child,
          bottomNavigationBar: NavigationBar(
            selectedIndex: selected < 0 ? primary.length : selected,
            onDestinationSelected: (index) {
              if (index == primary.length) {
                context.go('/menu');
              } else {
                context.go(primary[index].path);
              }
            },
            destinations: [
              for (final section in primary)
                NavigationDestination(icon: Icon(section.icon), label: section.label.split(' ').first),
              const NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
            ],
          ),
        );
      },
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.sections, required this.location, required this.venueName});

  final List<AppSection> sections;
  final String location;
  final String venueName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return Container(
      width: 240,
      color: AppColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CUTX Premium Command',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(venueName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.charcoalMuted)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final section in sections)
                    _SidebarItem(
                      section: section,
                      selected: location.startsWith(section.path),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      session?.displayName ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sign out',
                    icon: const Icon(Icons.logout),
                    onPressed: () => ref.read(sessionProvider.notifier).signOut(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({required this.section, required this.selected});

  final AppSection section;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: AppColors.brassSoft,
      selectedColor: AppColors.charcoal,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: Icon(section.icon, size: 20),
      title: Text(section.label, style: const TextStyle(fontSize: 14)),
      onTap: () => context.go(section.path),
    );
  }
}
