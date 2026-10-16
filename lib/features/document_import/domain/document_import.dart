import '../../beo/domain/beo.dart';
import '../../events/domain/readiness.dart';

enum ImportKind {
  beo('beo', 'BEO'),
  menu('menu', 'menu');

  const ImportKind(this.code, this.label);

  final String code;
  final String label;
}

/// One dish or drink read from a document.
class ParsedMenuItem {
  const ParsedMenuItem({
    required this.name,
    required this.course,
    required this.dietaryTags,
    required this.allergens,
  });

  final String name;
  final String course;
  final List<String> dietaryTags;
  final String allergens;

  factory ParsedMenuItem.fromJson(Map<String, dynamic> json) => ParsedMenuItem(
    name: (json['name'] as String?) ?? '',
    course: (json['course'] as String?) ?? '',
    dietaryTags: ((json['dietary_tags'] as List?) ?? const []).cast<String>(),
    allergens: (json['allergens'] as String?) ?? '',
  );

  /// Same dish in the same course, ignoring case and spacing.
  bool sameAs(String otherName, String otherCourse) =>
      _key(name, course) == _key(otherName, otherCourse);

  static String _key(String name, String course) =>
      '${name.trim().toLowerCase()}|${course.trim().toLowerCase()}';
}

/// What the document assistant read. Nothing is saved until an administrator reviews it
/// in the BEO editor or the menu list.
class ImportResult {
  const ImportResult({
    required this.kind,
    required this.menuItems,
    required this.warnings,
    this.content,
    this.title = '',
    this.summary = '',
    this.guestsFound = true,
  });

  final ImportKind kind;

  /// The BEO, for a BEO import. Guests is 0 when the document gave no count.
  final BeoContent? content;
  final String title;
  final String summary;
  final bool guestsFound;
  final List<ParsedMenuItem> menuItems;
  final List<String> warnings;

  factory ImportResult.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] == ImportKind.beo.code
        ? ImportKind.beo
        : ImportKind.menu;
    final beo = (json['beo'] as Map?)?.cast<String, dynamic>();
    final guests = (beo?['guests'] as num?)?.toInt();
    return ImportResult(
      kind: kind,
      content: beo == null
          ? null
          : BeoContent.fromJson({...beo, 'guests': guests ?? 0}),
      title: (beo?['title'] as String?) ?? '',
      summary: (beo?['summary'] as String?) ?? '',
      guestsFound: beo == null || guests != null,
      menuItems: [
        for (final item in (json['menu_items'] as List?) ?? const [])
          if (item is Map)
            ParsedMenuItem.fromJson(item.cast<String, dynamic>()),
      ],
      warnings: [
        ...((json['warnings'] as List?) ?? const []).cast<String>(),
        if (beo != null && guests == null)
          'The document has no guest count. Enter it before saving.',
      ],
    );
  }

  /// Departments read for a BEO, for display.
  Set<Department> get departments => content?.departments ?? const {};
}

/// The administrator's choices on the import screen.
class ImportOutcome {
  const ImportOutcome({required this.result, required this.menuItems});

  final ImportResult result;

  /// The menu items chosen to add to the event's menu.
  final List<ParsedMenuItem> menuItems;
}
