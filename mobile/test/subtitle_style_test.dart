import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/settings.dart';
import 'package:nami/subtitle_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_screen_test.dart' show pumpSettings;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'appLanguage': 'fr'});
    await AppSettings.load();
  });

  test('the defaults give mpv what it used before', () {
    final mpv = const SubtitleStyle().mpv(styled: false);
    expect(mpv['sub-scale'], '1.0');
    expect(mpv['sub-border-size'], '3.0');
    expect(mpv['sub-margin-y'], '22');
    expect(mpv['sub-ass-override'], 'scale');
    expect(mpv['sub-ass-style-overrides'], '');
  });

  test('plain subtitles get the background, designed ones keep their own', () {
    const style = SubtitleStyle(box: true, font: SubtitleFont.legible, color: SubtitleColor.yellow, lift: 50);
    final plain = style.mpv(styled: false);
    expect(plain['sub-ass-style-overrides'], contains('BorderStyle=3'));
    expect(plain['sub-font'], 'Atkinson Hyperlegible');
    expect(plain['sub-color'], '#FFE14D');
    expect(plain['sub-margin-y'], '122');
    final designed = style.mpv(styled: true);
    expect(designed['sub-ass-style-overrides'], '');
    expect(designed['sub-ass-override'], 'scale');
  });

  test('always my style forces it on designed subtitles too', () {
    final mpv = const SubtitleStyle(box: true, force: true).mpv(styled: true);
    expect(mpv['sub-ass-override'], 'force');
    expect(mpv['sub-ass-style-overrides'], contains('BorderStyle=3'));
  });

  test('the style is saved', () {
    final s = AppSettings.instance
      ..subtitleFont = SubtitleFont.serif
      ..subtitleOutline = SubtitleOutline.none
      ..subtitleBox = true
      ..subtitleLift = 30
      ..subtitleForce = true;
    final style = s.subtitleStyle;
    expect(style.font, SubtitleFont.serif);
    expect(style.outline, SubtitleOutline.none);
    expect(style.box, isTrue);
    expect(style.lift, 30);
    expect(style.force, isTrue);
  });

  testWidgets('the preview follows the choices', (tester) async {
    await pumpSettings(tester, desktop: false);
    final preview = find.byType(SubtitlePreview);
    await tester.ensureVisible(preview);
    expect(find.descendant(of: preview, matching: find.byType(DecoratedBox)), findsOneWidget);
    await tester.ensureVisible(find.text('Fond sombre'));
    await tester.pumpAndSettle();
    final row = find.ancestor(of: find.text('Fond sombre'), matching: find.byType(Row)).first;
    await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
    await tester.pump();
    expect(AppSettings.instance.subtitleStyle.box, isTrue);
    // The scene and now the box behind the text.
    expect(find.descendant(of: preview, matching: find.byType(DecoratedBox)), findsNWidgets(2));
  });
}
