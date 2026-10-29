import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
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
    final tag = DecoratedBox(
      decoration: BoxDecoration(color: selected ? Nami.text : Nami.text.withValues(alpha: 0.07), borderRadius: radius),
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
    if (onTap == null) return tag;
    // Touch screens get a finger-sized target around the small label.
    final target = isDesktop
        ? tag
        : ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Align(widthFactor: 1, heightFactor: 1, child: tag),
          );
    return Semantics(
      button: true,
      selected: selected,
      child: FocusOutline(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(onTap: onTap, borderRadius: radius, child: target),
        ),
      ),
    );
  }
}
