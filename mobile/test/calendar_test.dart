import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/anilist.dart';
import 'package:nami/platform.dart';
import 'package:nami/screens/calendar.dart';
import 'package:nami/settings.dart';
import 'package:nami/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

Media anime(int id) => Media({
  'id': id,
  'title': {'romaji': 'Anime $id'},
  'format': 'TV',
  'coverImage': <String, dynamic>{},
});

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'appLanguage': 'en'});
    await AppSettings.load();
  });

  test('episodes land on their local day, and the week has seven days', () {
    final now = DateTime(2026, 10, 30, 22);
    final days = weekDays([
      AiringItem(anime(1), 1, DateTime(2026, 10, 30, 23, 59)),
      AiringItem(anime(2), 2, DateTime(2026, 10, 31, 0, 1)),
      AiringItem(anime(3), 3, DateTime(2026, 11, 5, 12)),
      AiringItem(anime(4), 4, DateTime(2026, 11, 6, 0, 1)),
    ], now);
    expect(days.length, 7);
    expect(days[0].$2.map((i) => i.media.id), [1]);
    expect(days[1].$2.map((i) => i.media.id), [2]);
    expect(days[6].$1, DateTime(2026, 11, 5));
    expect(days[6].$2.map((i) => i.media.id), [3]);
    expect(days.expand((d) => d.$2).length, 3);
  });

  test('the week crosses a month and a clock change without skipping a day', () {
    final days = weekDays(const [], DateTime(2026, 10, 24, 12));
    expect([for (final d in days) d.$1.day], [24, 25, 26, 27, 28, 29, 30]);
  });

  test('days read today, tomorrow, then weekday and date', () {
    expect(dayLabel(DateTime(2026, 10, 30), 0), 'Today');
    expect(dayLabel(DateTime(2026, 10, 31), 1), 'Tomorrow');
    expect(dayLabel(DateTime(2026, 11, 1), 2), 'Sun 1');
  });

  Widget host(CalendarScreen screen) => MaterialApp(home: screen);

  testWidgets('a day tab shows that day, and the list filter hides the rest', (tester) async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 12);
    await tester.pumpWidget(
      host(
        CalendarScreen(
          listIds: const {2},
          load: () async => [
            AiringItem(anime(1), 1, DateTime(now.year, now.month, now.day, 23, 59)),
            AiringItem(anime(2), 2, tomorrow),
            AiringItem(anime(3), 3, tomorrow),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Anime 1'), findsOneWidget);
    expect(find.text('Anime 2'), findsNothing);

    await tester.tap(find.text('Tomorrow'));
    await tester.pump();
    expect(find.text('Anime 2'), findsOneWidget);
    expect(find.text('Anime 3'), findsOneWidget);
    expect(find.text('In your list'), findsOneWidget);

    await tester.tap(find.text('Only my list'));
    await tester.pump();
    expect(find.text('Anime 2'), findsOneWidget);
    expect(find.text('Anime 3'), findsNothing);
  });

  testWidgets('the badge shows the count, and nothing at zero', (tester) async {
    addTearDown(() => AniList.instance.newEpisodes.value = 0);
    AniList.instance.newEpisodes.value = 3;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: NewEpisodesBadge(child: Icon(Icons.bookmark))),
      ),
    );
    expect(find.text('3'), findsOneWidget);

    AniList.instance.newEpisodes.value = 0;
    await tester.pump();
    expect(find.text('0'), findsNothing);
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
  });

  testWidgets('times follow the language of the app', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox));
    expect(clockTime(context, DateTime(2026, 10, 31, 0, 30)), '12:30 AM');

    SharedPreferences.setMockInitialValues({'appLanguage': 'fr'});
    await AppSettings.load();
    expect(clockTime(context, DateTime(2026, 10, 31, 0, 30)), '00:30');
    expect(clockTime(context, DateTime(2026, 10, 31, 21, 5)), '21:05');
  });

  testWidgets('on desktop the day fills the width, with the filter beside the tabs', (tester) async {
    debugDesktopOverride = true;
    addTearDown(() => debugDesktopOverride = null);
    tester.view.physicalSize = const Size(1300, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final at = DateTime(now.year, now.month, now.day, 23, 59);
    await tester.pumpWidget(
      host(
        CalendarScreen(
          listIds: const {1},
          load: () async => [AiringItem(anime(1), 1, at), AiringItem(anime(2), 2, at), AiringItem(anime(3), 3, at)],
        ),
      ),
    );
    await tester.pump();
    expect(tester.getTopLeft(find.text('Anime 2')).dy, tester.getTopLeft(find.text('Anime 1')).dy);
    expect(tester.getTopLeft(find.text('Anime 3')).dx, greaterThan(800));
    expect(tester.getTopLeft(find.text('Only my list')).dy, lessThan(tester.getTopLeft(find.text('Anime 1')).dy));
    expect(find.byType(SwitchListTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no list means no filter', (tester) async {
    await tester.pumpWidget(host(CalendarScreen(load: () async => [])));
    await tester.pump();
    expect(find.text('Only my list'), findsNothing);
    expect(find.text('No episodes that day'), findsOneWidget);
  });

  testWidgets('a failed load says so and can be tried again', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      host(
        CalendarScreen(
          load: () async {
            if (calls++ == 0) throw Exception('down');
            return [AiringItem(anime(1), 1, DateTime.now())];
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Calendar unavailable'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Anime 1'), findsOneWidget);
  });
}
