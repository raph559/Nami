import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
import 'motion.dart';
import '../widgets.dart';

/// A small flat label (genre, fact). With [onTap] it is a toggle; the
/// selected one is off-white with black text.
class FlatTag extends StatelessWidget {
  const FlatTag(this.label, {super.key, this.selected = false, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Nami.radiusButton);
    if (onTap != null) {
      return Semantics(
        button: true,
        selected: selected,
        child: FocusOutline(
          child: Material(
            type: MaterialType.transparency,
            child: QuietTap(onTap: onTap, builder: (context, hovered) => _target(_tag(context, radius, hovered))),
          ),
        ),
      );
    }
    return _tag(context, radius, false);
  }

  /// Touch screens get a finger-sized target around the small label.
  Widget _target(Widget tag) => isDesktop
      ? tag
      : ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Align(widthFactor: 1, heightFactor: 1, child: tag),
        );

  Widget _tag(BuildContext context, BorderRadius radius, bool hovered) {
    final motion = Motion.of(context);
    return AnimatedContainer(
      duration: motion.fast,
      curve: Motion.curve,
      decoration: BoxDecoration(
        color: selected ? Nami.text : Nami.text.withValues(alpha: hovered ? 0.14 : 0.07),
        borderRadius: radius,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: Nami.sans,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Nami.ground : Nami.textSecondary,
          ),
        ),
      ),
    );
  }
}
