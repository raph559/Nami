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

  testWidgets('the flash says which way and how far', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Row(children: [SeekFlash(seconds: -30), SeekFlash(seconds: 10)])),
      ),
    );
    expect(find.text('-30 s'), findsOneWidget);
    expect(find.text('+10 s'), findsOneWidget);
  });
}
