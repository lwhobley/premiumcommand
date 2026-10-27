import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../dispatch/data/dispatch_repository.dart';
import '../domain/venue_document.dart';

/// The venue's document library. Files live in the private `venue-documents` bucket
/// ({venue_id}/{file}). Everyone at the venue can read them; only administrators
/// (manage_configuration) can add, rename, or remove them, which the database enforces.
class DocumentsRepository {
  DocumentsRepository(this._client);

  static const bucket = 'venue-documents';

  final SupabaseClient _client;

  Future<List<VenueDocument>> list(String venueId) async {
    final rows = await _client
        .from('venue_documents')
        .select()
        .eq('venue_id', venueId)
        .order('title');
    return rows
        .cast<Map<String, dynamic>>()
        .map(VenueDocument.fromJson)
        .toList();
  }

  /// Stores a file and lists it. If the listing fails, the stored file is removed again.
  Future<void> add({
    required String venueId,
    required String fileName,
    required Uint8List bytes,
    required String title,
    String category = '',
  }) async {
    final problem = validateDocumentUpload(fileName, bytes.length);
    if (problem != null) throw AppFailure(problem);
    final mimeType = documentMimeTypeFor(fileName)!;
    final path =
        '$venueId/${newClientRequestId()}.${documentExtension(fileName)}';
    await _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType),
        );
    try {
      await _client.from('venue_documents').insert({
        'venue_id': venueId,
        'title': title.trim(),
        'category': category.trim(),
        'file_name': fileName,
        'storage_path': path,
        'mime_type': mimeType,
        'size_bytes': bytes.length,
      });
    } catch (_) {
      try {
        await _client.storage.from(bucket).remove([path]);
      } catch (_) {
        // The listing error below is the one worth showing.
      }
      rethrow;
    }
  }

  Future<void> rename(
    VenueDocument document, {
    required String title,
    required String category,
  }) async {
    final rows = await _client
        .from('venue_documents')
        .update({'title': title.trim(), 'category': category.trim()})
        .eq('id', document.id)
        .select('id');
    if (rows.isEmpty) {
      throw const AppFailure(
        'This document was removed, or you can no longer edit it. Refresh and try again.',
      );
    }
  }

  /// Removes the listing first, so a failed file delete leaves nothing visible behind. The
  /// file's path is random and no longer listed, so a file left over is unreachable.
  Future<void> remove(VenueDocument document) async {
    final rows = await _client
        .from('venue_documents')
        .delete()
        .eq('id', document.id)
        .select('id');
    if (rows.isEmpty) {
      throw const AppFailure(
        'This document was already removed, or you can no longer remove it.',
      );
    }
    try {
      await _client.storage.from(bucket).remove([document.storagePath]);
    } catch (_) {
      // The document is already gone from the page; there is nothing to retry from there.
    }
  }

  /// The file's contents, held in memory for the viewer. Nothing is saved to the device.
  Future<Uint8List> read(String storagePath) =>
      _client.storage.from(bucket).download(storagePath);
}
