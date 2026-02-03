import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'constants.dart';
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
  }) async {
    // Default to exponential backoff if not provided
    retry ??= RetryConfig.exponential(
      count: 5,
      initialInterval: Duration(milliseconds: 500),
      maxInterval: maxBackoff,
    );

    final message = {
      keyMethod: methodRegistration,
      keyParams: {
        'phoneMac': discoveryPhoneMac,
        'register': false,
        'phoneIp': discoveryPhoneIp,
        'id': '1',
      },
    };

    final socket = await WizProtocol.sendBroadcast(
      ip: broadcastAddress,
      message: message,
      port: port,
    );

    try {
      final lights = <DiscoveredLight>[];
      final seenMacs = <String>{};
      final completer = Completer<void>();

      // Listen for responses
      final subscription = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            try {
              final responseText = utf8.decode(datagram.data);
              final response = jsonDecode(responseText) as Map<String, dynamic>;
              final light = DiscoveredLight.fromJson(response, datagram.address.address);
              
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
      });

      // Send initial broadcast
      final data = utf8.encode(jsonEncode(message));
      socket.send(data, InternetAddress(broadcastAddress), port);

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
      final timeoutTimer = Timer(timeout, () {
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
    final startTime = DateTime.now();

    void scheduleNext() {
      if (attempt >= retry.count) return;

      Timer(currentInterval, () {
        // Check if we're still within the timeout window
        final elapsedNow = DateTime.now().difference(startTime);
        if (elapsedNow >= timeout) {
          // Timeout expired, don't send more broadcasts
          return;
        }

        socket.send(data, InternetAddress(broadcastAddress), port);
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
  }) async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );

    final allLights = <DiscoveredLight>[];
    final seenMacs = <String>{};

    for (final _ in interfaces) {
      try {
        final lights = await discover(
          broadcastAddress: defaultBroadcastAddress,
          timeout: timeout,
          retry: retry,
          port: port,
        );
        
        for (final light in lights) {
          if (!seenMacs.contains(light.mac)) {
            seenMacs.add(light.mac);
            allLights.add(light);
          }
        }
      } catch (_) {
        // Ignore errors on individual interfaces
        // Continue with other interfaces
      }
    }

    return allLights;
  }
}
