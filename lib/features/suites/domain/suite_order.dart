/// Suite order states: Draft → Confirmed → Delivered. Editing a confirmed
/// order returns it to draft so the change is confirmed again.
enum SuiteOrderStatus {
  draft('draft', 'Draft'),
  confirmed('confirmed', 'Confirmed'),
  delivered('delivered', 'Delivered');

  const SuiteOrderStatus(this.code, this.label);

  final String code;
  final String label;

  static SuiteOrderStatus fromCode(String code) =>
      values.firstWhere((s) => s.code == code);

  /// The only state an order may move to next. Null once delivered.
  SuiteOrderStatus? get next =>
      index + 1 < values.length ? values[index + 1] : null;
}

class SuiteOrderItem {
  const SuiteOrderItem({
    required this.name,
    required this.quantity,
    this.notes = '',
  });

  final String name;
  final int quantity;
  final String notes;

  Map<String, dynamic> toJson() => {
    'name': name,
    'quantity': quantity,
    'notes': notes,
  };

  factory SuiteOrderItem.fromJson(Map<String, dynamic> json) => SuiteOrderItem(
    name: (json['name'] as String?) ?? '',
    quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    notes: (json['notes'] as String?) ?? '',
  );
}

/// The food and beverage order for one suite at one event.
class SuiteOrder {
  const SuiteOrder({
    required this.id,
    required this.assignmentId,
    required this.status,
    required this.items,
    required this.version,
    this.deliverAt,
    this.notes = '',
  });

  final String id;
  final String assignmentId;
  final SuiteOrderStatus status;
  final List<SuiteOrderItem> items;
  final int version;
  final DateTime? deliverAt;
  final String notes;

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  factory SuiteOrder.fromJson(Map<String, dynamic> json) => SuiteOrder(
    id: json['id'] as String,
    assignmentId: json['assignment_id'] as String,
    status: SuiteOrderStatus.fromCode(json['status'] as String),
    items: [
      for (final item in (json['items'] as List? ?? const []))
        SuiteOrderItem.fromJson((item as Map).cast<String, dynamic>()),
    ],
    version: (json['version'] as num).toInt(),
    deliverAt: json['deliver_at'] == null
        ? null
        : DateTime.parse(json['deliver_at'] as String),
    notes: (json['notes'] as String?) ?? '',
  );
}
