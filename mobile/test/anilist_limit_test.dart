import 'dart:convert';

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
}
