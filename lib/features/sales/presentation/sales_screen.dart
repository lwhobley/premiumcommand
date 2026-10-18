import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/icons/phosphor.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../../core/widgets/tag.dart';
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

    return PageScaffold(
      kicker: 'Premium sales',
      title: 'Sales',
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _add(
                context,
                ref,
                session.venueId,
                packages.value ?? const [],
              ),
              icon: const PhosphorIcon(PhosphorIconsDuotone.plus),
              label: const Text('Add package'),
            )
          : null,
      children: [
        packages.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(userMessageFor(error), style: AppText.body),
              Transform.translate(
                offset: const Offset(-10, 0),
                child: TextButton(
                  onPressed: () =>
                      ref.invalidate(salesPackagesProvider(session.venueId)),
                  child: const Text('Try again'),
                ),
              ),
            ],
          ),
          data: (all) {
            final groups = groupSalesPackages(all, includeInactive: canEdit);
            if (groups.isEmpty) {
              return EmptyNote(
                canEdit
                    ? 'No packages yet. Use Add package to create the first one.'
                    : 'No packages are available yet.',
              );
            }
            // Swiping in the showcase moves through every shown package, in page order.
            final ordered = [for (final g in groups) ...g.packages];
            return LayoutBuilder(
              builder: (context, constraints) {
                // Column breakpoints are by screen width; the page pads both sides.
                final screenWidth = constraints.maxWidth + 2 * AppSpace.screen;
                final columns = screenWidth >= 1100
                    ? 3
                    : screenWidth >= 700
                    ? 2
                    : 1;
                const gap = 16.0;
                final cardWidth =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (index, group) in groups.indexed) ...[
                      SectionHeading(group.category, first: index == 0),
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
                                onMove: (delta) => _move(
                                  context,
                                  ref,
                                  ordered,
                                  package,
                                  delta,
                                ),
                                onDelete: () => _delete(context, ref, package),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ],
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
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent2700,
            ),
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
      color: AppColors.neutral200,
      alignment: Alignment.center,
      child: const PhosphorIcon(
        PhosphorIconsDuotone.buildings,
        size: 40,
        color: AppColors.muted,
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
              padding: const EdgeInsets.fromLTRB(16, 14, 6, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          // Lines the title up with the menu button's icon.
                          padding: EdgeInsets.only(top: canEdit ? 10 : 0),
                          child: Text(package.title, style: AppText.rowTitle),
                        ),
                      ),
                      if (canEdit)
                        PopupMenuButton<String>(
                          tooltip: 'Edit package',
                          icon: const PhosphorIcon(
                            PhosphorIconsDuotone.dotsThree,
                          ),
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
                      padding: EdgeInsets.only(top: 4),
                      child: Tag('Hidden from the Sales page', Tone.neutral),
                    ),
                  if (package.headlinePrice.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      options > 1
                          ? 'From ${package.headlinePrice}'
                          : package.headlinePrice,
                      style: const TextStyle(
                        color: AppColors.accent700,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (options > 1)
                      Text('$options pricing options', style: AppText.meta),
                  ],
                  if (package.summary.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      package.summary,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body.copyWith(color: AppColors.muted),
                    ),
                  ],
                  const SizedBox(height: 10),
                  const Row(
                    children: [
                      PhosphorIcon(
                        PhosphorIconsDuotone.arrowsOut,
                        size: 14,
                        color: AppColors.accent700,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Tap to show full screen',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.accent700,
                        ),
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
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.screen,
                AppSpace.xs,
                AppSpace.s,
                0,
              ),
              child: Row(
                children: [
                  Expanded(child: Kicker(widget.packages[_index].category)),
                  IconButton(
                    tooltip: 'Close',
                    icon: const PhosphorIcon(PhosphorIconsDuotone.x),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: count,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) =>
                    _ShowcasePage(package: widget.packages[i]),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: count < 2
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.screen,
                  8,
                  AppSpace.s,
                  8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_index + 1} of $count',
                        style: AppText.meta.copyWith(fontSize: 15),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Previous package',
                      onPressed: _index == 0 ? null : () => _go(-1),
                      icon: const PhosphorIcon(PhosphorIconsDuotone.caretLeft),
                    ),
                    const SizedBox(width: AppSpace.s),
                    IconButton.filledTonal(
                      tooltip: 'Next package',
                      onPressed: _index == count - 1 ? null : () => _go(1),
                      icon: const PhosphorIcon(PhosphorIconsDuotone.caretRight),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screen,
        AppSpace.s,
        AppSpace.screen,
        32,
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: AppRadius.all,
                child: _PackageImage(url: package.imageUrl, height: 320),
              ),
              const SizedBox(height: AppSpace.l),
              Text(package.title, style: AppText.screenTitle),
              if (package.summary.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  package.summary,
                  style: AppText.body.copyWith(
                    fontSize: 18,
                    color: AppColors.muted,
                  ),
                ),
              ],
              if (package.priceRows.isNotEmpty) ...[
                const SectionHeading('Pricing'),
                for (final row in package.priceRows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.label,
                                style: AppText.rowTitle.copyWith(fontSize: 20),
                              ),
                              if (row.detail.isNotEmpty)
                                Text(
                                  row.detail,
                                  style: AppText.body.copyWith(
                                    color: AppColors.muted,
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
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent700,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (package.priceNote.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      package.priceNote,
                      style: AppText.body.copyWith(color: AppColors.muted),
                    ),
                  ),
              ],
              if (package.features.isNotEmpty) ...[
                const SectionHeading('Included'),
                for (final feature in package.features)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: PhosphorIcon(
                            PhosphorIconsDuotone.checkCircle,
                            color: AppColors.accent700,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            feature,
                            style: AppText.body.copyWith(fontSize: 18),
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
