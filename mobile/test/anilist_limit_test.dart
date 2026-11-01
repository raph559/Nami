import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nami/anilist.dart';
import 'package:nami/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response ok(Map<String, dynamic> data) => http.Response(jsonEncode({'data': data}), 200);
final limited = http.Response(
  jsonEncode({
    'errors': [
      {'message': 'Too Many Requests.', 'status': 429},
    ],
    'data': null,
  }),
  429,
  headers: {'retry-after': '0'},
);

final profile = {
  'Viewer': {'id': 7, 'name': 'raph559'},
};

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'appLanguage': 'fr', 'anilistToken': 'token'});
    await AppSettings.load();
    AniList.instance.viewer = null;
  });

  tearDown(() => AniList.instance.post = null);

  void answers(List<http.Response> list) {
    final queue = [...list];
    AniList.instance.post = (uri, headers, body) async => queue.length > 1 ? queue.removeAt(0) : queue.first;
  }

  test('a rate-limited request waits and tries again', () async {
    answers([
      limited,
      ok({'x': 1}),
    ]);
    expect(await AniList.instance.query('query'), {'x': 1});
  });

  test('a rate limit that lasts ends in an error', () async {
    answers([limited]);
    await expectLater(AniList.instance.query('query'), throwsA(isA<AniListException>()));
  });

  test('the profile loads through a rate limit', () async {
    answers([limited, ok(profile)]);
    await AniList.instance.loadViewer();
    expect(AniList.instance.viewer?.name, 'raph559');
  });

  test('a failed refresh keeps the profile on screen', () async {
    answers([ok(profile)]);
    await AniList.instance.loadViewer();
    answers([http.Response('down', 500)]);
    await AniList.instance.loadViewer();
    expect(AniList.instance.viewer?.name, 'raph559');
    expect(AniList.instance.isLoggedIn, isTrue);
  });

  test('a 401 for an old token does not log out the new one', () async {
    AniList.instance.post = (uri, headers, body) async {
      // The token changes while the request is on its way (a new login).
      await AppSettings.instance.prefs.setString('anilistToken', 'new');
      return http.Response('{"errors":[{"message":"Invalid token"}]}', 401);
    };
    await expectLater(AniList.instance.query('query'), throwsA(isA<AniListException>()));
    expect(AniList.instance.isLoggedIn, isTrue);
  });

  test('a 401 for the current token logs out', () async {
    answers([http.Response('{"errors":[{"message":"Invalid token"}]}', 401)]);
    await expectLater(AniList.instance.query('query'), throwsA(isA<AniListException>()));
    expect(AniList.instance.isLoggedIn, isFalse);
  });

  group('watching with no network', () {
    Media anime(int id, {int progress = 0, int episodes = 12}) => Media({
      'id': id,
      'title': <String, dynamic>{'romaji': 'Test'},
      'episodes': episodes,
      'mediaListEntry': {'id': 1, 'progress': progress, 'status': 'CURRENT', 'score': 0},
    });

    late List<Map<String, dynamic>> saved;
    late Map<int, Media> remote;
    var online = false;

    setUp(() {
      saved = [];
      remote = {};
      online = false;
      AniList.instance.post = (uri, headers, body) async {
        if (!online) throw const SocketException('offline');
        final request = jsonDecode(body) as Map<String, dynamic>;
        final variables = request['variables'] as Map<String, dynamic>;
        if ((request['query'] as String).contains('SaveMediaListEntry')) {
          saved.add(variables);
          return ok({
            'SaveMediaListEntry': {'progress': variables['p']},
          });
        }
        if ((request['query'] as String).contains('Media(id')) return ok({'Media': remote[variables['id']]!.json});
        return ok(profile);
      };
    });

    test('a failed save is held and sent later', () async {
      await expectLater(AniList.instance.setProgress(anime(1), 3), throwsA(anything));
      remote[1] = anime(1, progress: 1);
      await AniList.instance.sendHeldProgress();
      expect(saved, isEmpty);
      online = true;
      await AniList.instance.sendHeldProgress();
      expect(saved.single, containsPair('p', 3));
      saved.clear();
      await AniList.instance.sendHeldProgress();
      expect(saved, isEmpty);
    });

    test('the highest episode wins', () async {
      await expectLater(AniList.instance.setProgress(anime(1), 5), throwsA(anything));
      await expectLater(AniList.instance.setProgress(anime(1), 3), throwsA(anything));
      online = true;
      remote[1] = anime(1);
      await AniList.instance.sendHeldProgress();
      expect(saved.single, containsPair('p', 5));
    });

    test('progress made elsewhere meanwhile is not moved back', () async {
      await expectLater(AniList.instance.setProgress(anime(1), 3), throwsA(anything));
      online = true;
      remote[1] = anime(1, progress: 8);
      await AniList.instance.sendHeldProgress();
      expect(saved, isEmpty);
    });

    test('the last episode completes the anime', () async {
      await expectLater(AniList.instance.setProgress(anime(1), 12), throwsA(anything));
      online = true;
      remote[1] = anime(1);
      await AniList.instance.sendHeldProgress();
      expect(saved.single, containsPair('s', 'COMPLETED'));
    });

    test('the viewer loading sends what was held', () async {
      await expectLater(AniList.instance.setProgress(anime(1), 3), throwsA(anything));
      online = true;
      remote[1] = anime(1);
      await AniList.instance.loadViewer();
      await pumpEventQueue();
      expect(saved.single, containsPair('p', 3));
    });
  });
}
