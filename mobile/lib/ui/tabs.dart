import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'motion.dart';

/// Text tabs over a thin line; the selected one is bold with a short bar
/// under it. Scrolls sideways when the labels do not fit.
class UnderlineTabs extends StatelessWidget {
  const UnderlineTabs({
    super.key,
    required this.labels,
    this.counts = const [],
    required this.selected,
    required this.onSelect,
    this.trailing,
  });

  final List<String> labels;

  /// Shown after each label when not null.
  final List<int?> counts;
  final int selected;
  final ValueChanged<int> onSelect;

  /// Placed at the right end, on the same line (a sort menu for example).
  final Widget? trailing;

  static const barKey = ValueKey('underline-tabs-bar');

  @override
  Widget build(BuildContext context) {
    final tabs = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 24),
              child: _Tab(
                label: labels[i],
                count: i < counts.length ? counts[i] : null,
                selected: i == selected,
                onTap: () => onSelect(i),
              ),
            ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Nami.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: tabs),
          if (trailing != null) ...[
            const SizedBox(width: 16),
            Padding(padding: const EdgeInsets.only(bottom: 4), child: trailing),
          ],
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.count, required this.selected, required this.onTap});
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final motion = Motion.of(context);
    // No box on hover: the text brightens, and the chosen tab's bar grows out from its start.
    return Semantics(
      selected: selected,
      button: true,
      child: FocusOutline(
        child: QuietTap(
          onTap: onTap,
          builder: (context, hovered) => ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            // As wide as the label, so the bar can be a share of it.
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: motion.fast,
                        curve: Motion.curve,
                        style: TextStyle(
                          fontFamily: Nami.sans,
                          fontSize: 14,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected || hovered ? Nami.text : Nami.textSecondary,
                        ),
                        child: Text(label),
                      ),
                      if (count != null) ...[
                        const SizedBox(width: 5),
                        Text(
                          '$count',
                          style: TextStyle(fontFamily: Nami.sans, fontSize: 12, color: Nami.textMuted),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  // The bar sits on the row's line, 10 px under the text.
                  // Painted, not sized: the bar takes no width of its own, the column gives it the label's.
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: selected ? 1 : (hovered ? 0.25 : 0)),
                    duration: motion.medium,
                    curve: Motion.curve,
                    builder: (context, share, _) => CustomPaint(
                      key: selected ? UnderlineTabs.barKey : null,
                      painter: TabBarPainter(share: share, color: selected ? Nami.text : Nami.textMuted),
                      child: const SizedBox(height: 2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The chosen tab's bar, drawn over [share] of the label's width from its start.
class TabBarPainter extends CustomPainter {
  TabBarPainter({required this.share, required this.color});
  final double share;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (share <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & Size(size.width * share.clamp(0.0, 1.0), size.height),
        const Radius.circular(1),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(TabBarPainter old) => old.share != share || old.color != color;
}
