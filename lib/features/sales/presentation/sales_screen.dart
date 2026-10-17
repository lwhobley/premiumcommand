import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/session_controller.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../application/sales_providers.dart';
import '../domain/sales_package.dart';
import 'sales_package_editor.dart';

/// Premium offerings and current pricing. Tap a package to show it full screen to a buyer.
/// People with manage_sales can add, edit, reorder, hide, and remove packages.
class SalesScreen extends ConsumerWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!backendAvailable) return const BackendRequired(title: 'Sales');
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final canEdit = session.can(AppPermission.manageSales);
    final packages = ref.watch(salesPackagesProvider(session.venueId));

    return Scaffold(
      appBar: AppBar(title: const Text('Sales')),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _add(
                context,
                ref,
                session.venueId,
                packages.value ?? const [],
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add package'),
            )
          : null,
      body: packages.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(userMessageFor(error), textAlign: TextAlign.center),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(salesPackagesProvider(session.venueId)),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (all) {
          final groups = groupSalesPackages(all, includeInactive: canEdit);
          if (groups.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  canEdit
                      ? 'No packages yet. Use Add package to create the first one.'
                      : 'No packages are available yet.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.charcoalMuted),
                ),
              ),
            );
          }
          // Swiping in the showcase moves through every shown package, in page order.
          final ordered = [for (final g in groups) ...g.packages];
          return LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1100
                  ? 3
                  : constraints.maxWidth >= 700
                  ? 2
                  : 1;
              const gap = 16.0;
              final cardWidth =
                  (constraints.maxWidth - 32 - gap * (columns - 1)) / columns;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  for (final group in groups) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 10),
                      child: Text(
                        group.category,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final package in group.packages)
                          SizedBox(
                            width: cardWidth,
                            child: _PackageCard(
                              package: package,
                              canEdit: canEdit,
                              onOpen: () => showSalesShowcase(
                                context,
                                packages: ordered,
                                initialIndex: ordered.indexOf(package),
                              ),
                              onEdit: () => _edit(context, ref, package),
                              onMove: (delta) =>
                                  _move(context, ref, ordered, package, delta),
                              onDelete: () => _delete(context, ref, package),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    String venueId,
    List<SalesPackage> existing,
  ) async {
    final draft = await showSalesPackageEditor(context);
    if (draft == null || !context.mounted) return;
    final nextOrder = existing.isEmpty
        ? 10
        : existing.map((p) => p.sortOrder).reduce((a, b) => a > b ? a : b) + 10;
    await runWrite(context, () async {
      await ref
          .read(salesRepositoryProvider)
          .create(venueId, draft, sortOrder: nextOrder);
      ref.invalidate(salesPackagesProvider(venueId));
    }, success: 'Package added.');
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    SalesPackage package,
  ) async {
    final draft = await showSalesPackageEditor(context, existing: package);
    if (draft == null || !context.mounted) return;
    await runWrite(context, () async {
      await ref.read(salesRepositoryProvider).update(package, draft);
      ref.invalidate(salesPackagesProvider(package.venueId));
    }, success: 'Package saved.');
  }

  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    List<SalesPackage> ordered,
    SalesPackage package,
    int delta,
  ) async {
    final index = ordered.indexOf(package);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= ordered.length) return;
    await runWrite(context, () async {
      await ref
          .read(salesRepositoryProvider)
          .swapOrder(package, ordered[target]);
      ref.invalidate(salesPackagesProvider(package.venueId));
    });
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    SalesPackage package,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${package.title}?'),
        content: const Text(
          'This removes the package and its pricing from the Sales page. To keep it for later, edit it and hide it instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.blocked),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runWrite(context, () async {
      await ref.read(salesRepositoryProvider).delete(package.id);
      ref.invalidate(salesPackagesProvider(package.venueId));
    }, success: 'Package removed.');
  }
}

class _PackageImage extends StatelessWidget {
  const _PackageImage({required this.url, this.height});

