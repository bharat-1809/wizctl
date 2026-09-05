import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wizctl/wizctl.dart';

/// How a bulb's firmware decides where to send its registration reply.
enum ReplyMode {
  /// Replies to the source port of the datagram it received.
  sourcePort,

  /// Replies to a well-known port on the sender's IP, ignoring the source
  /// port. This is what real WiZ firmware does with the WiZ port (38899).
  fixedPort,
}

/// A stand-in for a WiZ bulb that answers `registration` broadcasts.
///
/// Tests talk to it over loopback so they don't depend on a real network.
class FakeBulb {
  final RawDatagramSocket _socket;
  final String mac;

  /// Number of `registration` requests this bulb has received.
  int requestCount = 0;

  FakeBulb._(this._socket, this.mac);

  int get port => _socket.port;

  static Future<FakeBulb> start({
    required int listenPort,
    required ReplyMode replyMode,
    int replyToPort = 0,
    String mac = 'a8bb50aabbcc',
    Set<String> supportedMethods = const {
      methodRegistration,
      methodGetSystemConfig,
      methodGetPilot,
    },
  }) async {
    var socket = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      listenPort,
      reuseAddress: true,
      reusePort: true,
    );
    socket.broadcastEnabled = true;
    var bulb = FakeBulb._(socket, mac);

    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      var datagram = socket.receive();
      if (datagram == null) return;

      Map<String, dynamic> request;
      try {
        request =
            jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
      // Only answer requests; never react to a reply (avoids a self-send loop
      // when the bulb and the reply port are the same socket).
      var method = request[keyMethod];
      if (method is! String || !supportedMethods.contains(method)) return;
      if (request.containsKey(keyResult)) return;
      bulb.requestCount++;

      // getPilot carries the MAC but no module name; getSystemConfig has both.
      var result = <String, dynamic>{keyMac: mac, 'success': true};
      if (method != methodGetPilot) {
        result[keyModuleName] = 'ESP01_SHRGB_03';
      }

      var reply = utf8.encode(
        jsonEncode({keyMethod: method, 'env': 'pro', keyResult: result}),
      );
      var target = replyMode == ReplyMode.sourcePort
          ? datagram.port
          : replyToPort;
      socket.send(reply, datagram.address, target);
    });

    return bulb;
  }

  void close() => _socket.close();
}

