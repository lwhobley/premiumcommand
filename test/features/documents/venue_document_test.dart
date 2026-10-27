import 'package:cutx_premium_command/app/app_section.dart';
import 'package:cutx_premium_command/core/permissions/app_permission.dart';
import 'package:cutx_premium_command/features/documents/domain/venue_document.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({
  String id = 'd1',
  String title = 'Suite Service Standards',
  String category = 'Policies',
  String mimeType = 'application/pdf',
}) => {
  'id': id,
  'venue_id': 'v1',
  'title': title,
  'category': category,
  'file_name': 'suite-service-standards.pdf',
  'storage_path': 'v1/abc.pdf',
  'mime_type': mimeType,
  'size_bytes': 2516582,
  'created_at': '2026-10-27T15:00:00Z',
};

void main() {
  test('a database row parses, and its type picks the viewer', () {
    final d = VenueDocument.fromJson(_row());
    expect(d.title, 'Suite Service Standards');
    expect(d.sizeBytes, 2516582);
    expect(d.kind, DocumentKind.pdf);
    expect(
      VenueDocument.fromJson(_row(mimeType: 'image/png')).kind,
      DocumentKind.image,
    );
    expect(
      VenueDocument.fromJson(_row(mimeType: 'text/plain')).kind,
      DocumentKind.text,
    );
  });

  test('only file types the viewer can show are accepted', () {
    expect(documentMimeTypeFor('Map.PDF'), 'application/pdf');
    expect(documentMimeTypeFor('photo.jpeg'), 'image/jpeg');
    expect(documentMimeTypeFor('notes.txt'), 'text/plain');
    expect(documentMimeTypeFor('budget.xlsx'), isNull);
    expect(documentMimeTypeFor('README'), isNull);

    expect(validateDocumentUpload('map.pdf', 1024), isNull);
    expect(validateDocumentUpload('budget.docx', 1024), contains('PDF'));
    expect(validateDocumentUpload('empty.pdf', 0), contains('empty'));
    expect(
      validateDocumentUpload('huge.pdf', documentMaxBytes + 1),
      contains('25 MB'),
    );
  });

  test('a title is made from the file name', () {
    expect(
      documentTitleFromFileName('suite_service-standards.pdf'),
      'suite service standards',
    );
    expect(documentTitleFromFileName('.pdf'), '.pdf');
    expect(documentTitleFromFileName('Floor Plan v2.png'), 'Floor Plan v2');
    expect(documentTitleFromFileName('${'a' * 200}.pdf').length, 160);
  });

  test('titles and categories are checked before saving', () {
    expect(validateDocumentDetails('Map', ''), isNull);
    expect(validateDocumentDetails('  ', ''), isNotNull);
    expect(validateDocumentDetails('Map', 'c' * 61), isNotNull);
  });

  test('documents group by category, uncategorized last, titles in order', () {
    final groups = groupDocuments([
      VenueDocument.fromJson(_row(id: '1', title: 'b', category: '')),
      VenueDocument.fromJson(_row(id: '2', title: 'Zed', category: 'Policies')),
      VenueDocument.fromJson(
        _row(id: '3', title: 'alpha', category: 'Policies'),
      ),
      VenueDocument.fromJson(_row(id: '4', title: 'Map', category: 'Maps')),
    ]);
    expect(groups.map((g) => g.category), [
      'Maps',
      'Policies',
      'Other documents',
    ]);
    expect(groups[1].documents.map((d) => d.title), ['alpha', 'Zed']);
  });

  test('sizes read as KB or MB', () {
    expect(formatDocumentSize(2516582), '2.4 MB');
    expect(formatDocumentSize(830 * 1024), '830 KB');
  });

  test('every role can open Documents', () {
    for (final role in AppRole.values) {
      expect(AppSection.documents.allows(permissionsFor({role})), isTrue);
    }
  });
}
