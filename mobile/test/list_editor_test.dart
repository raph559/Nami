import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/anilist.dart';
import 'package:nami/screens/list_editor.dart';
import 'package:nami/settings.dart';
import 'package:nami/theme.dart';
import 'package:nami/ui/tags.dart';
import 'package:shared_preferences/shared_preferences.dart';

Media anime({Map<String, dynamic>? entry, int episodes = 12}) => Media({
  'id': 1,
  'title': {'romaji': 'Test'},
  'episodes': episodes,
  'format': 'TV',
  'mediaListEntry': entry,
});

Future<void> pump(WidgetTester tester, Media media) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: Nami.theme(),
      home: Scaffold(body: ListEditor(media: media)),
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'appLanguage': 'en'});
    await AppSettings.load();
  });

  test('withEntry replaces or removes the list entry', () {
    final m = anime(entry: {'id': 5, 'progress': 3, 'status': 'CURRENT', 'score': 80});
    expect(m.progress, 3);
    expect(m.withEntry(ListEntry(id: 5, progress: 4, status: 'PAUSED')).listEntry!.status, 'PAUSED');
    expect(m.withEntry(null).listEntry, isNull);
    expect(m.withEntry(null).progress, 0);
  });

  testWidgets('a new anime starts as planned and can be added', (tester) async {
    await pump(tester, anime());
    expect(find.text('Not in your list yet'), findsOneWidget);
    expect(find.text('Add to my list'), findsOneWidget);
    expect(find.text('Remove'), findsNothing);
    expect(find.text('0 / 12'), findsOneWidget);
    expect(find.text('Not rated'), findsOneWidget);
  });

  testWidgets('one more episode moves a planned anime to watching', (tester) async {
    await pump(tester, anime());
    await tester.tap(find.byTooltip('One more'));
    await tester.pump();
    expect(find.text('1 / 12'), findsOneWidget);
    final chip = tester.widget<FlatTag>(find.widgetWithText(FlatTag, 'Watching'));
    expect(chip.selected, isTrue);
  });

  testWidgets('completing ticks off every episode', (tester) async {
    await pump(tester, anime(entry: {'id': 5, 'progress': 3, 'status': 'CURRENT', 'score': 75}));
    expect(find.text('7.5 / 10'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    await tester.tap(find.widgetWithText(FlatTag, 'Completed'));
    await tester.pump();
    expect(find.text('12 / 12'), findsOneWidget);
    expect(find.byTooltip('One more'), findsOneWidget);
    final more = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add));
    expect(more.onPressed, isNull);
  });
}
