/// One line of pricing: what is being sold, its price, and how the price is made up.
class SalesPriceRow {
  const SalesPriceRow({
    required this.label,
    required this.price,
    this.detail = '',
  });

  final String label;
  final String price;
  final String detail;

  Map<String, String> toJson() => {
    'label': label,
    'price': price,
    'detail': detail,
  };

  factory SalesPriceRow.fromJson(Map<String, dynamic> json) => SalesPriceRow(
    label: (json['label'] as String?) ?? '',
    price: (json['price'] as String?) ?? '',
    detail: (json['detail'] as String?) ?? '',
  );
}

/// A premium offering on the Sales page. Prices are the text shown to buyers.
class SalesPackage {
  const SalesPackage({
    required this.id,
    required this.venueId,
    required this.category,
    required this.title,
    required this.summary,
    required this.features,
    required this.priceRows,
    required this.priceNote,
    required this.sortOrder,
    required this.active,
    required this.version,
    this.imageUrl,
  });

  final String id;
  final String venueId;
  final String category;
  final String title;
  final String summary;
  final List<String> features;
  final List<SalesPriceRow> priceRows;
  final String priceNote;
  final String? imageUrl;
  final int sortOrder;
  final bool active;
  final int version;

  /// The headline price for a card: the first row's price, or nothing when there is none.
  String get headlinePrice => priceRows.isEmpty ? '' : priceRows.first.price;

  factory SalesPackage.fromJson(Map<String, dynamic> json) => SalesPackage(
    id: json['id'] as String,
    venueId: json['venue_id'] as String,
    category: (json['category'] as String?) ?? '',
    title: json['title'] as String,
    summary: (json['summary'] as String?) ?? '',
    features: ((json['features'] as List?) ?? const []).cast<String>(),
    priceRows: [
      for (final row in (json['price_rows'] as List? ?? const []))
        SalesPriceRow.fromJson((row as Map).cast<String, dynamic>()),
    ],
    priceNote: (json['price_note'] as String?) ?? '',
    imageUrl: json['image_url'] as String?,
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    active: json['active'] as bool? ?? true,
    version: (json['version'] as num?)?.toInt() ?? 1,
  );
}

/// The editable parts of a package, as entered in the editor.
class SalesPackageDraft {
  const SalesPackageDraft({
    required this.category,
    required this.title,
    required this.summary,
    required this.features,
    required this.priceRows,
    required this.priceNote,
    required this.imageUrl,
    required this.active,
  });

  final String category;
  final String title;
  final String summary;
  final List<String> features;
  final List<SalesPriceRow> priceRows;
  final String priceNote;
  final String imageUrl;
  final bool active;

  /// Columns for an insert or update. Blank feature lines and empty price rows are dropped.
  Map<String, Object?> toColumns() => {
    'category': category.trim(),
    'title': title.trim(),
    'summary': summary.trim(),
    'features': [
      for (final f in features)
        if (f.trim().isNotEmpty) f.trim(),
    ],
    'price_rows': [
      for (final r in priceRows)
        if (r.label.trim().isNotEmpty || r.price.trim().isNotEmpty)
          SalesPriceRow(
            label: r.label.trim(),
            price: r.price.trim(),
            detail: r.detail.trim(),
          ).toJson(),
    ],
    'price_note': priceNote.trim(),
    'image_url': imageUrl.trim().isEmpty ? null : imageUrl.trim(),
    'active': active,
  };
}

/// Returns the first problem with a draft, or null when it can be saved.
String? validateSalesDraft(SalesPackageDraft draft) {
  final title = draft.title.trim();
  if (title.isEmpty || title.length > 120) {
    return 'Give the package a title (up to 120 characters).';
  }
  if (draft.category.trim().length > 60) {
    return 'The category is too long (up to 60 characters).';
  }
  if (draft.summary.trim().length > 2000) {
    return 'The description is too long (up to 2,000 characters).';
  }
  if (draft.priceNote.trim().length > 1000) {
    return 'The pricing note is too long (up to 1,000 characters).';
  }
  final image = draft.imageUrl.trim();
  if (image.isNotEmpty && !image.startsWith('https://')) {
    return 'The image link must start with https://.';
  }
  if (draft.features.where((f) => f.trim().isNotEmpty).length > 30) {
    return 'Up to 30 features.';
  }
  if (draft.priceRows.length > 20) return 'Up to 20 price rows.';
  return null;
}

/// Packages grouped by category, in display order. Inactive packages are left out unless
/// [includeInactive] is set (for people who can edit them).
List<({String category, List<SalesPackage> packages})> groupSalesPackages(
  List<SalesPackage> packages, {
  bool includeInactive = false,
}) {
  final shown = [
    for (final p in packages)
      if (includeInactive || p.active) p,
  ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final groups = <String, List<SalesPackage>>{};
  for (final p in shown) {
    groups
        .putIfAbsent(
          p.category.isEmpty ? 'Other offerings' : p.category,
          () => [],
        )
        .add(p);
  }
  return [
    for (final entry in groups.entries)
      (category: entry.key, packages: entry.value),
  ];
}
