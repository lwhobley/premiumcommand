import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/application/session_controller.dart';
import '../../operations/application/operations_providers.dart';
import '../data/document_import_repository.dart';
import '../domain/document_import.dart';

final documentImportRepositoryProvider = Provider<DocumentImportRepository>((
  ref,
) {
  ref.watch(sessionProvider);
  return DocumentImportRepository(Supabase.instance.client);
});

/// Opens the import screen. Returns the reviewed result, or null when cancelled.
Future<ImportOutcome?> showDocumentImport(
  BuildContext context, {
  required ImportKind kind,
  required String eventId,
}) => Navigator.of(context).push<ImportOutcome>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => DocumentImportScreen(kind: kind, eventId: eventId),
  ),
);

/// Upload a PDF or photo, or paste text, and let the assistant read the BEO or menu.
/// Administrators only; the Edge Function checks this again.
class DocumentImportScreen extends ConsumerStatefulWidget {
  const DocumentImportScreen({
    super.key,
    required this.kind,
    required this.eventId,
  });

  final ImportKind kind;
  final String eventId;

  @override
  ConsumerState<DocumentImportScreen> createState() =>
      _DocumentImportScreenState();
}

class _DocumentImportScreenState extends ConsumerState<DocumentImportScreen> {
  final _text = TextEditingController();
  String? _busy;
  ImportResult? _result;
  Set<int> _chosen = {};
  Set<int> _onMenu = {};

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _run(String label, Future<ImportResult> Function() read) async {
    setState(() => _busy = label);
    try {
      final result = await read();
      final menu = await ref.read(menuProvider(widget.eventId).future);
      if (!mounted) return;
      final onMenu = {
        for (var i = 0; i < result.menuItems.length; i++)
          if (menu.any((m) => result.menuItems[i].sameAs(m.name, m.course))) i,
      };
      setState(() {
        _result = result;
        _onMenu = onMenu;
        _chosen = {
          for (var i = 0; i < result.menuItems.length; i++)
            if (!onMenu.contains(i)) i,
        };
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userMessageFor(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _pickFile() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: DocumentImportRepository.extensions,
    );
    if (file == null || !mounted) return;
    final repo = ref.read(documentImportRepositoryProvider);
    await _run('Reading ${file.name}…', () async {
      final bytes = await file.readAsBytes();
      final path = await repo.upload(
        venueId: session.venueId,
        eventId: widget.eventId,
        bytes: bytes,
        fileName: file.name,
      );
      return repo.read(
        venueId: session.venueId,
        eventId: widget.eventId,
        kind: widget.kind,
        path: path,
      );
    });
  }

  Future<void> _readText() async {
    final session = ref.read(sessionProvider);
    final text = _text.text.trim();
    if (session == null) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Paste the ${widget.kind.label} text first.')),
      );
      return;
    }
    await _run(
      'Reading the text…',
      () => ref
          .read(documentImportRepositoryProvider)
          .read(
            venueId: session.venueId,
            eventId: widget.eventId,
            kind: widget.kind,
            text: text,
          ),
    );
  }

  void _finish() {
    final result = _result!;
    Navigator.of(context).pop(
      ImportOutcome(
        result: result,
        menuItems: [
          for (var i = 0; i < result.menuItems.length; i++)
            if (_chosen.contains(i)) result.menuItems[i],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: Text('Import ${widget.kind.label} with AI')),
      body: Column(
        children: [
          if (_busy != null)
            Material(
              color: AppColors.brassSoft,
              child: ListTile(
                dense: true,
                leading: const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                title: Text(_busy!),
              ),
            ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: result == null ? _sourceView() : _reviewView(result),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sourceView() {
    final busy = _busy != null;
    final what = widget.kind == ImportKind.beo ? 'BEO' : 'menu';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          widget.kind == ImportKind.beo
              ? 'Upload the BEO or paste its text. The assistant fills in the BEO editor for you to check, and can add its dishes to the event menu.'
              : 'Upload the menu or paste its text. The assistant lists each dish for you to check before it is added to the event menu.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : _pickFile,
          icon: const Icon(Icons.upload_file),
          label: Text('Upload $what (PDF, photo, or text file)'),
        ),
        const SizedBox(height: 4),
        const Text(
          'Up to 10 MB. The file is deleted once it has been read.',
          style: TextStyle(color: AppColors.charcoalMuted, fontSize: 12),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _text,
          enabled: !busy,
          minLines: 6,
          maxLines: 16,
          maxLength: 60000,
          decoration: InputDecoration(
            labelText: 'Or paste the $what',
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: busy ? null : _readText,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Read pasted text'),
          ),
        ),
      ],
    );
  }

  Widget _reviewView(ImportResult result) {
    final theme = Theme.of(context).textTheme;
    final content = result.content;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (result.warnings.isNotEmpty)
          Card(
            color: AppColors.brassSoft,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Check these',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  for (final warning in result.warnings)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('•  $warning'),
                    ),
                ],
              ),
            ),
          ),
        if (content != null) ...[
          const SizedBox(height: 8),
          Text('BEO', style: theme.titleMedium),
          const SizedBox(height: 4),
          Text(
            [
              if (result.title.isNotEmpty) result.title,
              if (result.guestsFound) '${content.guests} guests',
              if (result.departments.isNotEmpty)
                result.departments.map((d) => d.label).join(', '),
            ].join(' · '),
          ),
          for (final (label, value) in [
            ('Timeline', content.timeline),
            ('Menu', content.menu),
            ('Dietary', content.dietary),
            ('Beverage', content.beverage),
            ('Equipment', content.equipment),
            ('Special requests', content.specialRequests),
          ])
            if (value.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$label\n',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: value),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 8),
          const Text(
            'You can change any of this in the BEO editor next.',
            style: TextStyle(color: AppColors.charcoalMuted),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          content == null ? 'Menu items' : 'Also add to the event menu',
          style: theme.titleMedium,
        ),
        if (result.menuItems.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'No menu items found.',
              style: TextStyle(color: AppColors.charcoalMuted),
            ),
          ),
        for (var i = 0; i < result.menuItems.length; i++)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _chosen.contains(i),
            onChanged: _onMenu.contains(i)
                ? null
                : (value) => setState(() {
                    _chosen = {..._chosen};
                    value == true ? _chosen.add(i) : _chosen.remove(i);
                  }),
            title: Text(result.menuItems[i].name),
            subtitle: Text(
              [
                if (result.menuItems[i].course.isNotEmpty)
                  result.menuItems[i].course,
                ...result.menuItems[i].dietaryTags,
                if (result.menuItems[i].allergens.isNotEmpty)
                  'Allergens: ${result.menuItems[i].allergens}',
                if (_onMenu.contains(i)) 'Already on the menu',
              ].join(' · '),
            ),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: content == null && _chosen.isEmpty ? null : _finish,
              child: Text(
                content != null
                    ? 'Continue to the BEO editor'
                    : 'Add ${_chosen.length} ${_chosen.length == 1 ? 'item' : 'items'} to the menu',
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _result = null),
              child: const Text('Try another document'),
            ),
          ],
        ),
      ],
    );
  }
}
