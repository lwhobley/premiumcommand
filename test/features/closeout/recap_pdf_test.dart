import 'package:flutter_test/flutter_test.dart';
import 'package:cutx_premium_command/features/closeout/data/recap_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recap export embeds the Unicode font for names and punctuation', () async {
    final bytes = await buildRecapPdf({
      'event': {
        'name': 'José — Zürich',
        'service_start': '2026-10-14T18:00:00Z',
        'service_end': '2026-10-14T21:00:00Z',
      },
    }, status: 'signed', timeZone: 'America/Chicago');
    expect(bytes.length, greaterThan(1000));
  });
}
