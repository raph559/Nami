import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/screens/player.dart';
import 'package:nami/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.load();
  });

  test('the seek length defaults to 10 seconds and is remembered', () async {
    expect(AppSettings.instance.seekStep, 10);
    AppSettings.instance.seekStep = 15;
    expect(AppSettings.instance.seekStep, 15);
    await AppSettings.load();
    expect(AppSettings.instance.seekStep, 15);
  });

  test('a saved length that is no longer offered falls back to 10', () async {
    SharedPreferences.setMockInitialValues({'seekStep': 7});
    await AppSettings.load();
    expect(AppSettings.instance.seekStep, 10);
  });

  test('double taps seek on the sides, not in the middle', () {
    expect(seekSide(100, 1000), -1);
    expect(seekSide(399, 1000), -1);
    expect(seekSide(500, 1000), 0);
    expect(seekSide(601, 1000), 1);
    expect(seekSide(950, 1000), 1);
  });

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(width: 800, height: 400, child: child)),
  );

  testWidgets('the feedback says how far, on the side of the jump', (tester) async {
    await tester.pumpWidget(host(const SeekFeedback(seconds: 10, pulse: 1)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('+10 s'), findsOneWidget);
    expect(tester.getCenter(find.text('+10 s')).dx, greaterThan(400));

    await tester.pumpWidget(host(const SeekFeedback(seconds: -30, tap: Offset(100, 100), pulse: 2)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('-30 s'), findsOneWidget);
    expect(tester.getCenter(find.text('-30 s')).dx, lessThan(400));
  });

  testWidgets('the arrows run in turn', (tester) async {
    await tester.pumpWidget(host(const SeekFeedback(seconds: 10)));
    double first() => tester.widgetList<Icon>(find.byType(Icon)).first.color!.a;
    await tester.pump(const Duration(milliseconds: 10));
    final start = first();
    await tester.pump(const Duration(milliseconds: 250));
    expect(first(), isNot(start));
  });

  testWidgets('the arrows stay still with reduced motion', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(body: SizedBox(width: 800, height: 400, child: const SeekFeedback(seconds: 10))),
        ),
      ),
    );
    expect(tester.hasRunningAnimations, isFalse);
  });
}
