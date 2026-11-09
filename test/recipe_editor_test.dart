import 'package:fitness_mobile/core/api.dart';
import 'package:fitness_mobile/core/session.dart';
import 'package:fitness_mobile/features/nutrition/recipe_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Answers food searches and keeps what the editor sends.
class FakeApi extends ApiClient {
  FakeApi(super.sessions);

  final posts = <String, Object?>{};

  static const egg = {
    'id': 'egg',
    'name': 'Egg, whole',
    'source': 'hxvy',
    'serving': '1 large egg (50 g)',
    'calories': 72,
    'protein_g': 6.3,
    'carbs_g': 0.4,
    'fat_g': 4.8,
  };

  // A recipe never shows when picking an ingredient.
  static final shake = {...egg, 'id': 'shake', 'name': 'My shake', 'source': 'recipe', 'serving': '1 serving'};

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async => switch (path) {
    '/foods' => {
      'items': [shake, egg],
      'total': 2,
    },
    _ => throw StateError('No fake answer for $path'),
  };

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    posts[path] = body;
    return {'id': 'new-recipe'};
  }
}

void main() {
  late FakeApi api;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    api = FakeApi(SessionStore());
  });

  /// A home page with a button that opens the editor, as the app pushes it.
  Future<void> openEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400); // a phone: 360 × 800
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: TextButton(onPressed: () => context.push('/new'), child: const Text('Open editor')),
            ),
          ),
          routes: [GoRoute(path: 'new', builder: (context, state) => const RecipeEditor())],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        retry: (retryCount, error) => null,
        overrides: [apiProvider.overrideWithValue(api)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }

  FilledButton saveButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save recipe'));

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('a recipe is made from ingredients weighed in grams, and saved', (tester) async {
    await openEditor(tester);
    expect(find.text('New recipe'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull, reason: 'nothing to save yet');

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Egg bowl');
    await tester.enterText(find.widgetWithText(TextField, 'Servings it makes'), '2');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNull, reason: 'a recipe needs at least one ingredient');

    // Pick the egg from the search. The recipe in the results is not offered.
    await tapVisible(tester, find.text('Add ingredient'));
    expect(find.text('Add an ingredient'), findsOneWidget);
    expect(find.text('My shake'), findsNothing);
    await tester.tap(find.text('Egg, whole'));
    await tester.pumpAndSettle();

    // 100 g of a 50 g egg is 2 servings, 144 kcal.
    await tester.enterText(find.widgetWithText(TextField, 'Grams'), '100');
    await tester.pump();
    expect(find.text('144'), findsOneWidget);
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Add to recipe'));

    // Back in the editor: the ingredient, and one of the 2 servings is 72 kcal.
    expect(find.text('Egg, whole'), findsOneWidget);
    expect(find.text('100 g'), findsOneWidget);
    expect(find.text('72'), findsOneWidget);
    expect(find.text('144 kcal in all'), findsOneWidget);

    await tapVisible(tester, find.widgetWithText(FilledButton, 'Save recipe'));
    expect(api.posts['/recipes'], {
      'name': 'Egg bowl',
      'portions': 2,
      'cooked_weight_g': null,
      'ingredients': [
        {'food_id': 'egg', 'servings': 2.0},
      ],
    });
    expect(find.text('Open editor'), findsOneWidget, reason: 'saving goes back to where the editor was opened');
  });

  testWidgets('the cooked weight tells what one serving weighs', (tester) async {
    await openEditor(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Servings it makes'), '4');
    await tester.enterText(find.widgetWithText(TextField, 'Cooked weight'), '1200');
    await tester.pump();
    expect(find.text('One serving weighs 300 g, so you can log it in grams.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Servings it makes'), '0');
    await tester.pump();
    expect(find.text('1 to 100'), findsOneWidget);
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    await openEditor(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Half typed');
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Leave without saving?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('New recipe'), findsOneWidget, reason: 'Cancel stays in the editor');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Open editor'), findsOneWidget);
    expect(api.posts, isEmpty);
  });
}
