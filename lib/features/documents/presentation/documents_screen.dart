import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/icons/phosphor.dart';
import '../../../core/permissions/app_permission.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/broadsheet.dart';
import '../../auth/application/session_controller.dart';
import '../../planning/presentation/planning_widgets.dart';
import '../application/documents_providers.dart';
import '../domain/venue_document.dart';
import 'document_viewer.dart';

/// The venue's reference library. Everyone at the venue can open documents in the in-app
/// viewer; nobody can download them. Administrators add, rename, and remove documents.
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _busy;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!backendAvailable) return const BackendRequired(title: 'Documents');
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final canEdit = session.can(AppPermission.manageConfiguration);
    final documents = ref.watch(venueDocumentsProvider(session.venueId));

    return PageScaffold(
      kicker: 'Reference library',
      title: 'Documents',
      subtitle: 'View only. Documents open here and cannot be downloaded, shared, or printed.',
      floatingActionButton: canEdit && _busy == null
          ? FloatingActionButton.extended(
              onPressed: () => _add(session.venueId),
              icon: const PhosphorIcon(PhosphorIconsDuotone.fileArrowUp),
              label: const Text('Add documents'),
            )
          : null,
      children: [
        if (_busy != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.l),
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 14),
                Expanded(child: Text(_busy!, style: AppText.body)),
              ],
            ),
          ),
        documents.when(
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
                      ref.invalidate(venueDocumentsProvider(session.venueId)),
                  child: const Text('Try again'),
                ),
              ),
            ],
          ),
          data: (all) {
            if (all.isEmpty) {
              return EmptyNote(
                canEdit
                    ? 'No documents yet. Use Add documents to upload PDFs, photos, or text files.'
                    : 'No documents have been shared yet.',
              );
            }
            final query = _query.trim().toLowerCase();
            final shown = query.isEmpty
                ? all
                : [
                    for (final d in all)
                      if (d.title.toLowerCase().contains(query) ||
                          d.category.toLowerCase().contains(query) ||
                          d.fileName.toLowerCase().contains(query))
                        d,
                  ];
            final groups = groupDocuments(shown);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (all.length > 6)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.s),
                    child: TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        labelText: 'Find a document',
                        prefixIcon: PhosphorIcon(
                          PhosphorIconsDuotone.magnifyingGlass,
                        ),
                      ),
                    ),
                  ),
                if (groups.isEmpty) const EmptyNote('No documents match.'),
                for (final (index, group) in groups.indexed) ...[
                  SectionHeading(group.category, first: index == 0),
                  for (final document in group.documents)
                    OpenRow(
                      leading: PhosphorIcon(
                        _iconFor(document.kind),
                        color: AppColors.accent700,
                      ),
                      title: document.title,
                      meta: _metaFor(document),
                      onTap: () => showDocumentViewer(context, document),
                      trailing: canEdit
                          ? _DocumentMenu(
                              onRename: () => _rename(document),
                              onRemove: () => _remove(document),
                            )
                          : null,
                    ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  static PhosphorIconData _iconFor(DocumentKind kind) => switch (kind) {
    DocumentKind.pdf => PhosphorIconsDuotone.filePdf,
    DocumentKind.image => PhosphorIconsDuotone.fileImage,
    DocumentKind.text => PhosphorIconsDuotone.fileText,
  };

  static String _metaFor(VenueDocument d) {
    final type = switch (d.kind) {
      DocumentKind.pdf => 'PDF',
      DocumentKind.image => 'Photo',
      DocumentKind.text => 'Text',
    };
    final added = DateFormat.yMMMd().format(d.createdAt.toLocal());
    return '$type · ${formatDocumentSize(d.sizeBytes)} · Added $added';
  }

  Future<void> _add(String venueId) async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Add documents',
      type: FileType.custom,
      allowedExtensions: documentMimeTypes.keys.toList(),
    );
    if (files.isEmpty || !mounted) return;
    final category = await _askCategory(files.length);
    if (category == null || !mounted) return;

    // The container outlives this page, so the list still refreshes if the person leaves.
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = container.read(documentsRepositoryProvider);
    final problems = <String>[];
    var added = 0;
    // Keeps going if the person leaves the page, so a batch is never half added unseen.
    for (final (i, file) in files.indexed) {
      if (mounted) {
        setState(
          () => _busy = files.length == 1
              ? 'Adding ${file.name}…'
              : 'Adding ${i + 1} of ${files.length}: ${file.name}…',
        );
      }
      try {
        final bytes = await file.readAsBytes();
        await repo.add(
          venueId: venueId,
          fileName: file.name,
          bytes: bytes,
          title: documentTitleFromFileName(file.name),
          category: category,
        );
        added++;
      } catch (error) {
        problems.add(
          error is AppFailure
              ? error.message
              : '${file.name}: ${userMessageFor(error)}',
        );
      }
    }
    container.invalidate(venueDocumentsProvider(venueId));
    if (!mounted) return;
    setState(() => _busy = null);
    final summary = added == 1
        ? '1 document added.'
        : '$added documents added.';
    if (problems.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(summary)));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(summary),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                problems.length == 1
                    ? 'One file was not added:'
                    : '${problems.length} files were not added:',
                style: AppText.body,
              ),
              const SizedBox(height: AppSpace.s),
              for (final p in problems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(p, style: AppText.meta),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Asks which category the new files go under. Returns null when cancelled.
  Future<String?> _askCategory(int count) => showDialog<String>(
    context: context,
    builder: (_) => _CategoryDialog(count: count),
  );

  Future<void> _rename(VenueDocument document) async {
    final details = await showDialog<({String title, String category})>(
      context: context,
      builder: (_) => _RenameDialog(document: document),
    );
    if (details == null || !mounted) return;
    await runWrite(context, () async {
      await ref
          .read(documentsRepositoryProvider)
          .rename(document, title: details.title, category: details.category);
      ref.invalidate(venueDocumentsProvider(document.venueId));
    }, success: 'Document saved.');
  }

  Future<void> _remove(VenueDocument document) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${document.title}?'),
        content: const Text(
          'This deletes the file from the Documents page for everyone at the venue.',
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
    if (ok != true || !mounted) return;
    await runWrite(context, () async {
      await ref.read(documentsRepositoryProvider).remove(document);
      ref.invalidate(venueDocumentsProvider(document.venueId));
    }, success: 'Document removed.');
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.count});

  final int count;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final _category = TextEditingController();

  @override
  void dispose() {
    _category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.count;
    return AlertDialog(
      title: Text(count == 1 ? 'Add 1 document' : 'Add $count documents'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Everyone at the venue will be able to view them. Nobody can download them.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSpace.m),
          TextField(
            controller: _category,
            autofocus: true,
            maxLength: 60,
            decoration: const InputDecoration(
              labelText: 'Category (optional)',
              hintText: 'For example, Policies or Venue maps',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_category.text.trim()),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.document});

  final VenueDocument document;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _title = TextEditingController(text: widget.document.title);
  late final _category = TextEditingController(text: widget.document.category);

  @override
  void dispose() {
    _title.dispose();
    _category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final problem = validateDocumentDetails(_title.text, _category.text);
    return AlertDialog(
      title: const Text('Rename document'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            maxLength: 160,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          TextField(
            controller: _category,
            maxLength: 60,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Category (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: problem == null
              ? () => Navigator.of(context).pop((
                  title: _title.text.trim(),
                  category: _category.text.trim(),
                ))
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DocumentMenu extends StatelessWidget {
  const _DocumentMenu({required this.onRename, required this.onRemove});

  final VoidCallback onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Edit document',
      padding: EdgeInsets.zero,
      icon: const PhosphorIcon(PhosphorIconsDuotone.dotsThree),
      onSelected: (choice) => choice == 'rename' ? onRename() : onRemove(),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'rename', child: Text('Rename or recategorize')),
        PopupMenuItem(value: 'remove', child: Text('Remove')),
      ],
    );
  }
}
