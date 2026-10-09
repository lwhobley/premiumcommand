import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../dispatch/data/dispatch_repository.dart';

/// Inspection photos in the private `evidence` bucket. Paths are {venue_id}/{event_id}/{file}.
/// Row-level policies on storage.objects allow only members of that venue to read or write.
class EvidenceStorage {
  EvidenceStorage(this._client);

  static const bucket = 'evidence';
  static const maxBytes = 5 * 1024 * 1024;

  final SupabaseClient _client;

  Future<String> upload({
    required String venueId,
    required String eventId,
    required Uint8List bytes,
    required String extension,
  }) async {
    if (bytes.length > maxBytes) {
      throw StateError('That photo is larger than 5 MB. Retake it at a lower resolution.');
    }
    final ext = extension.toLowerCase() == 'jpg' ? 'jpeg' : extension.toLowerCase();
    if (!{'jpeg', 'png', 'webp'}.contains(ext)) {
      throw StateError('Photos must be JPEG, PNG, or WebP.');
    }
    final path = '$venueId/$eventId/${newClientRequestId()}.$ext';
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: 'image/$ext'),
        );
    return path;
  }

  /// A short-lived link so a reviewer can view the photo. Expires after five minutes.
  Future<String> viewUrl(String path) => _client.storage.from(bucket).createSignedUrl(path, 300);
}
