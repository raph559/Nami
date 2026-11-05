import 'package:flutter_test/flutter_test.dart';
import 'package:nami/profile.dart';
import 'package:nami/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'appLanguage': 'fr'});
    await AppSettings.load();
  });

  test('score formats show like AniList', () {
    expect(ScoreFormat.point100.show(78), '78');
    expect(ScoreFormat.point10Decimal.show(78), '7,8');
    expect(ScoreFormat.point10.show(78), '8');
    expect(ScoreFormat.point5.show(78), '★★★★');
    expect(ScoreFormat.point3.show(78), '🙂');
    expect(ScoreFormat.point3.show(40), '😐');
    expect(ScoreFormat.parse('POINT_5'), ScoreFormat.point5);
    expect(ScoreFormat.parse(null), ScoreFormat.point100);
  });

  test('distribution keys become out of 100', () {
    expect(ScoreFormat.point10.distributionToOutOf100(8), 80);
    expect(ScoreFormat.point5.distributionToOutOf100(4), 80);
    expect(ScoreFormat.point3.distributionToOutOf100(3), 85);
    expect(ScoreFormat.point10Decimal.distributionToOutOf100(90), 90);
  });

  test('stats parse with empty lists', () {
    final empty = ProfileStats.fromJson({'count': 0}, ScoreFormat.point10);
    expect(empty.isEmpty, isTrue);
    expect(empty.genres, isEmpty);
    expect(empty.scores, isEmpty);
    final full = ProfileStats.fromJson({
      'count': 120,
      'meanScore': 78.5,
      'genres': [
        {'genre': 'Action', 'count': 40},
      ],
      'studios': [
        {
          'studio': {'name': 'MAPPA'},
          'count': 7,
        },
      ],
      'scores': [
        {'score': 8, 'count': 55},
      ],
      'releaseYears': [
        {'releaseYear': 2020, 'count': 12},
      ],
    }, ScoreFormat.point10);
    expect(full.isEmpty, isFalse);
    expect(full.genres.first.name, 'Action');
    expect(full.studios.first.name, 'MAPPA');
    expect(full.scores[80], 55);
    expect(full.releaseYears[2020], 12);
  });

  test('bio keeps text and links, drops media', () {
    expect(parseBio('Hi __there__ img220(https://x/a.png) [site](https://a.co) youtube(abc)'), [
      const BioText('Hi there '),
      const BioLink('site', 'https://a.co'),
    ]);
  });

  test('bio spoilers', () {
    expect(parseBio('a ~!secret!~ b'), contains(const BioSpoiler('secret')));
    expect(parseBio('a ~!open'), [const BioText('a ~!open')]);
  });

  test('bio html', () {
    expect(parseBio('<p>Hello <a href="https://b.co">B</a></p><br>x'), [
      const BioText('Hello '),
      const BioLink('B', 'https://b.co'),
      const BioText('\nx'),
    ]);
  });

  test('empty bios', () {
    expect(parseBio(null), isEmpty);
    expect(parseBio(''), isEmpty);
    expect(parseBio('img(https://x/a.png)'), isEmpty);
  });

  test('linked images and html images leave nothing behind', () {
    expect(parseBio('[img220(https://i.imgur.com/a.png)](https://anilist.co/user/x)'), isEmpty);
    expect(parseBio('~~~[ img(https://i.imgur.com/a.png) ](https://anilist.co/user/x)~~~'), isEmpty);
    expect(parseBio('<center><img src="https://i.imgur.com/a.png" width="200"></center>'), isEmpty);
    expect(parseBio('<a href="https://x.co"><img src="https://i.imgur.com/a.png"></a>'), isEmpty);
  });

  test('links with other attributes', () {
    expect(parseBio('<a target="_blank" href="https://x.co">X</a>'), [const BioLink('X', 'https://x.co')]);
  });
}
