import 'package:flutter/material.dart';

import '../anilist.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';

/// One destination of the rail.
typedef RailItem = ({IconData icon, IconData selectedIcon, String label});

/// Desktop frame: a slim icon rail over the left edge of full-window pages,
/// so banners run behind it. Pages get the rail width as left padding.
class DesktopShell extends StatelessWidget {
  const DesktopShell({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
    required this.pages,
    required this.onAccount,
  });

  final List<RailItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final List<Widget> pages;

  /// The avatar at the bottom: the list when logged in, the login otherwise.
  final VoidCallback onAccount;

  static const width = 60.0;
  static const railKey = ValueKey('desktop-rail');

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: MediaQuery(
              data: media.copyWith(padding: media.padding.copyWith(left: width)),
              child: IndexedStack(index: index, children: pages),
            ),
          ),
          Positioned(
            key: railKey,
            left: 0,
            top: 0,
            bottom: 0,
            width: width,
            child: DecoratedBox(
              // Opaque at the edge, lighter toward the page: a banner shows faintly behind.
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Nami.ground.withValues(alpha: 0.94), Nami.ground.withValues(alpha: 0.6)],
                ),
              ),
              child: Padding(
                padding: EdgeInsets.only(top: media.padding.top + 10, bottom: 14),
                child: Column(
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        'n',
                        style: TextStyle(
                          fontFamily: Nami.sans,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Nami.text,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (var i = 0; i < items.length; i++) ...[
                      _RailButton(item: items[i], selected: i == index, onTap: () => onSelect(i)),
                      const SizedBox(height: 6),
                    ],
                    const Spacer(),
                    _Account(onTap: onAccount),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.item, required this.selected, required this.onTap});
  final RailItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        child: FocusOutline(
          child: IconButton(
            tooltip: item.label,
            onPressed: onTap,
            style: IconButton.styleFrom(
              fixedSize: const Size(40, 40),
              minimumSize: const Size(40, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              backgroundColor: selected ? Nami.text.withValues(alpha: 0.10) : Colors.transparent,
            ),
            icon: Icon(
              selected ? item.selectedIcon : item.icon,
              size: 20,
              color: selected ? Nami.text : Nami.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _Account extends StatelessWidget {
  const _Account({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AniList.instance,
      builder: (context, _) {
        final viewer = AniList.instance.viewer;
        return FocusOutline(
          child: IconButton(
            tooltip: viewer?.name ?? t('Se connecter à AniList', 'Log in to AniList'),
            onPressed: onTap,
            style: IconButton.styleFrom(fixedSize: const Size(40, 40), minimumSize: const Size(40, 40)),
            icon: viewer?.avatar != null
                ? SizedBox(width: 30, height: 30, child: CoverImage(viewer!.avatar, radius: 15))
                : Icon(Icons.account_circle_outlined, size: 24, color: Nami.textMuted),
          ),
        );
      },
    );
  }
}
