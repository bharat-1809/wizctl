import 'package:test/test.dart';
import 'package:wizctl/wizctl.dart';

import 'support/fake_bulb.dart';

void main() {
  group('WizLight retry', () {
    const bulbPort = 39431;

    test('a light exposes its retry config', () {
      var light = WizLight(
        '192.168.1.100',
        retry: const RetryConfig.fixed(
          count: 2,
          interval: Duration(milliseconds: 100),
        ),
      );
      expect(light.retry?.count, 2);
      expect(WizLight('192.168.1.100').retry, isNull);
    });

    test('three attempts reach a bulb that drops the first two', () async {
      var bulb = await FakeBulb.start(
        listenPort: bulbPort,
        replyMode: ReplyMode.sourcePort,
        ignoreFirst: 2,
      );
      addTearDown(bulb.close);

      var light = WizLight(
        '127.0.0.1',
        port: bulbPort,
        timeout: Duration(milliseconds: 600),
        retry: const RetryConfig.fixed(
          count: 2,
          interval: Duration(milliseconds: 50),
        ),
      );
      var state = await light.getState();
      expect(state.isOn, isTrue);
      expect(bulb.requestCount, 3);
    });

    test('a single attempt times out against the same bulb', () async {
      var bulb = await FakeBulb.start(
        listenPort: bulbPort,
        replyMode: ReplyMode.sourcePort,
        ignoreFirst: 1,
      );
      addTearDown(bulb.close);

      var light = WizLight(
        '127.0.0.1',
        port: bulbPort,
        timeout: Duration(milliseconds: 600),
        retry: const RetryConfig.none(),
      );
      await expectLater(light.getState(), throwsA(isA<WizTimeoutError>()));
      expect(bulb.requestCount, 1);
    });

    test('send honours the retry config too', () async {
      var bulb = await FakeBulb.start(
        listenPort: bulbPort,
        replyMode: ReplyMode.sourcePort,
        ignoreFirst: 1,
      );
      addTearDown(bulb.close);

      var light = WizLight(
        '127.0.0.1',
        port: bulbPort,
        timeout: Duration(milliseconds: 600),
        retry: const RetryConfig.fixed(
          count: 1,
          interval: Duration(milliseconds: 50),
        ),
      );
      await light.send(ControlSignal.on());
      expect(bulb.requestCount, 2);
    });
  });
}
