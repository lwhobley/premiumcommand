import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../dispatch/data/dispatch_repository.dart';
import '../domain/document_import.dart';

/// BEO and menu documents read by the document-ai Edge Function. Files go to the private
/// `documents` bucket ({venue_id}/{event_id}/{file}), readable only by administrators, and
/// the function deletes each one after reading it.
class DocumentImportRepository {
  DocumentImportRepository(this._client);

  static const bucket = 'documents';
  static const maxBytes = 10 * 1024 * 1024;
  static const extensions = ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'txt'];

  final SupabaseClient _client;

  /// Uploads a document and returns its storage path.
  Future<String> upload({
    required String venueId,
    required String eventId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (bytes.length > maxBytes) {
      throw const AppFailure('Files must be 10 MB or smaller.');
    }
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    if (!extensions.contains(ext)) {
      throw const AppFailure(
        'Upload a PDF, a JPEG, PNG, or WebP photo, or a text file.',
      );
    }
    final contentType = switch (ext) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'text/plain',
    };
    final path = '$venueId/$eventId/${newClientRequestId()}.$ext';
    await _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );
    return path;
  }

  /// Asks the assistant to read an uploaded file ([path]) or pasted [text].
  Future<ImportResult> read({
    required String venueId,
    required String eventId,
    required ImportKind kind,
    String? path,
    String? text,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'document-ai',
        body: {
          'venue_id': venueId,
          'event_id': eventId,
          'kind': kind.code,
          'path': ?path,
          'text': ?text,
        },
      );
      final data = response.data;
      if (data is Map) {
        return ImportResult.fromJson(data.cast<String, dynamic>());
      }
      throw const AppFailure('The assistant returned an unexpected response.');
    } on FunctionException catch (error) {
      final details = error.details;
      final message = details is Map && details['error'] is String
          ? details['error'] as String
          : 'The assistant could not be reached. Try again.';
      throw AppFailure(message);
    }
  }
}
