import 'package:cutx_premium_command/features/sales/domain/sales_package.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({
  String id = 'p1',
  String category = 'Allen Americans Suites',
  String title = 'Suite · Full Season',
  int sortOrder = 10,
  bool active = true,
  List<Map<String, String>> prices = const [
    {
      'label': 'Bronze · 10 seats',
      'price': r'$18,000',
      'detail': r'$500 per game · 36 games',
    },
    {
      'label': 'Silver · 12 seats',
      'price': r'$21,600',
      'detail': r'$600 per game · 36 games',
    },
  ],
}) => {
  'id': id,
  'venue_id': 'v1',
  'category': category,
  'title': title,
  'summary': 'Exclusive access to your suite.',
  'features': ['Wet bar', 'Suite attendant'],
  'price_rows': prices,
  'price_note': r'Additional suite tickets are $50 each.',
  'image_url': 'https://example.com/suite.jpg',
  'sort_order': sortOrder,
  'active': active,
  'version': 2,
};

SalesPackageDraft _draft({
  String title = 'Club Seats',
  String image = '',
  List<String> features = const [],
}) => SalesPackageDraft(
  category: 'Club Seats',
  title: title,
  summary: '',
  features: features,
  priceRows: const [],
  priceNote: '',
  imageUrl: image,
  active: true,
);

void main() {
  test('a database row parses with its price rows', () {
    final p = SalesPackage.fromJson(_row());
    expect(p.title, 'Suite · Full Season');
    expect(p.priceRows, hasLength(2));
    expect(p.priceRows.first.price, r'$18,000');
    expect(p.headlinePrice, r'$18,000');
    expect(p.features, ['Wet bar', 'Suite attendant']);
    expect(p.version, 2);
  });

  test(
    'saving drops blank feature lines and empty price rows, and trims text',
    () {
      final draft = SalesPackageDraft(
        category: ' Suites ',
        title: ' Suite · Half Season ',
        summary: '',
        features: const ['Wet bar', '  ', ' Free parking '],
        priceRows: const [
          SalesPriceRow(label: 'Gold · 14 seats', price: r' $13,860 '),
          SalesPriceRow(label: '', price: ''),
        ],
        priceNote: '',
        imageUrl: '  ',
        active: false,
      );
      final columns = draft.toColumns();
      expect(columns['title'], 'Suite · Half Season');
      expect(columns['category'], 'Suites');
      expect(columns['features'], ['Wet bar', 'Free parking']);
      expect(columns['price_rows'], [
        {'label': 'Gold · 14 seats', 'price': r'$13,860', 'detail': ''},
      ]);
      expect(columns['image_url'], isNull);
      expect(columns['active'], isFalse);
    },
  );

  test('validation requires a title and an https image link', () {
    expect(validateSalesDraft(_draft()), isNull);
    expect(validateSalesDraft(_draft(title: '  ')), contains('title'));
    expect(
      validateSalesDraft(_draft(image: 'http://example.com/a.jpg')),
      contains('https://'),
    );
    expect(
      validateSalesDraft(_draft(image: 'https://example.com/a.jpg')),
      isNull,
    );
    expect(
      validateSalesDraft(_draft(features: List.filled(31, 'x'))),
      contains('30'),
    );
  });

  test('packages group by category in display order, and hidden ones show only to editors', () {
    final packages = [
      SalesPackage.fromJson(
        _row(
          id: 'c1',
          category: 'Club Seats',
          title: 'Club Full',
          sortOrder: 50,
        ),
      ),
      SalesPackage.fromJson(_row(id: 's2', title: 'Suite Half', sortOrder: 20)),
      SalesPackage.fromJson(_row(id: 's1', title: 'Suite Full', sortOrder: 10)),
      SalesPackage.fromJson(
        _row(id: 'h1', title: 'Hidden Suite', sortOrder: 30, active: false),
      ),
    ];

    final public = groupSalesPackages(packages);
    expect(public.map((g) => g.category), [
      'Allen Americans Suites',
      'Club Seats',
    ]);
    expect(public.first.packages.map((p) => p.id), ['s1', 's2']);

    final editor = groupSalesPackages(packages, includeInactive: true);
    expect(editor.first.packages.map((p) => p.id), ['s1', 's2', 'h1']);
  });
}
