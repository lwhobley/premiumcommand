import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/application/session_controller.dart';
import '../data/documents_repository.dart';
import '../domain/venue_document.dart';

final documentsRepositoryProvider = Provider<DocumentsRepository>((ref) {
  ref.watch(sessionProvider);
  return DocumentsRepository(Supabase.instance.client);
});

/// Reloaded each time the Documents page opens, so readers see newly added files.
final venueDocumentsProvider = FutureProvider.autoDispose
    .family<List<VenueDocument>, String>((ref, venueId) {
      ref.watch(sessionProvider);
      return ref.watch(documentsRepositoryProvider).list(venueId);
    });

/// A document's contents, by storage path, while its viewer is open. Released when the
/// viewer closes.
final documentBytesProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, storagePath) {
      ref.watch(sessionProvider);
      return ref.watch(documentsRepositoryProvider).read(storagePath);
    });
