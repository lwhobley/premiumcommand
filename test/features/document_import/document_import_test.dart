import 'package:cutx_premium_command/core/permissions/app_permission.dart';
import 'package:cutx_premium_command/features/auth/application/session_controller.dart';
import 'package:cutx_premium_command/features/document_import/data/document_import_repository.dart';
import 'package:cutx_premium_command/features/document_import/domain/document_import.dart';
import 'package:cutx_premium_command/features/document_import/presentation/document_import_screen.dart';
import 'package:cutx_premium_command/features/events/domain/readiness.dart';
import 'package:cutx_premium_command/features/operations/application/operations_providers.dart';
import 'package:cutx_premium_command/features/operations/domain/operations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Returns a fixed result for pasted text and records what was sent. No network.
class _FakeRepository extends DocumentImportRepository {
  _FakeRepository(this.result)
    : super(
        SupabaseClient(
          'http://localhost',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final Map<String, dynamic> result;
  String? sentText;
  ImportKind? sentKind;

  @override
  Future<ImportResult> read({
    required String venueId,
    required String eventId,
    required ImportKind kind,
    String? path,
    String? text,
  }) async {
    sentText = text;
    sentKind = kind;
    return ImportResult.fromJson(result);
  }
}

void main() {
  group('ImportResult', () {
    test('reads a BEO, keeping a missing guest count visible', () {
      final result = ImportResult.fromJson({
        'kind': 'beo',
        'beo': {
          'title': 'Acme dinner',
          'guests': null,
          'departments': ['culinary', 'banquets', 'unknown'],
          'timeline': '6:00 PM Reception',
          'menu': 'Salmon',
          'dietary': '',
          'beverage': '',
          'equipment': '',
          'special_requests': '',
          'summary': 'From the client PDF.',
        },
        'menu_items': [
          {
            'name': 'Salmon',
            'course': 'Entrée',
            'dietary_tags': ['GF'],
            'allergens': 'Fish',
          },
        ],
        'warnings': ['Page 2 was blurry.'],
      });
      expect(result.kind, ImportKind.beo);
      expect(result.title, 'Acme dinner');
      expect(result.content!.guests, 0);
      expect(result.guestsFound, isFalse);
      expect(result.departments, {Department.culinary, Department.banquets});
      expect(result.warnings, hasLength(2));
      expect(result.warnings.last, contains('no guest count'));
      expect(result.menuItems.single.dietaryTags, ['GF']);
    });

    test('reads a menu without a BEO', () {
      final result = ImportResult.fromJson({
        'kind': 'menu',
        'menu_items': [
          {
            'name': 'Sorbet',
            'course': 'Dessert',
            'dietary_tags': [],
            'allergens': '',
          },
        ],
        'warnings': [],
      });
      expect(result.kind, ImportKind.menu);
      expect(result.content, isNull);
      expect(result.warnings, isEmpty);
    });

    test('menu items match ignoring case and spacing', () {
      const item = ParsedMenuItem(
        name: ' Seared Salmon',
        course: 'Entrée ',
        dietaryTags: [],
        allergens: '',
      );
      expect(item.sameAs('seared salmon', 'entrée'), isTrue);
      expect(item.sameAs('Seared salmon', 'Lunch'), isFalse);
    });
  });

  testWidgets(
    'pasted menu text is read, reviewed, and only new chosen items come back',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _FakeRepository({
        'kind': 'menu',
        'menu_items': [
          {
            'name': 'Sorbet',
            'course': 'Dessert',
            'dietary_tags': ['VG'],
            'allergens': '',
          },
          {
            'name': 'Wings',
            'course': 'Appetizer',
            'dietary_tags': [],
            'allergens': 'Celery',
          },
          {
            'name': 'Caesar salad',
            'course': 'Salad',
            'dietary_tags': [],
            'allergens': 'Egg',
          },
        ],
        'warnings': ['Prices were left out.'],
      });
      final container = ProviderContainer(
        overrides: [
          documentImportRepositoryProvider.overrideWithValue(repo),
          menuProvider.overrideWith(
            (ref, eventId) async => const [
              MenuItem(
                id: 'm1',
                name: 'wings',
                course: 'appetizer',
                dietaryTags: [],
                allergens: '',
              ),
            ],
          ),
        ],
      );
      container.read(sessionProvider.notifier).signInAsDemo(AppRole.director);

      ImportOutcome? outcome;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async => outcome = await showDocumentImport(
                  context,
                  kind: ImportKind.menu,
                  eventId: 'event-1',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField),
        'Sorbet\nWings\nCaesar salad',
      );
      await tester.tap(find.text('Read pasted text'));
      await tester.pumpAndSettle();

      expect(repo.sentText, 'Sorbet\nWings\nCaesar salad');
      expect(repo.sentKind, ImportKind.menu);
      expect(find.textContaining('Prices were left out.'), findsOneWidget);
      expect(find.textContaining('Already on the menu'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Leave out the salad. Wings is already on the menu and cannot be chosen.
      await tester.tap(find.text('Caesar salad'));
      await tester.pump();
      await tester.tap(find.text('Add 1 item to the menu'));
      await tester.pumpAndSettle();

      expect(outcome!.menuItems.map((i) => i.name), ['Sorbet']);

      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );
}
