import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/sales_package.dart';

/// Adds or edits a package: its text, features, and every price. Returns null when cancelled.
Future<SalesPackageDraft?> showSalesPackageEditor(
  BuildContext context, {
  SalesPackage? existing,
}) {
  return showDialog<SalesPackageDraft>(
    context: context,
    builder: (_) => _SalesPackageEditor(existing: existing),
  );
}

class _PriceRowFields {
  _PriceRowFields([SalesPriceRow? row])
    : label = TextEditingController(text: row?.label ?? ''),
      price = TextEditingController(text: row?.price ?? ''),
      detail = TextEditingController(text: row?.detail ?? '');

  final TextEditingController label;
  final TextEditingController price;
  final TextEditingController detail;

  void dispose() {
    label.dispose();
    price.dispose();
    detail.dispose();
  }
}

class _SalesPackageEditor extends StatefulWidget {
  const _SalesPackageEditor({this.existing});

  final SalesPackage? existing;

  @override
  State<_SalesPackageEditor> createState() => _SalesPackageEditorState();
}

class _SalesPackageEditorState extends State<_SalesPackageEditor> {
  late final _category = TextEditingController(
    text: widget.existing?.category ?? '',
  );
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _summary = TextEditingController(
    text: widget.existing?.summary ?? '',
  );
  late final _features = TextEditingController(
    text: (widget.existing?.features ?? const []).join('\n'),
  );
  late final _priceNote = TextEditingController(
    text: widget.existing?.priceNote ?? '',
  );
  late final _imageUrl = TextEditingController(
    text: widget.existing?.imageUrl ?? '',
  );
  late final List<_PriceRowFields> _rows = [
    for (final row in widget.existing?.priceRows ?? const <SalesPriceRow>[])
      _PriceRowFields(row),
    if ((widget.existing?.priceRows ?? const []).isEmpty) _PriceRowFields(),
  ];
  late bool _active = widget.existing?.active ?? true;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _category,
      _title,
      _summary,
      _features,
      _priceNote,
      _imageUrl,
    ]) {
      c.dispose();
    }
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _removeRow(int index) {
    final removed = _rows.removeAt(index);
    setState(() {});
    // The fields still use these controllers until the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  void _save() {
    final draft = SalesPackageDraft(
      category: _category.text,
      title: _title.text,
      summary: _summary.text,
      features: _features.text.split('\n'),
      priceRows: [
        for (final row in _rows)
          SalesPriceRow(
            label: row.label.text,
            price: row.price.text,
            detail: row.detail.text,
          ),
      ],
      priceNote: _priceNote.text,
      imageUrl: _imageUrl.text,
      active: _active,
    );
    final problem = validateSalesDraft(draft);
    if (problem != null) return setState(() => _error = problem);
    Navigator.of(context).pop(draft);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add package' : 'Edit package'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  helperText:
                      'Packages with the same category are shown together.',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _summary,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 16),
              Text('Pricing', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              for (final (index, row) in _rows.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            TextField(
                              controller: row.label,
                              decoration: const InputDecoration(
                                labelText: 'Option',
                                hintText: 'Gold · 14 seats',
                              ),
                            ),
                            TextField(
                              controller: row.detail,
                              decoration: const InputDecoration(
                                labelText: 'Detail',
                                hintText: '\$700 per game · 36 games',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: row.price,
                          decoration: const InputDecoration(
                            labelText: 'Price',
                            hintText: '\$25,200',
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove this price',
                        onPressed: () => _removeRow(index),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: () => setState(() => _rows.add(_PriceRowFields())),
                icon: const Icon(Icons.add),
                label: const Text('Add price'),
              ),
              TextField(
                controller: _priceNote,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Pricing note (optional)',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _features,
                minLines: 3,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Features and benefits',
                  helperText: 'One per line.',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _imageUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Image link (https://, optional)',
                ),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (on) => setState(() => _active = on),
                title: const Text('Show on the Sales page'),
                subtitle: const Text(
                  'Hidden packages are visible only to people who can edit them.',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: AppColors.blocked)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
