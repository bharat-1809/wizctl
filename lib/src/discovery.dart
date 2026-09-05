import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'constants.dart';
import 'exceptions.dart';
import 'logging.dart';
import 'protocol.dart';
import 'retry_config.dart';
import 'state.dart';

/// Discovers WiZ lights on the local network.
///
/// WiZ lights use a UDP-based discovery protocol where devices respond to
/// broadcast messages with their identification information (MAC address, IP,
/// firmware version, etc.). Since UDP is connectionless and packets can be
/// lost, this implementation supports configurable retry mechanisms to improve
/// reliability.
///
/// **Key Difference from Protocol Requests:**
///
/// - **Discovery uses total timeout**: All broadcasts happen within a single
///   timeout window, and responses are collected continuously throughout.
/// - **Protocol requests use per-attempt timeout**: Each attempt gets its own
///   timeout duration.
///
/// ```dart
/// // Simple discovery with single broadcast
/// final lights = await WizDiscovery.discover();
///
/// // Discovery with exponential backoff retries (default)
/// final lights = await WizDiscovery.discover(
///   retry: RetryConfig.exponential(count: 5, initialInterval: Duration(milliseconds: 500)),
/// );
///
/// // Discovery on all network interfaces
/// final lights = await WizDiscovery.discoverOnAllInterfaces();
/// ```
class WizDiscovery {
  /// Discovers WiZ lights on the local network.
  ///
  /// This method sends UDP broadcast messages to discover WiZ lights. Since
  /// UDP packets can be lost or delayed, you can configure retry behavior to
  /// improve reliability.
  ///
  /// **Parameters:**
  ///
  /// [broadcastAddress] - The broadcast address to use. Defaults to
  ///   '255.255.255.255' which broadcasts to all devices on the local network.
  ///   For specific subnets, use the subnet broadcast address (e.g.,
  ///   '192.168.1.255' for a 192.168.1.x network). This is useful when you
  ///   have multiple network segments and want to target a specific one.
  ///
  /// [timeout] - Total duration to wait for responses from lights. Defaults to
  /// 10 seconds. This is a **total timeout window** - all broadcasts (initial
  ///   + retries) happen within this window, and responses are collected
  ///   continuously throughout. Increase this value on slower networks, when
  ///   expecting many lights, or when lights are known to respond slowly.
  ///
  /// [retry] - Retry configuration. Defaults to exponential backoff with 5
  ///   retries, starting at 500ms and capping at 3 seconds. Set to null for no
  ///   retries (single broadcast only), or customize as needed.
  ///
  /// [port] - The UDP port to use for communication. Defaults to 38899, which
  ///   is the standard WiZ protocol port. Only change this if you're using a
  ///   custom port configuration.
  ///
  /// [localPort] - The local UDP port to bind for receiving replies. Defaults
  ///   to 38899 (the WiZ port) because a lot of WiZ firmware addresses its
  ///   registration reply to the WiZ port on the sender's IP rather than to
  ///   the source port of the request. Binding an ephemeral port would silently
  ///   miss those lights. Pass 0 to use an ephemeral port. If the port is
  ///   already held by another process, discovery falls back to an ephemeral
  ///   port automatically.
  ///
  /// [bindAddress] - Restricts the socket to a single local address, which
  ///   forces the broadcast out of that specific interface. Defaults to all
  ///   interfaces.
  ///
  /// **Returns:** A list of [DiscoveredLight] objects, one for each unique
  ///   light found (deduplicated by MAC address).
  ///
  /// **Example:**
  /// ```dart
  /// // Quick discovery (single broadcast, may miss some lights)
  /// final quick = await WizDiscovery.discover(timeout: Duration(seconds: 2));
  ///
  /// // Reliable discovery with exponential backoff (default)
  /// final reliable = await WizDiscovery.discover(
  ///   timeout: Duration(seconds: 5),
  ///   retry: RetryConfig.exponential(
  ///     count: 5,
  ///     initialInterval: Duration(milliseconds: 500),
  ///     maxInterval: Duration(seconds: 3),
  ///   ),
  /// );
  ///
  /// // Discovery with fixed intervals
  /// final fixed = await WizDiscovery.discover(
  ///   timeout: Duration(seconds: 5),
  ///   retry: RetryConfig.fixed(count: 5, interval: Duration(seconds: 1)),
  /// );
  ///
  /// // Discovery on specific subnet
  /// final subnet = await WizDiscovery.discover(
  ///   broadcastAddress: '192.168.1.255',
  ///   retry: RetryConfig.fixed(count: 3, interval: Duration(milliseconds: 500)),
  /// );
  /// ```
  static Future<List<DiscoveredLight>> discover({
    String broadcastAddress = defaultBroadcastAddress,
    Duration timeout = defaultDiscoveryTimeout,
    RetryConfig? retry,
    int port = wizPort,
    int localPort = wizPort,
    InternetAddress? bindAddress,
  }) async {
    // Default to exponential backoff if not provided
    retry ??= RetryConfig.exponential(
      count: 5,
      initialInterval: Duration(milliseconds: 500),
      maxInterval: maxBackoff,
    );

    var message = {
      keyMethod: methodRegistration,
      keyParams: {
        'phoneMac': discoveryPhoneMac,
        'register': false,
        'phoneIp': discoveryPhoneIp,
        'id': '1',
      },
    };

    // Bind first, listen second, send third. Opening and sending in one step
    // would race: a fast bulb can answer before the listener is attached.
    var socket = await WizProtocol.openBroadcastSocket(
      localPort: localPort,
      bindAddress: bindAddress,
    );

    try {
      var lights = <DiscoveredLight>[];
      var seenMacs = <String>{};
      var completer = Completer<void>();

      // Listen for responses
      var subscription = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          var datagram = socket.receive();
          if (datagram != null) {
            try {
              var responseText = utf8.decode(datagram.data);
              var response = jsonDecode(responseText) as Map<String, dynamic>;

              // We bind the WiZ port itself, so our own broadcast is echoed
              // back to us. Requests carry `params`; replies carry `result`.
              if (response.containsKey(keyParams)) return;

              var light = DiscoveredLight.fromJson(
                response,
                datagram.address.address,
              );

              // Deduplicate by MAC address
              if (light.mac.isNotEmpty && !seenMacs.contains(light.mac)) {
                seenMacs.add(light.mac);
                lights.add(light);
              }
            } catch (_) {
              // Ignore malformed responses
            }
          }
        }
      }, onError: _ignoreAsyncSocketError);

      // Send initial broadcast
      var data = utf8.encode(jsonEncode(message));
      var sent = WizProtocol.sendBroadcast(
        socket: socket,
        ip: broadcastAddress,
        data: data,
        port: port,
      );
      if (!sent) {
        await subscription.cancel();
        throw WizConnectionError(
          'Could not broadcast to $broadcastAddress:$port from '
          '${socket.address.address}',
        );
      }

      // Handle retries if configured
      if (retry.enabled) {
        _scheduleRetries(
          socket: socket,
          data: data,
          broadcastAddress: broadcastAddress,
          port: port,
          retry: retry,
          timeout: timeout,
        );
      }

      // Overall timeout (total window for collecting responses)
      var timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete();
      });

      await completer.future;
      timeoutTimer.cancel();
      await subscription.cancel();

      return lights;
    } finally {
      socket.close();
    }
  }

  /// Schedules retry broadcasts according to the retry configuration.
  ///
  /// All broadcasts are scheduled within the total timeout window.
  static void _scheduleRetries({
    required RawDatagramSocket socket,
    required List<int> data,
    required String broadcastAddress,
    required int port,
    required RetryConfig retry,
    required Duration timeout,
  }) {
    if (retry.count == 0) return;

    int attempt = 0;
    Duration currentInterval = retry.interval;
    var startTime = DateTime.now();

    void scheduleNext() {
      if (attempt >= retry.count) return;

      Timer(currentInterval, () {
        // Check if we're still within the timeout window
        var elapsedNow = DateTime.now().difference(startTime);
        if (elapsedNow >= timeout) {
          // Timeout expired, don't send more broadcasts
          return;
        }

        // A failed send here would otherwise escape the timer as an unhandled
        // async error, so stop retrying instead of throwing.
        var sent = WizProtocol.sendBroadcast(
          socket: socket,
          ip: broadcastAddress,
          data: data,
          port: port,
        );
        if (!sent) return;
        attempt++;

        if (attempt < retry.count) {
          // Calculate next interval based on strategy
          if (retry.strategy == RetryStrategy.exponential) {
            currentInterval = retry.nextExponentialInterval(currentInterval);
          }
          // For fixed strategy, currentInterval stays the same

          // Schedule next broadcast
          scheduleNext();
        }
      });
    }

    scheduleNext();
  }

  /// Discovers lights on all network interfaces.
  ///
  /// This method is useful when your device has multiple network interfaces
  /// (e.g., WiFi and Ethernet, or multiple network adapters). It discovers
  /// lights on each interface separately and combines the results.
  ///
  /// **When to use this method:**
  /// - Your device has multiple network interfaces (WiFi + Ethernet, VPNs, etc.)
  /// - Lights might be on different network segments
  /// - The global broadcast address (255.255.255.255) doesn't reach all networks
  /// - You want maximum coverage across all available networks
  ///
  /// **How it works:**
  /// 1. Lists all IPv4 network interfaces on the system
  /// 2. Calls [discover] for each interface
  /// 3. Combines and deduplicates results by MAC address
  ///
  /// **Parameters:**
  ///
  /// [timeout] - How long to wait for responses on each interface. This timeout
  ///   applies to each interface discovery separately, so the total time may be
  ///   longer if you have many interfaces. Defaults to 5 seconds per interface.
  ///
  /// [retry] - Retry configuration for each interface discovery. Defaults to
  ///   exponential backoff with 5 retries, starting at 500ms and capping at
  ///   3 seconds. Set to null for no retries, or customize as needed.
  ///
  /// [port] - The UDP port to use. Defaults to 38899 (standard WiZ port).
  ///
  /// **Returns:** A deduplicated list of all discovered lights across all
  ///   interfaces, with each light appearing only once (based on MAC address).
  ///
  /// **Example:**
  /// ```dart
  /// // Discover on all interfaces with default retries
  /// final allLights = await WizDiscovery.discoverOnAllInterfaces();
  ///
  /// // Discover on all interfaces with custom retry config
  /// final allLights = await WizDiscovery.discoverOnAllInterfaces(
  ///   timeout: Duration(seconds: 5),
  ///   retry: RetryConfig.exponential(
  ///     count: 3,
  ///     initialInterval: Duration(milliseconds: 500),
  ///   ),
  /// );
  /// ```
  static Future<List<DiscoveredLight>> discoverOnAllInterfaces({
    Duration timeout = defaultDiscoveryTimeout,
    RetryConfig? retry,
    int port = wizPort,
    int localPort = wizPort,
  }) async {
    var interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );

    var allLights = <DiscoveredLight>[];
    var seenMacs = <String>{};

    for (var interface in interfaces) {
      for (var address in interface.addresses) {
        // Binding to the interface's own address is what actually pins the
        // broadcast to that interface. Without it every iteration would just
        // repeat the same discovery out of the default route.
        try {
          WizLogger.info(
            'Discovering on ${interface.name} (${address.address})',
          );
          var lights = await discover(
            broadcastAddress: defaultBroadcastAddress,
            timeout: timeout,
            retry: retry,
            port: port,
            localPort: localPort,
            bindAddress: address,
          );

          for (var light in lights) {
            if (!seenMacs.contains(light.mac)) {
              seenMacs.add(light.mac);
              allLights.add(light);
            }
          }
        } catch (e) {
          // An interface that can't broadcast (down, no route) shouldn't stop
          // the others.
          WizLogger.warn('Discovery failed on ${interface.name}: $e');
        }
      }
    }

    return allLights;
  }

  /// Finds lights by probing every address on a subnet directly, one at a time.
  ///
  /// Use this when [discover] comes back empty on a network where the lights
  /// are demonstrably reachable. On some networks lights never answer the
  /// discovery broadcast even though they respond to unicast immediately —
  /// access points filter broadcast to wireless clients, and Wi-Fi power save
  /// on the bulb means broadcast frames are only delivered on the access
  /// point's DTIM schedule and are easily missed. Either way no implementation
  /// of the WiZ protocol can find those lights by broadcasting, while asking
  /// each address in turn works reliably.
  ///
  /// Each address is probed with both `getSystemConfig` and `getPilot`.
  /// `getSystemConfig` is the richer answer — module name and firmware version
  /// as well as the MAC — but it is not implemented by every firmware version,
  /// and `getPilot` carries the MAC too. Probing with both means an older bulb
  /// still turns up, just with less detail.
  ///
  /// **Parameters:**
  ///
  /// [subnet] - The first three octets to scan, e.g. `'192.168.0'`. Defaults to
  ///   the subnet of this machine's own address. Note the /24 assumption:
  ///   Dart's [NetworkInterface] does not expose netmasks, so a network wider
  ///   than /24 has to be scanned a /24 at a time.
  ///
  /// [timeout] - Total time budget. Probes go out at the start of the window
  ///   and replies are collected until it expires, so allow a few seconds.
  ///
  /// [rounds] - How many times to probe each address. Defaults to 2, and going
  ///   below that is unwise: with a cold ARP cache the kernel drops the first
  ///   datagram to each host while it resolves the MAC, so a single round
  ///   misses lights it has never talked to.
  ///
  /// Probes go out in batches (see [subnetScanBatchSize]), so sweeping a /24
  /// takes several seconds per round whatever [timeout] says. Replies are
  /// collected throughout, and [timeout] only governs how long to keep
  /// listening after the last probe.
  ///
  /// **Returns:** The lights that answered, deduplicated by MAC address.
  static Future<List<DiscoveredLight>> scanSubnet({
    String? subnet,
    Duration timeout = defaultDiscoveryTimeout,
    int port = wizPort,
    int localPort = wizPort,
    InternetAddress? bindAddress,
    int rounds = subnetScanRounds,
  }) async {
    var base = subnet ?? await _defaultSubnetBase();
    if (base == null) {
      throw WizConnectionError('Could not determine a local subnet to scan');
    }

    var skip = await _localAddresses();
    var addresses = [
      for (var host = 1; host <= 254; host++)
        if (!skip.contains('$base.$host')) '$base.$host',
    ];

    WizLogger.info('Scanning $base.1-254 on port $port');

    // One socket per chunk: see [subnetScanChunkSize].
    var byMac = <String, DiscoveredLight>{};
    for (
      var start = 0;
      start < addresses.length;
      start += subnetScanChunkSize
    ) {
      var chunk = addresses.skip(start).take(subnetScanChunkSize).toList();
      try {
        var found = await probeAddresses(
          addresses: chunk,
          timeout: timeout,
          port: port,
          localPort: localPort,
          bindAddress: bindAddress,
          rounds: rounds,
        );
        for (var light in found) {
          byMac.putIfAbsent(light.mac, () => light);
        }
      } catch (e) {
        // A chunk that fails outright must not lose the ones already found.
        WizLogger.warn('Scan chunk ${chunk.first}-${chunk.last} failed: $e');
      }
    }

    return byMac.values.toList();
  }

  /// Asks specific addresses whether a light is listening there.
  ///
  /// This is the reliable half of [scanSubnet]. Probing a handful of known
  /// addresses succeeds where sweeping a whole subnet does not, and the reason
  /// is the kernel rather than the lights: `net.link.ether.inet.maxhold` caps
  /// how many datagrams may be queued awaiting ARP resolution (16 on macOS).
  /// Sweeping a /24 queues one against every empty address, the hold queue
  /// overflows, and probes aimed at addresses that *do* have a light behind
  /// them get dropped along with the rest. The table only drains on
  /// `net.link.ether.inet.prune_intvl`, so a sweep can stay unproductive for
  /// minutes afterwards. Probing addresses you already know never fills it.
  ///
  /// Prefer this for lights already in a config file, and fall back to
  /// [scanSubnet] to find ones you have not seen before.
  static Future<List<DiscoveredLight>> probeAddresses({
    required Iterable<String> addresses,
    Duration timeout = defaultDiscoveryTimeout,
    int port = wizPort,
    int localPort = wizPort,
    InternetAddress? bindAddress,
    int rounds = subnetScanRounds,
  }) async {
    var targets = addresses.toList();
    if (targets.isEmpty) return [];

    var socket = await WizProtocol.openBroadcastSocket(
      localPort: localPort,
      bindAddress: bindAddress,
    );

    try {
      // Keyed by MAC: a bulb answers both probes, and the two replies carry
      // different amounts of detail.
      var byMac = <String, DiscoveredLight>{};

      var subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        var datagram = socket.receive();
        if (datagram == null) return;
        try {
          var response =
              jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
          // Requests carry `params`, replies carry `result`; skip our own.
          if (response.containsKey(keyParams)) return;

          var light = DiscoveredLight.fromJson(
            response,
            datagram.address.address,
          );
          if (light.mac.isEmpty) return;

          var known = byMac[light.mac];
          if (known == null) {
            byMac[light.mac] = light;
            WizLogger.info('Found ${light.mac} at ${light.ip}');
          } else if (known.moduleName == null && light.moduleName != null) {
            // A getSystemConfig reply landing after a getPilot one: keep the
            // richer of the two.
            byMac[light.mac] = light;
          }
        } catch (_) {
          // Ignore malformed responses
        }
      }, onError: _ignoreAsyncSocketError);

      var probes = [
        utf8.encode(
          jsonEncode({keyMethod: methodGetSystemConfig, keyParams: {}}),
        ),
        utf8.encode(jsonEncode({keyMethod: methodGetPilot, keyParams: {}})),
      ];
      var deadline = DateTime.now().add(timeout);

      for (var round = 0; round < rounds; round++) {
        if (round > 0) await Future.delayed(subnetScanRoundInterval);

        var unreachable = 0;
        for (
          var start = 0;
          start < targets.length;
          start += subnetScanBatchSize
        ) {
          var batch = targets.skip(start).take(subnetScanBatchSize);
          for (var ip in batch) {
            var address = InternetAddress(ip);
            for (var probe in probes) {
              // Failures here are reported asynchronously (see
              // [_ignoreAsyncSocketError]), but guard anyway: a synchronous
              // throw for one address must not abort the rest.
              try {
                socket.send(probe, address, port);
              } on SocketException {
                unreachable++;
              }
            }
          }
          // Let the ARP hold queue drain before queuing the next batch.
          await Future.delayed(subnetScanBatchInterval);
        }
        WizLogger.verbose(
          'Round ${round + 1}/$rounds probed ${targets.length} address(es) '
          '($unreachable unreachable)',
        );
      }

      // Collect for whatever is left of the window.
      var remaining = deadline.difference(DateTime.now());
      if (remaining > Duration.zero) await Future.delayed(remaining);

      await subscription.cancel();
      return byMac.values.toList();
    } finally {
      socket.close();
    }
  }

  /// Swallows the socket errors that discovery provokes by design.
  ///
  /// [RawDatagramSocket.send] does not throw when the OS rejects a datagram —
  /// it returns 0 and delivers the [SocketException] asynchronously on the
  /// socket's own stream. Probing an address with nothing behind it produces
  /// exactly that ("No route to host", "Host is down"), so a broadcast or a
  /// subnet scan generates them by the hundred. Without a handler here each one
  /// becomes an unhandled async error that terminates the process.
  static void _ignoreAsyncSocketError(Object error) {
    WizLogger.verbose('Ignoring socket error while probing: $error');
  }

  /// This machine's own IPv4 addresses, so a scan doesn't probe itself.
  static Future<Set<String>> _localAddresses() async {
    var interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    return {
      for (var interface in interfaces)
        for (var address in interface.addresses) address.address,
    };
  }

  /// The `a.b.c` prefix of this machine's LAN address.
  ///
  /// Prefers RFC1918 space so a VPN adapter (Tailscale hands out 100.64/10,
  /// which is carrier-grade NAT space, not a LAN) doesn't get scanned instead
  /// of the network the lights are actually on.
  static Future<String?> _defaultSubnetBase() async {
    var interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );

    String? fallback;
    for (var interface in interfaces) {
      for (var address in interface.addresses) {
        if (address.isLoopback) continue;
        var octets = address.address.split('.');
        if (octets.length != 4) continue;
        var base = octets.take(3).join('.');
        if (_isPrivateLan(octets)) return base;
        fallback ??= base;
      }
    }
    return fallback;
  }

  static bool _isPrivateLan(List<String> octets) {
    var first = int.tryParse(octets[0]);
    var second = int.tryParse(octets[1]);
    if (first == null || second == null) return false;
    return first == 10 ||
        (first == 192 && second == 168) ||
        (first == 172 && second >= 16 && second <= 31);
  }
}
