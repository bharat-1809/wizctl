import 'dart:async';

import 'package:test/test.dart';
import 'package:wizctl/wizctl.dart';

import 'support/fake_bulb.dart';

void main() {
  group('WizDiscovery.probeAddressesStream', () {
    const bulbPort = 39421;
    const replyPort = 39422;

    test(
      'emits progress, found and done for a single reachable bulb',
      () async {
        var bulb = await FakeBulb.start(
          listenPort: bulbPort,
          replyMode: ReplyMode.sourcePort,
        );
        addTearDown(bulb.close);

        var events = await WizDiscovery.probeAddressesStream(
          addresses: const ['127.0.0.1'],
          port: bulbPort,
          localPort: replyPort,
          timeout: Duration(seconds: 2),
          rounds: 1,
        ).toList();

        expect(events.first, isA<ScanProgress>());
        var progress = events.whereType<ScanProgress>().toList();
        expect(progress.last.addressesProbed, 1);
        expect(progress.last.addressCount, 1);
        expect(progress.last.fraction, 1.0);
        expect(progress.last.subnet, isNull);
        expect(events.whereType<ScanFound>(), hasLength(1));
        expect(events.whereType<ScanFound>().single.light.mac, 'a8bb50aabbcc');
        expect(events.last, isA<ScanDone>());
        expect((events.last as ScanDone).lights, hasLength(1));
      },
    );

    test('progress never decreases across rounds', () async {
      var bulb = await FakeBulb.start(
        listenPort: bulbPort,
        replyMode: ReplyMode.sourcePort,
      );
      addTearDown(bulb.close);

      var progress = await WizDiscovery.probeAddressesStream(
        addresses: const ['127.0.0.1', '127.0.0.2', '127.0.0.3'],
        port: bulbPort,
        localPort: replyPort,
        timeout: Duration(seconds: 3),
        rounds: 2,
      ).where((e) => e is ScanProgress).cast<ScanProgress>().toList();

      for (var i = 1; i < progress.length; i++) {
        expect(
          progress[i].addressesProbed,
          greaterThanOrEqualTo(progress[i - 1].addressesProbed),
        );
        expect(
          progress[i].fraction,
          greaterThanOrEqualTo(progress[i - 1].fraction),
        );
      }
      expect(progress.last.addressesProbed, 3);
      expect(progress.last.fraction, 1.0);
      expect(progress.first.fraction, lessThan(1.0));
    });

    test(
      'reports an updated light when the richer reply lands later',
      () async {
        // getSystemConfig and getPilot are both sent; whichever answers second
        // that carries more detail must surface as ScanUpdated, and ScanDone
        // must hold the richer record.
        var bulb = await FakeBulb.start(
          listenPort: bulbPort,
          replyMode: ReplyMode.sourcePort,
        );
        addTearDown(bulb.close);

        var events = await WizDiscovery.probeAddressesStream(
          addresses: const ['127.0.0.1'],
          port: bulbPort,
          localPort: replyPort,
          timeout: Duration(seconds: 2),
          rounds: 1,
        ).toList();

        var done = events.last as ScanDone;
        expect(done.lights.single.moduleName, 'ESP01_SHRGB_03');
        var found = events.whereType<ScanFound>().single;
        if (found.light.moduleName == null) {
          expect(events.whereType<ScanUpdated>(), isNotEmpty);
        }
      },
    );

    test('cancelling stops probing', () async {
      var bulb = await FakeBulb.start(
        listenPort: bulbPort,
        replyMode: ReplyMode.sourcePort,
      );
      addTearDown(bulb.close);

      var firstProgress = Completer<void>();
      var subscription =
          WizDiscovery.probeAddressesStream(
            addresses: const ['127.0.0.1'],
            port: bulbPort,
            localPort: replyPort,
            timeout: Duration(seconds: 3),
            rounds: 2,
          ).listen((event) {
            if (event is ScanProgress && !firstProgress.isCompleted) {
              firstProgress.complete();
            }
          });
      await firstProgress.future;
      await subscription.cancel();

      // Round two would fire after subnetScanRoundInterval (800ms). Two
      // probes per address were sent in round one; no more may arrive.
      await Future.delayed(Duration(milliseconds: 1500));
      expect(bulb.requestCount, 2);
    });

    test('an empty address list completes with an empty ScanDone', () async {
      var events = await WizDiscovery.probeAddressesStream(
        addresses: const [],
        port: bulbPort,
        localPort: replyPort,
      ).toList();
      expect(events, hasLength(1));
      expect(events.single, isA<ScanDone>());
      expect((events.single as ScanDone).lights, isEmpty);
    });
  });
}
