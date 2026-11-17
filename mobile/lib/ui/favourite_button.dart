import 'package:flutter/material.dart';

import '../anilist.dart';
import '../profile.dart';
import '../settings.dart';
import '../theme.dart';

/// The heart of a favourite on AniList. It changes at once; AniList is told after,
/// one request at a time, and the heart goes back if AniList refuses.
class FavouriteButton extends StatefulWidget {
  const FavouriteButton({
    super.key,
    required this.kind,
    required this.id,
    required this.initial,
    this.compact = false,
    this.tall = false,
    this.toggle,
    this.check,
  });

  final FavouriteKind kind;
  final int id;
  final bool initial;

  /// A plain icon (in a list), rather than a button the size of the ones beside it.
  final bool compact;

  /// As tall as the large phone buttons beside it; otherwise the theme's height,
  /// like the other buttons of its row.
  final bool tall;

  /// Flips the favourite on AniList; [AniList.toggleFavourite] unless a test gives another.
  final Future<void> Function(FavouriteKind, int)? toggle;

  /// Asks AniList whether it is a favourite now; [AniList.isFavourite] unless a test gives another.
  final Future<bool> Function(FavouriteKind, int)? check;

  static const red = Color(0xFFE85D75);

  /// What AniList confirmed during this session, by kind and id. Pages keep the
  /// details they loaded, so a heart built again (another tab, the same anime
  /// opened twice) starts from here; a toggle flips, so starting wrong would undo it.
  static final _confirmed = <String, bool>{};

  /// Favourites whose last change failed without AniList saying what it has: the
  /// change may have gone through with only the answer lost. They are checked
  /// before anything else is sent.
  static final _unsure = <String>{};

  @visibleForTesting
  static void forget() {
    _confirmed.clear();
    _unsure.clear();
  }

  @override
  State<FavouriteButton> createState() => _FavouriteButtonState();
}

class _FavouriteButtonState extends State<FavouriteButton> {
  String get _key => '${widget.kind.name}:${widget.id}';
  bool get _known => FavouriteButton._confirmed[_key] ?? widget.initial;

  /// What the heart shows: what the viewer asked for last.
  late bool _on = _known;

  /// What AniList has.
  late bool _sent = _known;
  bool _busy = false;

  @override
  void didUpdateWidget(FavouriteButton old) {
    super.didUpdateWidget(old);
    if ((old.initial != widget.initial || old.id != widget.id || old.kind != widget.kind) && !_busy) {
      _on = _sent = _known;
    }
  }

  /// Reads what AniList has and takes it as the truth.
  Future<void> _ask() async {
    final check = widget.check ?? AniList.instance.isFavourite;
    final now = await check(widget.kind, widget.id);
    _sent = now;
    FavouriteButton._confirmed[_key] = now;
    FavouriteButton._unsure.remove(_key);
  }

  Future<void> _tap() async {
    setState(() => _on = !_on);
    if (_busy) return;
    _busy = true;
    final toggle = widget.toggle ?? AniList.instance.toggleFavourite;
    try {
      if (FavouriteButton._unsure.contains(_key)) await _ask();
      // Taps during a request only change what is wanted; it is sent once that request ends.
      while (_on != _sent) {
        FavouriteButton._unsure.add(_key);
        await toggle(widget.kind, widget.id);
        _sent = !_sent;
        FavouriteButton._confirmed[_key] = _sent;
        FavouriteButton._unsure.remove(_key);
      }
    } catch (_) {
      // The change may have reached AniList with only its answer lost: ask before going back.
      try {
        await _ask();
      } catch (_) {}
      if (!mounted) return;
      final done = !FavouriteButton._unsure.contains(_key) && _sent == _on;
      setState(() => _on = _sent);
      if (!done) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(t("Les favoris n'ont pas pu être modifiés.", 'Favourites could not be changed.'))),
        );
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      _on ? Icons.favorite : Icons.favorite_border,
      color: _on ? FavouriteButton.red : Nami.text,
      size: widget.compact ? 22 : 20,
    );
    final label = _on
        ? t('Retirer des favoris', 'Remove from favourites')
        : t('Ajouter aux favoris', 'Add to favourites');
    if (widget.compact) {
      return IconButton(onPressed: _tap, icon: icon, tooltip: label);
    }
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: OutlinedButton(
          style: widget.tall
              ? OutlinedButton.styleFrom(minimumSize: const Size(50, 50), padding: EdgeInsets.zero)
              : OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
          onPressed: _tap,
          child: icon,
        ),
      ),
    );
  }
}
