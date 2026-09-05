import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'constants.dart';
import 'exceptions.dart';
import 'logging.dart';
import 'retry_config.dart';

/// UDP protocol client for WiZ light communication.
///
class WizProtocol {
  WizProtocol._();

  /// Sends a JSON message to a WiZ light
  ///
  /// This method uses **per-attempt timeout**: each retry attempt gets its own
  /// full timeout duration.
  ///
  /// **Parameters:**
  ///
  /// [ip] - The IP address of the light.
  /// [message] - The JSON message to send.
  /// [port] - The port to send to (defaults to [wizPort]).
  /// [timeout] - Per-attempt timeout duration (defaults to [defaultTimeout]).
  ///   Each retry attempt waits for this full duration before timing out.
  ///   Total operation time = timeout * (attempts) + retry_intervals.
  /// [retry] - Retry configuration. Defaults to exponential backoff with
  ///   5 retries, starting at 750ms and capping at 3 seconds. Set to
  ///   [RetryConfig.none()] to disable retries.
  ///
  /// **Returns:** The parsed JSON response from the light.
  ///
  /// **Throws:**
  /// - [WizTimeoutError] if no response after all retries.
  /// - [WizConnectionError] if there's a network error.
  /// - [WizMethodNotFoundError] if the method is not supported.
  /// - [WizResponseError] if the response indicates an error.
  ///
  /// **Example:**
  /// ```dart
  /// // Default retry behavior (exponential backoff)
  /// final response = await WizProtocol.send(
  ///   ip: '192.168.1.100',
  ///   message: {'method': 'getPilot', 'params': {}},
  /// );
  ///
  /// // Custom retry configuration
  /// final response = await WizProtocol.send(
  ///   ip: '192.168.1.100',
  ///   message: {'method': 'getPilot', 'params': {}},
  ///   retry: RetryConfig.fixed(count: 3, interval: Duration(seconds: 1)),
  /// );
  /// ```
  static Future<Map<String, dynamic>> send({
    required String ip,
    required Map<String, dynamic> message,
    int port = wizPort,
    Duration timeout = defaultTimeout,
    RetryConfig? retry,
  }) async {
    // Use default retry config if not provided (matches old behavior)
    var retryConfig =
        retry ??
        RetryConfig.exponential(
          count:
              maxSendDatagrams - 1, // -1 because first attempt is not a retry
          initialInterval: firstSendInterval,
          maxInterval: maxBackoff,
        );
    RawDatagramSocket? socket;
    var method = message[keyMethod] as String? ?? 'unknown';
    var messageJson = jsonEncode(message);

    WizLogger.info('Sending $method to $ip:$port');
    WizLogger.debug('Request: $messageJson');

    try {
      // Bind to any available port
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      WizLogger.verbose('Bound to local port ${socket.port}');

      var data = utf8.encode(messageJson);
      var address = InternetAddress(ip);
      var completer = Completer<Map<String, dynamic>>();
      // Attach an error listener straight away. The completer can be completed
      // with an error before the code below reaches its `await`, and a future
      // that holds an error with nobody listening is reported as an unhandled
      // async error, which terminates the process.
      completer.future.catchError((Object _) => <String, dynamic>{});
      var attemptNumber = 0;
      var currentRetryInterval = retryConfig.interval;
      Timer? attemptTimeoutTimer;
      SocketException? lastSocketError;

      // How this request should fail. `send` reports an unreachable host
      // asynchronously rather than by throwing, so when we saw such an error
      // it is a far better explanation than a bare timeout.
      Object failure() => lastSocketError != null
          ? WizConnectionError('Cannot reach $ip:$port', lastSocketError)
          : WizTimeoutError(
              ip: ip,
              timeout: timeout,
              retryCount: attemptNumber,
            );

      var subscription = socket.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            var datagram = socket!.receive();
            if (datagram != null) {
              var responseText = utf8.decode(datagram.data);
              WizLogger.debug(
                'Received from ${datagram.address.address}: $responseText',
              );

              try {
                var response = jsonDecode(responseText) as Map<String, dynamic>;

                if (response.containsKey(keyError)) {
                  var error = response[keyError] as Map<String, dynamic>;
                  var code = error[keyCode] as int?;
                  var errorMsg = error['message'] as String? ?? 'Unknown error';

                  WizLogger.error(
                    'Error response: code=$code, message=$errorMsg',
                  );

                  if (code == errorCodeMethodNotFound) {
                    if (!completer.isCompleted) {
                      completer.completeError(
                        WizMethodNotFoundError(method: method, ip: ip),
                      );
                    }
                    return;
                  }

                  if (!completer.isCompleted) {
                    completer.completeError(
                      WizResponseError(
                        'Error from light: $errorMsg',
                        errorCode: code,
                        rawResponse: responseText,
                      ),
                    );
                  }
                  return;
                }

                WizLogger.info('Success: $method response from $ip');
                if (!completer.isCompleted) {
                  attemptTimeoutTimer?.cancel();
                  completer.complete(response);
                }
              } catch (e) {
                WizLogger.error('Failed to parse response: $e');
                if (!completer.isCompleted) {
                  completer.completeError(
                    WizResponseError(
                      'Failed to parse response from $ip',
                      rawResponse: responseText,
                      cause: e,
                    ),
                  );
                }
              }
            }
          }
        },
        onError: (Object error) {
          // [RawDatagramSocket.send] returns 0 and reports the failure here
          // instead of throwing, so this is the only place an unreachable host
          // surfaces. Without this handler it becomes an unhandled async error
          // that terminates the process.
          if (error is SocketException) lastSocketError = error;
          WizLogger.debug('Socket error talking to $ip: $error');
        },
      );

      Future<void> sendWithRetry() async {
        // Always make at least one attempt
        var maxAttempts = retryConfig.count + 1;

        while (!completer.isCompleted && attemptNumber < maxAttempts) {
          attemptNumber++;
          var bytesSent = socket!.send(data, address, port);
          WizLogger.debug(
            'Attempt $attemptNumber/$maxAttempts: sent $bytesSent bytes',
          );

          if (bytesSent != data.length) {
            // The OS refused the datagram - typically an unresolved ARP entry
            // for a host that is asleep. The reason arrives asynchronously on
            // the socket, not as a throw. Treat it as a failed attempt: the
            // next one usually succeeds once ARP has resolved.
            WizLogger.debug('Incomplete send: $bytesSent/${data.length} bytes');
            if (attemptNumber < maxAttempts) {
              await Future.delayed(currentRetryInterval);
              if (retryConfig.strategy == RetryStrategy.exponential) {
                currentRetryInterval = retryConfig.nextExponentialInterval(
                  currentRetryInterval,
                );
              }
              continue;
            }
            if (!completer.isCompleted) completer.completeError(failure());
            return;
          }

          // Set up per-attempt timeout
          attemptTimeoutTimer?.cancel();
          var attemptTimedOut = false;

          attemptTimeoutTimer = Timer(timeout, () {
            if (!completer.isCompleted) {
              WizLogger.debug(
                'Attempt $attemptNumber timed out after ${timeout.inSeconds}s',
              );
              attemptTimedOut = true;
            }
          });

          // Wait for response with timeout
          try {
            await completer.future.timeout(timeout);
            // If we get here, completer completed successfully (got a response)
          } on TimeoutException {
            attemptTimedOut = true;
          } catch (_) {
            // Error already handled by completer
          }

          attemptTimeoutTimer?.cancel();

          // If we got a response, we're done
          if (completer.isCompleted) {
            break;
          }

          // If we timed out and have more retries, wait and retry
          if (attemptTimedOut && attemptNumber < maxAttempts) {
            WizLogger.verbose(
              'Waiting ${currentRetryInterval.inMilliseconds}ms before retry',
            );
            await Future.delayed(currentRetryInterval);

            // Calculate next interval based on strategy
            if (retryConfig.strategy == RetryStrategy.exponential) {
              currentRetryInterval = retryConfig.nextExponentialInterval(
                currentRetryInterval,
              );
            }
            // For fixed strategy, currentRetryInterval stays the same
          } else if (attemptTimedOut) {
            // No more retries left
            WizLogger.error('Giving up after $attemptNumber attempts to $ip');
            if (!completer.isCompleted) {
              completer.completeError(failure());
            }
            break;
          }
        }

        // Ensure completer is always completed (safety check)
        if (!completer.isCompleted) {
          WizLogger.error('Giving up after $attemptNumber attempts to $ip');
          completer.completeError(failure());
        }
      }

      await sendWithRetry();
      // At this point, sendWithRetry has completed, so completer should be completed
      // (either with a response or an error, due to the safety check in sendWithRetry)

      try {
        // Use a timeout as a safety measure to ensure we always return
        var maxWait = Duration(seconds: 1);
        var result = await completer.future.timeout(
          maxWait,
          onTimeout: () {
            // This should never happen, but ensure we always return
            if (!completer.isCompleted) {
              completer.completeError(
                WizTimeoutError(
                  ip: ip,
                  timeout: timeout,
                  retryCount: attemptNumber,
                ),
              );
            }
            throw WizTimeoutError(
              ip: ip,
              timeout: timeout,
              retryCount: attemptNumber,
            );
          },
        );
        return result;
      } finally {
        attemptTimeoutTimer?.cancel();
        await subscription.cancel();
      }
    } on SocketException catch (e) {
      WizLogger.error('Socket error: $e');
      throw WizConnectionError('Socket error with $ip:$port', e);
    } finally {
      socket?.close();
      WizLogger.verbose('Socket closed');
    }
  }

  /// Opens a broadcast-enabled socket for discovery.
  ///
  /// Nothing is sent yet: the caller attaches its listener first, then sends,
  /// so no response can arrive before anyone is listening for it.
  ///
  /// [localPort] is the local port to bind. It defaults to [wizPort] on
  /// purpose. WiZ firmware does not consistently reply to the source port of
  /// the request; a lot of it addresses the reply to the WiZ port on the
  /// sender's IP. A socket on an ephemeral port therefore never sees those
  /// replies and the bulb looks absent. Binding [wizPort] catches both
  /// behaviours. Pass 0 for an ephemeral port.
  ///
  /// [bindAddress] restricts the socket to one local address, which forces
  /// broadcasts out of that specific interface. Defaults to all interfaces.
  ///
  /// If [localPort] is already taken (the WiZ app or another wizctl run holds
  /// it), this falls back to an ephemeral port rather than failing outright —
  /// degraded, but still able to find source-port firmware.
  ///
  /// Returns the socket for receiving responses. Caller is responsible for
  /// closing it.
  static Future<RawDatagramSocket> openBroadcastSocket({
    int localPort = wizPort,
    InternetAddress? bindAddress,
  }) async {
    var address = bindAddress ?? InternetAddress.anyIPv4;

    try {
      RawDatagramSocket socket;
      try {
        // Deliberately no reusePort: sharing the port would let the bind
        // succeed while unicast replies get delivered to whichever socket the
        // kernel picks. Losing lights at random is worse than failing loudly
        // and falling back below.
        socket = await RawDatagramSocket.bind(address, localPort);
      } on SocketException catch (e) {
        if (localPort == 0) rethrow;
        WizLogger.warn(
          'Could not bind local port $localPort ($e). Falling back to an '
          'ephemeral port; lights whose firmware replies to port $localPort '
          'instead of the request source port will not be discovered.',
        );
        socket = await RawDatagramSocket.bind(address, 0);
      }

      socket.broadcastEnabled = true;
      WizLogger.verbose(
        'Broadcast socket on ${address.address}:${socket.port}',
      );
      return socket;
    } on SocketException catch (e) {
      WizLogger.error('Failed to open broadcast socket: $e');
      throw WizConnectionError(
        'Failed to open broadcast socket on ${address.address}:$localPort',
        e,
      );
    }
  }

  /// Sends a discovery broadcast on an already-open [socket].
  ///
  /// Returns false when the datagram could not be put on the wire. A
  /// point-to-point interface (a VPN tunnel, for instance) has no broadcast
  /// domain, and macOS reports that either by sending 0 bytes or by throwing.
  /// Callers get a value to check instead of an exception, because these sends
  /// also happen from retry timers where a throw would surface as an unhandled
  /// async error and take the process down.
  static bool sendBroadcast({
    required RawDatagramSocket socket,
    required String ip,
    required List<int> data,
    int port = wizPort,
  }) {
    WizLogger.info('Broadcasting to $ip:$port');
    try {
      var bytesSent = socket.send(data, InternetAddress(ip), port);
      if (bytesSent != data.length) {
        WizLogger.warn(
          'Broadcast to $ip:$port sent $bytesSent/${data.length} bytes',
        );
        return false;
      }
      WizLogger.debug('Sent $bytesSent bytes to $ip:$port');
      return true;
    } on SocketException catch (e) {
      WizLogger.warn(
        'Broadcast to $ip:$port failed: ${e.osError?.message ?? e.message}',
      );
      return false;
    }
  }
}
