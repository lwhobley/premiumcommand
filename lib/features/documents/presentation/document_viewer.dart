import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/icons/phosphor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/broadsheet.dart';
import '../application/documents_providers.dart';
import '../domain/venue_document.dart';

/// Opens [document] in the read-only viewer.
Future<void> showDocumentViewer(BuildContext context, VenueDocument document) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        Dialog.fullscreen(child: DocumentViewer(document: document)),
  );
}

/// Shows a document inside the app, with no download, share, print, or copy controls.
/// The file is held in memory only while the viewer is open. On the web the browser's
/// right-click menu is turned off here, so there is no "Save image as".
class DocumentViewer extends ConsumerStatefulWidget {
  const DocumentViewer({super.key, required this.document});

  final VenueDocument document;

  @override
  ConsumerState<DocumentViewer> createState() => _DocumentViewerState();
}

class _DocumentViewerState extends ConsumerState<DocumentViewer> {
  @override
  void initState() {
    super.initState();
    if (kIsWeb) unawaited(BrowserContextMenu.disableContextMenu());
  }

  @override
  void dispose() {
    if (kIsWeb) unawaited(BrowserContextMenu.enableContextMenu());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    final bytes = ref.watch(documentBytesProvider(document.storagePath));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.screen,
                AppSpace.xs,
                AppSpace.s,
                AppSpace.s,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Kicker(
                          document.category.isEmpty
                              ? 'View only'
                              : '${document.category} · View only',
                        ),
                        Text(
                          document.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.rowTitle,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const PhosphorIcon(PhosphorIconsDuotone.x),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: AppColors.neutral200,
                child: bytes.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _Problem(
                    message: userMessageFor(error),
                    onRetry: () => ref.invalidate(
                      documentBytesProvider(document.storagePath),
                    ),
                  ),
                  data: (data) => switch (document.kind) {
                    DocumentKind.pdf => _PdfPages(bytes: data),
                    DocumentKind.image => InteractiveViewer(
                      maxScale: 5,
                      child: Center(
                        child: Image.memory(
                          data,
                          errorBuilder: (_, _, _) => const _Problem(
                            message: 'This image could not be shown.',
                          ),
                        ),
                      ),
                    ),
                    DocumentKind.text => _TextPage(bytes: data),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// PDF pages drawn as images as they are read, with zoom controls.
class _PdfPages extends StatefulWidget {
  const _PdfPages({required this.bytes});

  final Uint8List bytes;

  @override
  State<_PdfPages> createState() => _PdfPagesState();
}

class _PdfPagesState extends State<_PdfPages> {
  static const _zooms = [1.0, 1.5, 2.0, 3.0];

  final _pages = <Uint8List>[];
  StreamSubscription<Uint8List>? _raster;
  bool _done = false;
  Object? _error;
  int _zoom = 0;

  @override
  void initState() {
    super.initState();
    // Each page is kept as a compressed image, not raw pixels, so long documents fit in memory.
    _raster = Printing.raster(widget.bytes, dpi: 144)
        .asyncMap((page) => page.toPng())
        .listen(
          (png) {
            if (mounted) setState(() => _pages.add(png));
          },
          onError: (Object error) {
            if (mounted) setState(() => _error = error);
          },
          onDone: () {
            if (mounted) setState(() => _done = true);
          },
        );
  }

  @override
  void dispose() {
    _raster?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _pages.isEmpty) {
      return const _Problem(message: 'This PDF could not be shown.');
    }
    if (_pages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final zoom = _zooms[_zoom];
    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // Fit the page to the screen (up to 900 wide), then zoom from there.
            final fit = (constraints.maxWidth - 2 * AppSpace.s).clamp(
              0.0,
              900.0,
            );
            final pageWidth = fit * zoom;
            final list = ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.s,
                AppSpace.s,
                AppSpace.s,
                88,
              ),
              itemCount: _pages.length + (_done ? 0 : 1),
              itemBuilder: (context, i) {
                if (i == _pages.length) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpace.l),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.s),
                  child: Center(
                    child: SizedBox(
                      width: pageWidth,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(color: Color(0x22000000), blurRadius: 4),
                          ],
                        ),
                        child: Image.memory(
                          _pages[i],
                          fit: BoxFit.fitWidth,
                          gaplessPlayback: true,
                          semanticLabel: 'Page ${i + 1}',
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
            if (pageWidth + 2 * AppSpace.s <= constraints.maxWidth) return list;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: pageWidth + 2 * AppSpace.s, child: list),
            );
          },
        ),
        Positioned(
          right: AppSpace.screen,
          bottom: AppSpace.l,
          child: SafeArea(
            child: Material(
              color: AppColors.background,
              elevation: 2,
              borderRadius: BorderRadius.circular(24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Zoom out',
                    onPressed: _zoom == 0
                        ? null
                        : () => setState(() => _zoom--),
                    icon: const PhosphorIcon(PhosphorIconsDuotone.minus),
                  ),
                  Text('${(zoom * 100).round()}%', style: AppText.meta),
                  IconButton(
                    tooltip: 'Zoom in',
                    onPressed: _zoom == _zooms.length - 1
                        ? null
                        : () => setState(() => _zoom++),
                    icon: const PhosphorIcon(PhosphorIconsDuotone.plus),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TextPage extends StatelessWidget {
  const _TextPage({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpace.screen),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Text(
            utf8.decode(bytes, allowMalformed: true),
            style: AppText.body,
          ),
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.screen),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: AppText.body, textAlign: TextAlign.center),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
