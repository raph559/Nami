import 'package:flutter/material.dart';

/// Shared timings, so every hover and change moves at the same pace. With
/// reduced motion (system setting) every duration is zero: things change, nothing moves.
class Motion {
  const Motion._(this.fast, this.medium, this.slow);

  /// Hover and press feedback.
  final Duration fast;

  /// Something appearing or changing place (a card, a tab bar, a page).
  final Duration medium;

  /// Large surfaces (the home banner crossfade).
  final Duration slow;

  static const curve = Curves.easeOutCubic;

  static const _normal = Motion._(
    Duration(milliseconds: 140),
    Duration(milliseconds: 240),
    Duration(milliseconds: 600),
  );
  static const _still = Motion._(Duration.zero, Duration.zero, Duration.zero);

  static Motion of(BuildContext context) => MediaQuery.disableAnimationsOf(context) ? _still : _normal;
}

/// Rebuilds its child with whether the pointer is over it, and shows the hand
/// cursor when it can be clicked.
class Hoverable extends StatefulWidget {
  const Hoverable({super.key, required this.builder, this.clickable = true});
  final Widget Function(BuildContext context, bool hovered) builder;
  final bool clickable;

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.clickable ? SystemMouseCursors.click : MouseCursor.defer,
    onEnter: (_) => setState(() => hovered = true),
    onExit: (_) => setState(() => hovered = false),
    child: widget.builder(context, hovered),
  );
}

/// A tap target with no grey box and no ripple: [builder] draws its own hover
/// state. It stays focusable and answers Enter and Space, like any button.
class QuietTap extends StatefulWidget {
  const QuietTap({super.key, required this.onTap, required this.builder});
  final VoidCallback? onTap;
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<QuietTap> createState() => _QuietTapState();
}

class _QuietTapState extends State<QuietTap> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: widget.onTap,
    onHover: (h) => setState(() => hovered = h),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    splashFactory: NoSplash.splashFactory,
    child: widget.builder(context, hovered),
  );
}
