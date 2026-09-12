import 'dart:async';

import 'package:test/test.dart';
import 'package:wizctl/wizctl.dart';

import 'support/fake_bulb.dart';

void main() {
  group('ScanFailed', () {
    test('carries the address range and error, and formats both', () {
      var event = ScanFailed(
        addressRange: '192.168.1.65-192.168.1.128',
        error: 'socket failed to bind',
      );

      expect(event.addressRange, '192.168.1.65-192.168.1.128');
      expect(event.error, 'socket failed to bind');
      expect(
        event.toString(),
        'ScanFailed(192.168.1.65-192.168.1.128: socket failed to bind)',
      );
    });
  });

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
        // Delay the getSystemConfig reply so getPilot answers first: the
        // ScanFound must carry no moduleName, and the later, richer reply
        // must surface as ScanUpdated.
        var bulb = await FakeBulb.start(
          listenPort: bulbPort,
          replyMode: ReplyMode.sourcePort,
          replyDelays: {methodGetSystemConfig: Duration(milliseconds: 150)},
        );
        addTearDown(bulb.close);

        var events = await WizDiscovery.probeAddressesStream(
          addresses: const ['127.0.0.1'],
          port: bulbPort,
          localPort: replyPort,
          timeout: Duration(seconds: 2),
          rounds: 1,
        ).toList();

        var found = events.whereType<ScanFound>().single;
        expect(found.light.moduleName, isNull);

        var updated = events.whereType<ScanUpdated>().single;
        expect(updated.light.moduleName, 'ESP01_SHRGB_03');
        expect(updated.light.mac, 'a8bb50aabbcc');

        var done = events.last as ScanDone;
        expect(done.lights.single.moduleName, 'ESP01_SHRGB_03');
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

  group('WizDiscovery.scanSubnetStream', () {
    const unusedPort = 39423;

    test(
      'sweeps a whole /24 with cumulative progress and finishes empty',
      () async {
        // TEST-NET-1 is reserved and unroutable, so nothing answers and every
        // send fails asynchronously; the stream must still progress to the
        // end and finish with an empty ScanDone.
        var events = await WizDiscovery.scanSubnetStream(
          subnet: '192.0.2',
          port: unusedPort,
          localPort: 0,
          timeout: Duration(seconds: 1),
          rounds: 1,
        ).toList();

        var progress = events.whereType<ScanProgress>().toList();
        expect(progress, isNotEmpty);
        expect(progress.every((p) => p.subnet == '192.0.2'), isTrue);
        expect(progress.every((p) => p.addressCount == 254), isTrue);
        for (var i = 1; i < progress.length; i++) {
          expect(
            progress[i].addressesProbed,
            greaterThanOrEqualTo(progress[i - 1].addressesProbed),
          );
        }
        expect(progress.last.addressesProbed, 254);
        expect(progress.last.fraction, closeTo(1.0, 0.001));
        expect(events.last, isA<ScanDone>());
        expect((events.last as ScanDone).lights, isEmpty);
      },
    );

    test('scanSubnet still returns the collected list', () async {
      var lights = await WizDiscovery.scanSubnet(
        subnet: '192.0.2',
        port: unusedPort,
        localPort: 0,
        timeout: Duration(seconds: 1),
        rounds: 1,
      );
      expect(lights, isEmpty);
    });

    test('cancelling a sweep completes without a ScanDone', () async {
      var received = <ScanEvent>[];
      var subscription = WizDiscovery.scanSubnetStream(
        subnet: '192.0.2',
        port: unusedPort,
        localPort: 0,
        timeout: Duration(seconds: 1),
        rounds: 1,
      ).listen(received.add);
      await Future.delayed(Duration(milliseconds: 600));
      await subscription.cancel();
      await Future.delayed(Duration(seconds: 2));
      expect(received.whereType<ScanDone>(), isEmpty);
      expect(
        received.whereType<ScanProgress>().last.addressesProbed,
        lessThan(254),
      );
    });
  });
}
