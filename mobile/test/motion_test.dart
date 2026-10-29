import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/settings.dart';
import 'package:nami/theme.dart';
import 'package:nami/ui/motion.dart';
import 'package:nami/ui/tabs.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget host(Widget child, {bool reduce = false}) => MaterialApp(
  theme: Nami.desktopTheme(),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'appLanguage': 'fr'});
    await AppSettings.load();
  });

  testWidgets('motion durations drop to zero with reduced motion', (tester) async {
    late Duration normal, reduced;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (c) {
            normal = Motion.of(c).medium;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpWidget(
      host(
        Builder(
          builder: (c) {
            reduced = Motion.of(c).medium;
            return const SizedBox();
          },
        ),
        reduce: true,
      ),
    );
    expect(normal, greaterThan(Duration.zero));
    expect(reduced, Duration.zero);
  });

  testWidgets('hovering a tab brightens its text without a box', (tester) async {
    await tester.pumpWidget(host(UnderlineTabs(labels: const ['En cours', 'En pause'], selected: 0, onSelect: (_) {})));
    // Still a focusable button, but its hover overlay is see-through.
    final ink = tester.widget<InkWell>(
      find.descendant(of: find.byType(UnderlineTabs), matching: find.byType(InkWell)).first,
    );
    expect(ink.overlayColor!.resolve({WidgetState.hovered}), Colors.transparent);
    Color color() => DefaultTextStyle.of(tester.element(find.text('En pause'))).style.color!;
    final before = color();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('En pause')));
    await tester.pumpAndSettle();
    expect(color(), isNot(before));
    expect(color(), Nami.text);
  });

  testWidgets('the tab bar grows in when a tab is chosen', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => UnderlineTabs(
            labels: const ['En cours', 'En pause'],
            selected: selected,
            onSelect: (i) => setState(() => selected = i),
          ),
        ),
      ),
    );
    await tester.tap(find.text('En pause'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    double share() => (tester.widget<CustomPaint>(find.byKey(UnderlineTabs.barKey)).painter! as TabBarPainter).share;
    final mid = share();
    await tester.pumpAndSettle();
    expect(mid, lessThan(1));
    expect(share(), 1);
  });
}
