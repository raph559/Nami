import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/anilist.dart';
import 'package:nami/mappings.dart';
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
    debugDesktopOverride = false;
  });
  tearDown(() => debugDesktopOverride = null);

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

  test('a week reads as its days, across two months too', () {
    expect(weekRange(DateTime(2026, 11, 2)), 'Nov 2 – 8');
    expect(weekRange(DateTime(2026, 10, 26)), 'Oct 26 – Nov 1');
  });

  test('the fanart comes from the images of the mappings', () {
    expect(Mappings({}).fanart, isNull);
    expect(
      Mappings({
        'images': [
          {'coverType': 'Banner', 'url': 'banner'},
          {'coverType': 'Fanart', 'url': 'wide'},
        ],
      }).fanart,
      'wide',
    );
  });

  test('months read in full, in the language of the app', () {
    expect(monthTitle(DateTime(2026, 11, 2)), 'November 2026');
  });

  Widget host(CalendarScreen screen) => MaterialApp(home: screen);

  testWidgets('the phone shows the strip of days, opens on today, and a day shows that day', (tester) async {
    final now = DateTime.now();
    final other = DateTime(now.year, now.month, now.day + 1, 12);
    await tester.pumpWidget(
      host(
        CalendarScreen(
          listIds: const {2},
          load: (_) async => [
            AiringItem(anime(1), 1, DateTime(now.year, now.month, now.day, 23, 59)),
            AiringItem(anime(2), 2, other),
            AiringItem(anime(3), 3, other),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.text(monthTitle(now)), findsOneWidget);
    expect(find.text('Anime 1'), findsOneWidget);
    expect(find.text('Anime 2'), findsNothing);
    expect(find.text('Today'), findsNothing);

    await tester.tap(find.text('${other.day}'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Anime 2'), findsOneWidget);
    expect(find.text('Anime 3'), findsOneWidget);
    expect(find.text('In your list'), findsOneWidget);

    await tester.tap(find.text('Only my list'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Anime 2'), findsOneWidget);
    expect(find.text('Anime 3'), findsNothing);

    await tester.tap(find.text('Today'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Today'), findsNothing);
  });

  testWidgets('a swipe moves to the next or previous week, keeping the weekday', (tester) async {
    final today = dayStart(DateTime.now());
    final asked = <DateTime>[];
    await tester.pumpWidget(
      host(
        CalendarScreen(
          load: (start) async {
            asked.add(start);
            return [];
          },
        ),
      ),
    );
    await tester.pump();
    await tester.fling(find.text('${DateTime.now().day}'), const Offset(-300, 0), 1000);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(asked.last, DateTime(today.year, today.month, today.day + 7));
    expect(find.text('Today'), findsOneWidget);

    await tester.tap(find.text('Today'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(asked.last, today);
  });

  testWidgets('today has a line for the current time, other days do not', (tester) async {
    final now = DateTime.now();
    final past = now.subtract(const Duration(minutes: 1));
    await tester.pumpWidget(
      host(CalendarScreen(load: (_) async => [AiringItem(anime(1), 1, past.day == now.day ? past : now)])),
    );
    await tester.pump();
    expect(find.byType(NowLine), findsOneWidget);
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

  group('desktop week', () {
    final today = dayStart(DateTime.now());
    DateTime at(int day, int hour) => DateTime(today.year, today.month, today.day + day, hour);

    Future<List<DateTime>> pumpWeek(WidgetTester tester, {Size size = const Size(1300, 700), double text = 1}) async {
      debugDesktopOverride = true;
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final asked = <DateTime>[];
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(text)),
            child: child!,
          ),
          home: CalendarScreen(
            listIds: const {2},
            load: (start) async {
              asked.add(start);
              return [
                AiringItem(anime(1), 1, at(0, 12)),
                AiringItem(anime(2), 2, at(1, 12)),
                AiringItem(anime(3), 3, at(6, 12)),
              ];
            },
          ),
        ),
      );
      await tester.pump();
      return asked;
    }

    testWidgets('today comes first, with one column per day in order', (tester) async {
      final asked = await pumpWeek(tester);
      expect(asked, [today]);
      for (var i = 0; i < 7; i++) {
        expect(find.text(weekdayName(at(i, 12))), findsOneWidget);
      }
      double x(String text) => tester.getTopLeft(find.text(text)).dx;
      expect(x('Anime 1'), lessThan(x('Anime 2')));
      expect(x('Anime 2'), lessThan(x('Anime 3')));
      // Under its own day.
      expect(x('Anime 3') - x(weekdayName(at(6, 12))), inInclusiveRange(0, 60));
      expect(x(weekdayName(at(0, 12))), lessThan(x(weekdayName(at(1, 12)))));
      expect(tester.takeException(), isNull);
    });

    testWidgets('pages through the weeks and comes back', (tester) async {
      final asked = await pumpWeek(tester);
      expect(find.text('Today'), findsNothing);

      await tester.tap(find.byTooltip('Next week'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(asked.last, DateTime(today.year, today.month, today.day + 7));

      await tester.tap(find.text('Today'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(asked.last, today);

      await tester.tap(find.byTooltip('Previous week'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(asked.last, DateTime(today.year, today.month, today.day - 7));
    });

    testWidgets('the filter sits at the right end, and a new week slides in', (tester) async {
      await pumpWeek(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getTopRight(find.byType(Switch)).dx, greaterThan(1300 - 40));

      SlideTransition? moving() => tester
          .widgetList<SlideTransition>(find.byType(SlideTransition))
          .where((t) => t.position.value != Offset.zero)
          .firstOrNull;
      expect(moving(), isNull);
      await tester.tap(find.byTooltip('Next week'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(moving(), isNotNull);
      await tester.pump(const Duration(seconds: 1));
      expect(moving(), isNull);
    });

    testWidgets('the list filter works from its label', (tester) async {
      await pumpWeek(tester);
      await tester.tap(find.text('Only my list'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Anime 2'), findsOneWidget);
      expect(find.text('Anime 1'), findsNothing);
      expect(find.byIcon(Icons.bookmark), findsOneWidget);
    });

    testWidgets('holds in a small window and at large text', (tester) async {
      await pumpWeek(tester, size: const Size(900, 600), text: 2);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('no list means no filter', (tester) async {
    await tester.pumpWidget(host(CalendarScreen(load: (_) async => [])));
    await tester.pump();
    expect(find.text('Only my list'), findsNothing);
    expect(find.text('No episodes that day'), findsOneWidget);
  });

  testWidgets('a failed load says so and can be tried again', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      host(
        CalendarScreen(
          load: (_) async {
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
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Anime 1'), findsOneWidget);
  });
}
