/// How a document is shown in the viewer.
enum DocumentKind { pdf, image, text }

/// A file in the venue's read-only library on the Documents page.
class VenueDocument {
  const VenueDocument({
    required this.id,
    required this.venueId,
    required this.title,
    required this.category,
    required this.fileName,
    required this.storagePath,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
  });

  final String id;
  final String venueId;
  final String title;
  final String category;
  final String fileName;
  final String storagePath;
  final String mimeType;
  final int sizeBytes;
  final DateTime createdAt;

  DocumentKind get kind => switch (mimeType) {
    'application/pdf' => DocumentKind.pdf,
    'text/plain' => DocumentKind.text,
    _ => DocumentKind.image,
  };

  factory VenueDocument.fromJson(Map<String, dynamic> json) => VenueDocument(
    id: json['id'] as String,
    venueId: json['venue_id'] as String,
    title: json['title'] as String,
    category: (json['category'] as String?) ?? '',
    fileName: json['file_name'] as String,
    storagePath: json['storage_path'] as String,
    mimeType: json['mime_type'] as String,
    sizeBytes: (json['size_bytes'] as num).toInt(),
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}

/// File types the viewer can show, by extension, with the type stored for each.
const documentMimeTypes = {
  'pdf': 'application/pdf',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'txt': 'text/plain',
};

/// Largest file the library accepts, matching the bucket's limit.
const documentMaxBytes = 25 * 1024 * 1024;

String documentExtension(String fileName) =>
    fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';

/// The stored type for [fileName], or null when the viewer cannot show it.
String? documentMimeTypeFor(String fileName) =>
    documentMimeTypes[documentExtension(fileName)];

/// A readable default title: the file name without its extension, with dashes and
/// underscores as spaces.
String documentTitleFromFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final base = dot > 0 ? fileName.substring(0, dot) : fileName;
  final title = base
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final shown = title.isEmpty ? fileName.trim() : title;
  return shown.length > 160 ? shown.substring(0, 160).trimRight() : shown;
}

/// Returns why a file cannot be added, or null when it can.
String? validateDocumentUpload(String fileName, int sizeBytes) {
  if (documentMimeTypeFor(fileName) == null) {
    return '$fileName: add PDFs, JPEG, PNG, or WebP photos, or text files. Save Word and Excel files as PDF first.';
  }
  if (sizeBytes <= 0) return '$fileName is empty.';
  if (sizeBytes > documentMaxBytes) {
    return '$fileName is larger than 25 MB.';
  }
  return null;
}

/// Returns the first problem with a title and category, or null when they can be saved.
String? validateDocumentDetails(String title, String category) {
  final t = title.trim();
  if (t.isEmpty || t.length > 160) {
    return 'Give the document a title (up to 160 characters).';
  }
  if (category.trim().length > 60) {
    return 'The category is too long (up to 60 characters).';
  }
  return null;
}

/// "2.4 MB", "830 KB".
String formatDocumentSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).ceil()} KB';
}

/// Documents grouped by category, then by title. Uncategorized documents come last.
List<({String category, List<VenueDocument> documents})> groupDocuments(
  List<VenueDocument> documents,
) {
  final groups = <String, List<VenueDocument>>{};
  for (final d in documents) {
    groups.putIfAbsent(d.category.trim(), () => []).add(d);
  }
  final keys = groups.keys.toList()
    ..sort((a, b) {
      if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
  return [
    for (final key in keys)
      (
        category: key.isEmpty ? 'Other documents' : key,
        documents: groups[key]!
          ..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          ),
      ),
  ];
}