  final String? url;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      height: height,
      color: AppColors.surfaceMuted,
      alignment: Alignment.center,
      child: const Icon(
        Icons.stadium_outlined,
        size: 40,
        color: AppColors.charcoalMuted,
      ),
    );
    final link = url;
    if (link == null || link.isEmpty) return placeholder;
    return Image.network(
      link,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : placeholder,
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.package,
    required this.canEdit,
    required this.onOpen,
    required this.onEdit,
    required this.onMove,
    required this.onDelete,
  });

  final SalesPackage package;
  final bool canEdit;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final ValueChanged<int> onMove;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final options = package.priceRows.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _PackageImage(url: package.imageUrl),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          package.title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (canEdit)
                        PopupMenuButton<String>(
                          tooltip: 'Edit package',
                          onSelected: (choice) {
                            switch (choice) {
                              case 'edit':
                                onEdit();
                              case 'up':
                                onMove(-1);
                              case 'down':
                                onMove(1);
                              case 'delete':
                                onDelete();
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit offering and pricing'),
                            ),
                            PopupMenuItem(
                              value: 'up',
                              child: Text('Move earlier'),
                            ),
                            PopupMenuItem(
                              value: 'down',
                              child: Text('Move later'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Remove'),
                            ),
                          ],
                        ),
                    ],
                  ),
                  if (!package.active)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text(
                        'Hidden from the Sales page',
                        style: TextStyle(
                          color: AppColors.attention,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (package.headlinePrice.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      options > 1
                          ? 'From ${package.headlinePrice}'
                          : package.headlinePrice,
                      style: const TextStyle(
                        color: AppColors.brass,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (options > 1)
                      Text(
                        '$options pricing options',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.charcoalMuted,
                        ),
                      ),
                  ],
                  if (package.summary.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      package.summary,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.charcoalMuted),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(
                        Icons.open_in_full,
                        size: 14,
                        color: AppColors.brass,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Tap to show full screen',
                        style: TextStyle(fontSize: 12, color: AppColors.brass),
                      ),
                    ],
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

/// Full-screen presentation for showing packages to a buyer. Swipe or use the arrows to move
/// between packages. No editing controls appear here.
Future<void> showSalesShowcase(
  BuildContext context, {
  required List<SalesPackage> packages,
  required int initialIndex,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog.fullscreen(
      child: _Showcase(
        packages: packages,
        initialIndex: initialIndex < 0 ? 0 : initialIndex,
      ),
    ),
  );
}

class _Showcase extends StatefulWidget {
  const _Showcase({required this.packages, required this.initialIndex});

  final List<SalesPackage> packages;
  final int initialIndex;

  @override
  State<_Showcase> createState() => _ShowcaseState();
}

class _ShowcaseState extends State<_Showcase> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final target = _index + delta;
    if (target < 0 || target >= widget.packages.length) return;
    _pages.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.packages.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.packages[_index].category),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: count,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => _ShowcasePage(package: widget.packages[i]),
      ),
      bottomNavigationBar: count < 2
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Previous package',
                      onPressed: _index == 0 ? null : () => _go(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        '${_index + 1} of $count',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.charcoalMuted),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Next package',
                      onPressed: _index == count - 1 ? null : () => _go(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _ShowcasePage extends StatelessWidget {
  const _ShowcasePage({required this.package});

  final SalesPackage package;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _PackageImage(url: package.imageUrl, height: 320),
              ),
              const SizedBox(height: 20),
              Text(
                package.title,
                style: theme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (package.summary.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  package.summary,
                  style: theme.titleMedium?.copyWith(
                    color: AppColors.charcoalMuted,
                  ),
                ),
              ],
              if (package.priceRows.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Pricing', style: theme.titleLarge),
                const SizedBox(height: 8),
                for (final row in package.priceRows)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row.label,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (row.detail.isNotEmpty)
                                  Text(
                                    row.detail,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: AppColors.charcoalMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            row.price,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brass,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (package.priceNote.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      package.priceNote,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.charcoalMuted,
                      ),
                    ),
                  ),
              ],
              if (package.features.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Included', style: theme.titleLarge),
                const SizedBox(height: 8),
                for (final feature in package.features)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.check_circle,
                            color: AppColors.ready,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            feature,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
