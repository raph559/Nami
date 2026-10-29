import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/anilist.dart';
import 'package:nami/settings.dart';
import 'package:nami/theme.dart';
import 'package:nami/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Number of focus rings currently painted.
int rings() => find
    .byWidgetPredicate((w) => w is CustomPaint && w.foregroundPainter != null && w.foregroundPainter.runtimeType.toString() == '_RingPainter')
    .evaluate()
    .length;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.load();
  });

  testWidgets('Tab moves a visible focus ring through controls, Enter activates them', (tester) async {
    var played = 0;
    var retried = 0;
    await tester.pumpWidget(MaterialApp(
      theme: Nami.theme(),
      home: Scaffold(
        body: Column(children: [
          FocusOutline(child: FilledButton(onPressed: () => played++, child: const Text('Regarder'))),
          MediaCard(Media({'id': 1, 'title': {'romaji': 'Test'}})),
          StateMessage(title: 'Erreur', action: 'Réessayer', onAction: () => retried++),
        ]),
      ),
    ));

    expect(rings(), 0, reason: 'no ring before keyboard use');

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(rings(), 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(played, 1, reason: 'Enter activates the focused button');

    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // anime card
    await tester.pump();
    expect(rings(), 1);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<MediaCard>(), isNotNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // retry button
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(retried, 1, reason: 'Space activates too');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<MediaCard>(), isNotNull,
        reason: 'Shift+Tab goes back in visual order');
  });

  test('accent colors are lifted to 4.5:1 on the black ground', () {
    for (final c in const [Color(0xFF1A237E), Color(0xFF8B0000), Color(0xFF0A0A0B), Color(0xFFFE286B)]) {
      expect(Nami.contrast(Nami.accentOf(c), Nami.ground), greaterThanOrEqualTo(4.5), reason: '$c');
    }
  });
}
