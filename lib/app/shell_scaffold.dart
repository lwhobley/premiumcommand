import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/icons/phosphor.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/application/session_controller.dart';
import '../features/dispatch/application/dispatch_providers.dart';
import '../features/sync/presentation/sync_banner.dart';
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
    final visible = AppSection.values
        .where((s) => s.allows(session.permissions))
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideBreakpoint) {
          return Scaffold(
            body: Row(
              children: [
                _Sidebar(
                  sections: visible,
                  location: location,
                  venueName: session.venueName,
                ),
                Expanded(
                  child: Column(
                    children: [
                      const SyncBanner(),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final primary = _mobilePrimary.where(visible.contains).toList();
        final selected = primary.indexWhere((s) => s.matches(location));
        return Scaffold(
          body: Column(
            children: [
              const SyncBanner(),
              Expanded(child: child),
            ],
          ),
          // The hairline above the bar is the one rule the layout allows.
          bottomNavigationBar: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.ink(0.12))),
            ),
            child: NavigationBar(
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
                  NavigationDestination(
                    icon: section == AppSection.liveDispatch
                        ? _DispatchIcon(section.icon)
                        : PhosphorIcon(section.icon),
                    label: section.label.split(' ').first,
                  ),
                const NavigationDestination(
                  icon: PhosphorIcon(PhosphorIconsDuotone.dotsThree),
                  label: 'More',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The Dispatch tab icon with a magenta count of escalated requests.
class _DispatchIcon extends ConsumerWidget {
  const _DispatchIcon(this.icon);

  final PhosphorIconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final escalated = ref.watch(escalatedRequestCountProvider);
    return Badge(
      isLabelVisible: escalated > 0,
      label: Text('$escalated'),
      child: PhosphorIcon(icon),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.sections,
    required this.location,
    required this.venueName,
  });

  final List<AppSection> sections;
  final String location;
  final String venueName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    // Material gives the rows an ink ancestor; a plain colored Container would hide their splashes.
    return SizedBox(
      width: 240,
      child: Material(
        color: AppColors.background,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Premium Command',
                      style: TextStyle(
                        fontSize: 20,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(venueName, style: AppText.meta),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: [
                    for (final section in sections)
                      _SidebarItem(
                        section: section,
                        selected: section.matches(location),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 10, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        session?.displayName ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: AppText.meta,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Sign out',
                      icon: const PhosphorIcon(PhosphorIconsDuotone.signOut),
                      onPressed: () =>
                          ref.read(sessionProvider.notifier).signOut(),
                    ),
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

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({required this.section, required this.selected});

  final AppSection section;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? AppColors.accent100 : Colors.transparent,
        borderRadius: AppRadius.all,
        child: InkWell(
          borderRadius: AppRadius.all,
          hoverColor: AppColors.ink(0.05),
          onTap: () => context.go(section.path),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSpace.minTap),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  PhosphorIcon(
                    section.icon,
                    size: 20,
                    color: selected ? AppColors.accent700 : AppColors.text,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      section.label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
