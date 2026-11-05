import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nami/pip.dart';

class FakeWindow implements PipWindow {
  final calls = <String>[];

  @override
  Future<void> enter() async => calls.add('enter');

  @override
  Future<void> exit() async => calls.add('exit');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('with no platform support nothing happens', () async {
    final pip = Pip(null);
    expect(pip.supported, isFalse);
    await pip.enter();
    expect(pip.supported, isFalse);
  });

  test('a window Nami manages itself opens and closes at once', () async {
    final window = FakeWindow();
    final pip = Pip(window);
    await pip.enter();
    await pip.enter();
    expect(pip.active, isTrue);
    await pip.exit();
    await pip.exit();
    expect(pip.active, isFalse);
    expect(window.calls, ['enter', 'exit']);
  });

  group('the system window', () {
    const channel = MethodChannel('nami/pip-test');
    late List<MethodCall> sent;

    Future<void> event(String method, [Object? args]) async {
      final data = const StandardMethodCodec().encodeMethodCall(MethodCall(method, args));
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        data,
        (_) {},
      );
    }

    setUp(() {
      sent = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        sent.add(call);
        return null;
      });
    });

    test('waits for Android to say the window is up', () async {
      final pip = Pip(const AndroidPip(channel), channel: channel);
      await pip.enter();
      expect(sent.single.method, 'enter');
      expect(pip.active, isFalse);
      await event('changed', {'active': true, 'closed': false});
      expect(pip.active, isTrue);
    });

    test('closing the window stops the video, expanding it does not', () async {
      var closed = 0;
      final pip = Pip(const AndroidPip(channel), channel: channel)..onClosed = () => closed++;
      await event('changed', {'active': true, 'closed': false});
      await event('changed', {'active': false, 'closed': false});
      expect(closed, 0);
      await event('changed', {'active': true, 'closed': false});
      await event('changed', {'active': false, 'closed': true});
      expect(closed, 1);
      expect(pip.active, isFalse);
    });

    test('the pause button in the window reaches the player', () async {
      var toggled = 0;
      Pip(const AndroidPip(channel), channel: channel).onTogglePause = () => toggled++;
      await event('togglePause');
      expect(toggled, 1);
    });

    test('tells Android whether it is playing and may shrink by itself', () async {
      final pip = Pip(const AndroidPip(channel), channel: channel);
      pip.setPlaying(true);
      pip.setAuto(false);
      await pumpEventQueue();
      expect(sent.map((c) => (c.method, c.arguments)), [('playing', true), ('auto', false)]);
    });
  });
}
