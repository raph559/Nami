import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/profile.dart';
import 'package:nami/settings.dart';
import 'package:nami/theme.dart';
import 'package:nami/ui/favourite_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpButton(
  WidgetTester tester,
  Future<void> Function(FavouriteKind, int) toggle, {
  Future<bool> Function(FavouriteKind, int)? check,
}) async {
  SharedPreferences.setMockInitialValues({'appLanguage': 'fr'});
  await AppSettings.load();
  await tester.pumpWidget(
    MaterialApp(
      theme: Nami.theme(),
      home: Scaffold(
        body: Center(
          child: FavouriteButton(
            kind: FavouriteKind.anime,
            id: 1,
            initial: false,
            toggle: toggle,
            check: check ?? (_, _) async => false,
          ),
        ),
      ),
    ),
  );
}

void main() {
  tearDown(FavouriteButton.forget);

  testWidgets('a confirmed change is remembered when the heart is built again', (tester) async {
    await pumpButton(tester, (_, _) async {});
    await tester.tap(find.byType(FavouriteButton));
    await tester.pumpAndSettle();
    // Leaving the tab and coming back builds a new button from the details loaded before.
    await tester.pumpWidget(const SizedBox());
    await pumpButton(tester, (_, _) async {});
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('the heart fills at once', (tester) async {
    final done = Completer<void>();
    await pumpButton(tester, (_, _) => done.future);
    await tester.tap(find.byType(FavouriteButton));
    await tester.pump();
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    done.complete();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('the heart goes back when AniList refuses', (tester) async {
    await pumpButton(tester, (_, _) async => throw Exception('offline'));
    await tester.tap(find.byType(FavouriteButton));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.text("Les favoris n'ont pas pu être modifiés."), findsOneWidget);
  });

  testWidgets('two quick taps end as the last one', (tester) async {
    var calls = 0;
    var running = 0;
    var most = 0;
    var favourite = false;
    await pumpButton(tester, (_, _) async {
      calls++;
      running++;
      most = running > most ? running : most;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      favourite = !favourite;
      running--;
    });
    await tester.tap(find.byType(FavouriteButton));
    await tester.pump();
    await tester.tap(find.byType(FavouriteButton));
    await tester.pump();
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    // Each toggle flips it: an even number of calls leaves it off, as wanted.
    expect(calls, 2);
    expect(most, 1);
    expect(favourite, isFalse);
  });

  testWidgets('an answer lost after AniList made the change keeps the heart', (tester) async {
    await pumpButton(tester, (_, _) async => throw Exception('timeout'), check: (_, _) async => true);
    await tester.tap(find.byType(FavouriteButton));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.text("Les favoris n'ont pas pu être modifiés."), findsNothing);
  });

  testWidgets('after a failure it cannot check, the next tap asks AniList first', (tester) async {
    var online = false;
    var toggles = 0;
    await pumpButton(tester, (_, _) async {
      toggles++;
      // The change reaches AniList, the answer does not.
      throw Exception('timeout');
    }, check: (_, _) async => online ? true : throw Exception('offline'));
    await tester.tap(find.byType(FavouriteButton));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    online = true;
    await tester.tap(find.byType(FavouriteButton));
    await tester.pumpAndSettle();
    // AniList already has it: nothing more is sent, which would have removed it.
    expect(toggles, 1);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });
}
