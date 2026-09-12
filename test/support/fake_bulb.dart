import 'dart:convert';
import 'dart:io';

import 'package:wizctl/wizctl.dart';

/// How a bulb's firmware decides where to send its registration reply.
enum ReplyMode {
  /// Replies to the source port of the datagram it received.
  sourcePort,

  /// Replies to a well-known port on the sender's IP, ignoring the source
  /// port. This is what real WiZ firmware does with the WiZ port (38899).
  fixedPort,
}

/// A stand-in for a WiZ bulb that answers over loopback, so tests never
/// depend on a real network. See AGENTS.md.
class FakeBulb {
  final RawDatagramSocket _socket;
  final String mac;

  /// Number of requests this bulb has received (including ignored ones).
  int requestCount = 0;

  int _toIgnore;

  FakeBulb._(this._socket, this.mac, this._toIgnore);

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
      methodSetPilot,
    },
    // A bulb in Wi-Fi power save loses the first datagrams sent to it;
    // dropping requests models that so retry behaviour can be tested.
    int ignoreFirst = 0,
    // A real bulb's getSystemConfig reply can land after its getPilot one;
    // delaying a method's reply lets a test force that ordering instead of
    // relying on whichever the OS happens to deliver first.
    Map<String, Duration> replyDelays = const {},
  }) async {
    var socket = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      listenPort,
      reuseAddress: true,
      reusePort: true,
    );
    socket.broadcastEnabled = true;
    var bulb = FakeBulb._(socket, mac, ignoreFirst);

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
      if (bulb._toIgnore > 0) {
        bulb._toIgnore--;
        return;
      }

      // getPilot carries the MAC and the pilot but no module name;
      // getSystemConfig has the module name.
      var result = <String, dynamic>{keyMac: mac, 'success': true};
      if (method == methodGetPilot) {
        result[keyState] = true;
        result[keyDimming] = 70;
        result[keyTemperature] = 2700;
      } else {
        result[keyModuleName] = 'ESP01_SHRGB_03';
      }

      var reply = utf8.encode(
        jsonEncode({keyMethod: method, 'env': 'pro', keyResult: result}),
      );
      var target = replyMode == ReplyMode.sourcePort
          ? datagram.port
          : replyToPort;
      var delay = replyDelays[method];
      if (delay == null) {
        socket.send(reply, datagram.address, target);
      } else {
        Future.delayed(
          delay,
          () => socket.send(reply, datagram.address, target),
        );
      }
    }, onError: (Object _) {});

    return bulb;
  }

  void close() => _socket.close();
}