void main() {
  group('WizDiscovery.discover', () {
    // Ports picked to be well clear of the real WiZ port so a live bulb (or a
    // running WiZ app) on the machine can't influence the result.
    const bulbPort = 39411;
    const replyPort = 39412;

    test('finds a bulb that replies to the source port', () async {
      var bulb = await FakeBulb.start(
        listenPort: bulbPort,
        replyMode: ReplyMode.sourcePort,
      );
      addTearDown(bulb.close);

      var lights = await WizDiscovery.discover(
        broadcastAddress: '127.0.0.1',
        port: bulbPort,
        localPort: replyPort,
        timeout: Duration(seconds: 2),
        retry: RetryConfig.none(),
      );

      expect(lights, hasLength(1));
      expect(lights.single.mac, 'a8bb50aabbcc');
      expect(lights.single.moduleName, 'ESP01_SHRGB_03');
    });

    test(
      'finds a bulb that replies to the WiZ port instead of the source port',
      () async {
        // Regression test: discovery used to bind an ephemeral local port, so
        // replies addressed to the WiZ port were delivered to nobody and every
        // bulb with this firmware behaviour was invisible.
        var bulb = await FakeBulb.start(
          listenPort: bulbPort,
          replyMode: ReplyMode.fixedPort,
          replyToPort: replyPort,
        );
        addTearDown(bulb.close);

        var lights = await WizDiscovery.discover(
          broadcastAddress: '127.0.0.1',
          port: bulbPort,
          localPort: replyPort,
          timeout: Duration(seconds: 2),
          retry: RetryConfig.none(),
        );

        expect(lights, hasLength(1));
        expect(lights.single.mac, 'a8bb50aabbcc');
      },
    );

    test('sends exactly one broadcast when retries are disabled', () async {
      // Regression test: the broadcast was sent once while opening the socket
      // and again after the listener was attached, doubling every request.
      var bulb = await FakeBulb.start(
        listenPort: bulbPort,
        replyMode: ReplyMode.sourcePort,
      );
      addTearDown(bulb.close);

      await WizDiscovery.discover(
        broadcastAddress: '127.0.0.1',
        port: bulbPort,
        localPort: replyPort,
        timeout: Duration(seconds: 1),
        retry: RetryConfig.none(),
      );

      expect(bulb.requestCount, 1);
    });

    test('sends one broadcast per configured retry', () async {
      var bulb = await FakeBulb.start(
        listenPort: bulbPort,
        replyMode: ReplyMode.sourcePort,
      );
      addTearDown(bulb.close);

      await WizDiscovery.discover(
        broadcastAddress: '127.0.0.1',
        port: bulbPort,
        localPort: replyPort,
        timeout: Duration(seconds: 3),
        retry: RetryConfig.fixed(
          count: 2,
          interval: Duration(milliseconds: 200),
        ),
      );

      // 1 initial broadcast + 2 retries.
      expect(bulb.requestCount, 3);
    });

    test('does not report our own broadcast as a light', () async {
      // Binding the WiZ port means our own broadcast is echoed back to us.
      var lights = await WizDiscovery.discover(
        broadcastAddress: '127.0.0.1',
        port: bulbPort,
        localPort: replyPort,
        timeout: Duration(milliseconds: 700),
        retry: RetryConfig.none(),
      );

      expect(lights, isEmpty);
    });

    test(
      'falls back to an ephemeral port when the local port is taken',
      () async {
        // Another process (the WiZ app, a second wizctl) may already hold the
        // port. Discovery must still work for source-port firmware.
        var squatter = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          replyPort,
        );
        addTearDown(squatter.close);

        // Guard the premise: if the port were still bindable this test would
        // pass without ever exercising the fallback.
        await expectLater(
          RawDatagramSocket.bind(InternetAddress.anyIPv4, replyPort),
          throwsA(isA<SocketException>()),
        );

        var bulb = await FakeBulb.start(
          listenPort: bulbPort,
          replyMode: ReplyMode.sourcePort,
        );
        addTearDown(bulb.close);

        var lights = await WizDiscovery.discover(
          broadcastAddress: '127.0.0.1',
          port: bulbPort,
          localPort: replyPort,
          timeout: Duration(seconds: 2),
          retry: RetryConfig.none(),
        );

        expect(lights, hasLength(1));
      },
    );

    test('deduplicates bulbs that answer more than once', () async {
      var bulb = await FakeBulb.start(
        listenPort: bulbPort,
        replyMode: ReplyMode.sourcePort,
      );
      addTearDown(bulb.close);

      var lights = await WizDiscovery.discover(
        broadcastAddress: '127.0.0.1',
        port: bulbPort,
        localPort: replyPort,
        timeout: Duration(seconds: 2),
        retry: RetryConfig.fixed(
          count: 3,
          interval: Duration(milliseconds: 150),
        ),
      );

      expect(bulb.requestCount, greaterThan(1));
      expect(lights, hasLength(1));
    });
  });

  group('WizDiscovery.scanSubnet', () {
    const bulbPort = 39413;
    const replyPort = 39414;

    test('finds a bulb by unicast when broadcast never reaches it', () async {
      // The real-world case: the lights never answer the discovery broadcast,
      // so no broadcast-based discovery can see them, but unicast to each
      // address still works.
      var bulb = await FakeBulb.start(
        listenPort: bulbPort,
        replyMode: ReplyMode.sourcePort,
      );
      addTearDown(bulb.close);

      var lights = await WizDiscovery.probeAddresses(
        addresses: const ['127.0.0.1'],
        port: bulbPort,
        localPort: replyPort,
        timeout: Duration(seconds: 3),
        rounds: 1,
      );

      expect(lights, hasLength(1));
      expect(lights.single.ip, '127.0.0.1');
      expect(lights.single.mac, 'a8bb50aabbcc');
      expect(lights.single.moduleName, 'ESP01_SHRGB_03');
    });

    test('keeps scanning when individual addresses are unreachable', () async {
      // 253 of the 254 probes in the test above hit nothing. This asserts the
      // documented-unroutable case explicitly: a send failure on one address
      // must not abort the whole scan.
      var lights = await WizDiscovery.scanSubnet(
        subnet: '192.0.2', // TEST-NET-1, reserved and unroutable
        port: bulbPort,
        localPort: replyPort,
        timeout: Duration(seconds: 2),
        rounds: 1,
      );

      expect(lights, isEmpty);
    });

    test('deduplicates across rounds', () async {
      var bulb = await FakeBulb.start(
        listenPort: bulbPort,
        replyMode: ReplyMode.sourcePort,
      );
      addTearDown(bulb.close);

      var lights = await WizDiscovery.probeAddresses(
        addresses: const ['127.0.0.1'],
        port: bulbPort,
        localPort: replyPort,
        timeout: Duration(seconds: 4),
        rounds: 2,
      );

      expect(bulb.requestCount, greaterThan(1));
      expect(lights, hasLength(1));
    });
  });

  group('asynchronous socket errors', () {
    // RawDatagramSocket.send does not throw when the OS rejects a datagram: it
    // returns 0 and delivers the SocketException asynchronously on the socket's
    // own stream. A listener with no onError handler turns that into an
    // unhandled async exception that kills the process — the intermittent
    // "socket exception" crash. A socket bound to loopback cannot reach a
    // routable address, which reproduces it deterministically and offline.
    const deadSubnet = '10.99.99';
    const unusedPort = 39415;

    test('scanSubnet survives asynchronous send failures', () async {
      var lights = await WizDiscovery.scanSubnet(
        subnet: deadSubnet,
        bindAddress: InternetAddress.loopbackIPv4,
        port: unusedPort,
        localPort: 0,
        timeout: Duration(seconds: 2),
        rounds: 1,
      );

      expect(lights, isEmpty);
    });

    test('discover survives asynchronous send failures', () async {
      await expectLater(
        WizDiscovery.discover(
          broadcastAddress: '$deadSubnet.1',
          bindAddress: InternetAddress.loopbackIPv4,
          port: unusedPort,
          localPort: 0,
          timeout: Duration(seconds: 2),
          retry: RetryConfig.none(),
        ),
        throwsA(isA<WizConnectionError>()),
      );
      // Give the asynchronous error time to land after discover() returned.
      await Future.delayed(Duration(milliseconds: 500));
    });

    test(
      'a unicast request reports a clean error instead of crashing',
      () async {
        await expectLater(
          WizLight('0.0.0.0', timeout: Duration(milliseconds: 300)).getState(),
          throwsA(isA<WizException>()),
        );
        await Future.delayed(Duration(milliseconds: 500));
      },
    );
  });

  group('WizDiscovery.scanSubnet firmware tolerance', () {
    const bulbPort = 39417;
    const replyPort = 39418;

    test('finds a bulb whose firmware has no getSystemConfig', () async {
      // Older WiZ firmware does not implement every method. getPilot carries
      // the MAC too, so such a bulb must still be discovered - with less
      // detail rather than not at all.
      var bulb = await FakeBulb.start(
        listenPort: bulbPort,
        replyMode: ReplyMode.sourcePort,
        supportedMethods: const {methodGetPilot},
      );
      addTearDown(bulb.close);

      var lights = await WizDiscovery.probeAddresses(
        addresses: const ['127.0.0.1'],
        port: bulbPort,
        localPort: replyPort,
        timeout: Duration(seconds: 3),
        rounds: 1,
      );

      expect(lights, hasLength(1));
      expect(lights.single.mac, 'a8bb50aabbcc');
      expect(lights.single.moduleName, isNull);
    });

    test('prefers the richer reply when the firmware answers both', () async {
      var bulb = await FakeBulb.start(
        listenPort: bulbPort,
        replyMode: ReplyMode.sourcePort,
      );
      addTearDown(bulb.close);

      var lights = await WizDiscovery.probeAddresses(
        addresses: const ['127.0.0.1'],
        port: bulbPort,
        localPort: replyPort,
        timeout: Duration(seconds: 3),
        rounds: 1,
      );

      expect(lights, hasLength(1));
      expect(lights.single.moduleName, 'ESP01_SHRGB_03');
    });
  });
}
