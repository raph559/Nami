import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

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
    final style = TextStyle(
      fontFamily: Nami.sans,
      fontSize: 14,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      color: selected ? Nami.text : Nami.textSecondary,
    );
    return Semantics(
      selected: selected,
      button: true,
      child: FocusOutline(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Nami.radiusButton),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(label, style: style),
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
                selected
                    ? IntrinsicWidth(
                        child: Container(
                          key: UnderlineTabs.barKey,
                          height: 2,
                          decoration: BoxDecoration(color: Nami.text, borderRadius: BorderRadius.circular(1)),
                        ),
                      )
                    : const SizedBox(height: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
