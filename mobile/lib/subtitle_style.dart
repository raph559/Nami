import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'settings.dart';

enum SubtitleFont { standard, nami, legible, serif }

extension SubtitleFontInfo on SubtitleFont {
  String get label => switch (this) {
    SubtitleFont.standard => 'Standard',
    SubtitleFont.nami => 'Nami',
    SubtitleFont.legible => t('Lisible', 'Legible'),
    SubtitleFont.serif => t('Classique', 'Classic'),
  };

  /// The family mpv asks libass for. The three named ones ship with Nami.
  String get mpvName => switch (this) {
    SubtitleFont.standard => 'sans-serif',
    SubtitleFont.nami => 'Hanken Grotesk',
    SubtitleFont.legible => 'Atkinson Hyperlegible',
    SubtitleFont.serif => 'PT Serif',
  };

  /// The family Settings draws the preview with.
  String get flutterFamily => switch (this) {
    SubtitleFont.standard => 'sans-serif',
    SubtitleFont.nami => 'HankenGrotesk',
    SubtitleFont.legible => 'AtkinsonHyperlegible',
    SubtitleFont.serif => 'PTSerif',
  };
}

enum SubtitleColor { white, yellow }

extension SubtitleColorInfo on SubtitleColor {
  String get label => switch (this) {
    SubtitleColor.white => t('Blanc', 'White'),
    SubtitleColor.yellow => t('Jaune', 'Yellow'),
  };

  String get hex => switch (this) {
    SubtitleColor.white => '#FFFFFF',
    SubtitleColor.yellow => '#FFE14D',
  };

  Color get color => switch (this) {
    SubtitleColor.white => const Color(0xFFFFFFFF),
    SubtitleColor.yellow => const Color(0xFFFFE14D),
  };
}

enum SubtitleOutline { none, thin, thick }

extension SubtitleOutlineInfo on SubtitleOutline {
  String get label => switch (this) {
    SubtitleOutline.none => t('Aucun', 'None'),
    SubtitleOutline.thin => t('Fin', 'Thin'),
    SubtitleOutline.thick => t('Épais', 'Thick'),
  };

  /// mpv's sub-border-size, in pixels of a 720-line screen. Thick is mpv's own default.
  double get size => switch (this) {
    SubtitleOutline.none => 0,
    SubtitleOutline.thin => 1.5,
    SubtitleOutline.thick => 3,
  };
}

/// How subtitles look. Subtitles that bring their own design (ASS) keep it, apart
/// from the size, unless [force] is on.
class SubtitleStyle {
  const SubtitleStyle({
    this.size = 100,
    this.font = SubtitleFont.standard,
    this.color = SubtitleColor.white,
    this.outline = SubtitleOutline.thick,
    this.box = false,
    this.lift = 0,
    this.force = false,
  });

  /// Percent.
  final int size;
  final SubtitleFont font;
  final SubtitleColor color;
  final SubtitleOutline outline;

  /// A dark box behind the text.
  final bool box;

  /// How far above the bottom, from 0 (mpv's usual place) to 100.
  final int lift;
  final bool force;

  static const maxLift = 100;

  /// mpv's bottom margin, in pixels of a 720-line screen; 22 is mpv's default.
  int get marginY => 22 + lift * 2;

  /// The mpv settings for the subtitle being shown. [styled] says it is an ASS
  /// subtitle with its own design.
  Map<String, String> mpv({required bool styled}) {
    final mine = force || !styled;
    return {
      'sub-scale': (size / 100).toString(),
      'sub-font': font.mpvName,
      'sub-color': color.hex,
      'sub-border-size': outline.size.toString(),
      'sub-margin-y': '$marginY',
      'sub-ass-override': force ? 'force' : 'scale',
      // mpv 0.36 (Android and Windows) has no background option: libass's opaque
      // box, coloured with the outline colour, does it. Never on a design kept as is.
      'sub-ass-style-overrides': box && mine ? 'BorderStyle=3,Outline=3,Shadow=0,OutlineColour=&H60000000' : '',
    };
  }
}

/// The subtitle fonts in a folder mpv can read: assets are inside the app package.
class SubtitleFonts {
  static const files = ['HankenGrotesk-Bold.ttf', 'AtkinsonHyperlegible-Bold.ttf', 'PTSerif-Bold.ttf'];
  static Future<String?>? _dir;

  /// Null when the folder cannot be made (tests, a full disk): mpv then uses its own font.
  static Future<String?> dir() => _dir ??= _copy();

  static Future<String?> _copy() async {
    try {
      final sep = Platform.pathSeparator;
      final dir = Directory('${(await getApplicationSupportDirectory()).path}${sep}subtitle-fonts');
      await dir.create(recursive: true);
      for (final name in files) {
        final data = await rootBundle.load('assets/subtitle-fonts/$name');
        final file = File('${dir.path}$sep$name');
        if (await file.exists() && await file.length() == data.lengthInBytes) continue;
        await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      }
      return dir.path;
    } catch (_) {
      return null;
    }
  }
}

/// A line of subtitle over a dark scene, drawn the way [style] says, for Settings.
class SubtitlePreview extends StatelessWidget {
  const SubtitlePreview({super.key, required this.style});
  final SubtitleStyle style;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: LayoutBuilder(
          builder: (context, box) {
            // Sizes follow mpv's: 55 px text and the margin on a 720-line screen.
            final unit = box.maxHeight / 720;
            final fontSize = 55 * unit * style.size / 100;
            final text = t('On se retrouve demain, au même endroit.', 'See you tomorrow, same place.');
            final family = style.font.flutterFamily;
            final weight = style.font == SubtitleFont.standard ? FontWeight.w600 : FontWeight.w700;
            final stroke = style.outline.size * unit * 2;
            Widget line = Stack(
              children: [
                if (!style.box && stroke > 0)
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: family,
                      fontSize: fontSize,
                      fontWeight: weight,
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = stroke
                        ..strokeJoin = StrokeJoin.round
                        ..color = Colors.black,
                    ),
                  ),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: family,
                    fontSize: fontSize,
                    fontWeight: weight,
                    color: style.color.color,
                  ),
                ),
              ],
            );
            if (style.box) {
              line = DecoratedBox(
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.62)),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6 * unit, vertical: 3 * unit),
                  child: line,
                ),
              );
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF3A4A5C), Color(0xFF7A5A48), Color(0xFF1C1F26)],
                    ),
                  ),
                ),
                Positioned(
                  left: 24 * unit,
                  right: 24 * unit,
                  bottom: style.marginY * unit,
                  child: Center(child: line),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
