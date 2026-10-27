import 'dart:convert';
import 'dart:typed_data';

import 'package:cutx_premium_command/core/permissions/app_permission.dart';
import 'package:cutx_premium_command/features/auth/application/session_controller.dart';
import 'package:cutx_premium_command/features/documents/application/documents_providers.dart';
import 'package:cutx_premium_command/features/documents/data/documents_repository.dart';
import 'package:cutx_premium_command/features/documents/domain/venue_document.dart';
import 'package:cutx_premium_command/features/documents/presentation/document_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeDocuments extends DocumentsRepository {
  FakeDocuments()
    : super(
        SupabaseClient(
          'https://example.com',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final reads = <String>[];

  @override
  Future<Uint8List> read(String storagePath) async {
    reads.add(storagePath);
    return Uint8List.fromList(
      utf8.encode('Doors open 90 minutes before puck drop.'),
    );
  }
}

void main() {
  testWidgets('a text document opens read-only, with no download controls', (
    tester,
  ) async {
    final repo = FakeDocuments();
    final container = ProviderContainer(
      overrides: [documentsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).signInAsDemo(AppRole.runner);
    final document = VenueDocument(
      id: 'd1',
      venueId: 'v1',
      title: 'Arrival Notes',
      category: 'Policies',
      fileName: 'arrival-notes.txt',
      storagePath: 'v1/abc.txt',
      mimeType: 'text/plain',
      sizeBytes: 40,
      createdAt: DateTime.utc(2026, 10, 27),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: DocumentViewer(document: document)),
      ),
    );
    await tester.pumpAndSettle();

    expect(repo.reads, ['v1/abc.txt']);
    expect(find.text('Arrival Notes'), findsOneWidget);
    expect(find.text('POLICIES · VIEW ONLY'), findsOneWidget);
    expect(
      find.text('Doors open 90 minutes before puck drop.'),
      findsOneWidget,
    );
    // Shown as plain text: nothing to select and copy, and no save, share, or print buttons.
    expect(find.byType(SelectableText), findsNothing);
    for (final label in ['Download', 'Share', 'Print', 'Save']) {
      expect(find.byTooltip(label), findsNothing);
    }
    expect(find.byTooltip('Close'), findsOneWidget);
  });
}
