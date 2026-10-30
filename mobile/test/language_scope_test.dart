import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/main.dart';
import 'package:nami/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A const page, so only a rebuild forced from above can update its text.
class Page extends StatefulWidget {
  const Page({super.key});
  @override
  State<Page> createState() => _PageState();
}

class _PageState extends State<Page> {
  int taps = 0;

  @override
  Widget build(BuildContext context) =>
      TextButton(onPressed: () => setState(() => taps++), child: Text('${t('Accueil', 'Home')} $taps'));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'appLanguage': 'fr'});
    await AppSettings.load();
  });

  testWidgets('changing the language updates text and keeps the page state', (tester) async {
    await tester.pumpWidget(
      const LanguageScope(
        child: MaterialApp(home: Scaffold(body: Page())),
      ),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(find.text('Accueil 1'), findsOneWidget);
    AppSettings.instance.language = AppLanguage.en;
    await tester.pump();
    // Same text widget, same state: still 1 tap, now in English.
    expect(find.text('Home 1'), findsOneWidget);
  });

  testWidgets('changing the title language rebuilds too', (tester) async {
    var builds = 0;
    await tester.pumpWidget(
      LanguageScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              builds++;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final before = builds;
    AppSettings.instance.titleLanguage = TitleLanguage.english;
    await tester.pump();
    expect(builds, greaterThan(before));
  });

  testWidgets('other settings do not rebuild the whole app', (tester) async {
    var builds = 0;
    await tester.pumpWidget(
      LanguageScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              builds++;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final before = builds;
    AppSettings.instance.resolution = '720';
    await tester.pump();
    expect(builds, before);
  });
}
