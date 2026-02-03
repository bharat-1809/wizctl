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
    final retryConfig = retry ?? RetryConfig.exponential(
      count: maxSendDatagrams - 1, // -1 because first attempt is not a retry
      initialInterval: firstSendInterval,
      maxInterval: maxBackoff,
    );
    RawDatagramSocket? socket;
    final method = message[keyMethod] as String? ?? 'unknown';
    final messageJson = jsonEncode(message);

    WizLogger.info('Sending $method to $ip:$port');
    WizLogger.debug('Request: $messageJson');

    try {
      // Bind to any available port
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      WizLogger.verbose('Bound to local port ${socket.port}');

      final data = utf8.encode(messageJson);
      final address = InternetAddress(ip);
      final completer = Completer<Map<String, dynamic>>();
      var attemptNumber = 0;
      var currentRetryInterval = retryConfig.interval;
      Timer? attemptTimeoutTimer;

      final subscription = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket!.receive();
          if (datagram != null) {
            final responseText = utf8.decode(datagram.data);
            WizLogger.debug('Received from ${datagram.address.address}: $responseText');

            try {
              final response = jsonDecode(responseText) as Map<String, dynamic>;

              if (response.containsKey(keyError)) {
                final error = response[keyError] as Map<String, dynamic>;
                final code = error[keyCode] as int?;
                final errorMsg = error['message'] as String? ?? 'Unknown error';

                WizLogger.error('Error response: code=$code, message=$errorMsg');

                if (code == errorCodeMethodNotFound) {
                  if (!completer.isCompleted) {
                    completer.completeError(WizMethodNotFoundError(method: method, ip: ip));
                  }
                  return;
                }

                if (!completer.isCompleted) {
                  completer.completeError(WizResponseError(
                    'Error from light: $errorMsg',
                    errorCode: code,
                    rawResponse: responseText,
                  ));
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
                completer.completeError(WizResponseError(
                  'Failed to parse response from $ip',
                  rawResponse: responseText,
                  cause: e,
                ));
              }
            }
          }
        }
      });

      Future<void> sendWithRetry() async {
        // Always make at least one attempt
        final maxAttempts = retryConfig.count + 1;
        
        while (!completer.isCompleted && attemptNumber < maxAttempts) {
          attemptNumber++;
          final bytesSent = socket!.send(data, address, port);
          WizLogger.debug('Attempt $attemptNumber/$maxAttempts: sent $bytesSent bytes');

          if (bytesSent != data.length) {
            WizLogger.error('Incomplete send: $bytesSent/${data.length} bytes');
            if (!completer.isCompleted) {
              completer.completeError(WizConnectionError('Failed to send to $ip:$port'));
            }
            return;
          }

          // Set up per-attempt timeout
          attemptTimeoutTimer?.cancel();
          var attemptTimedOut = false;
          
          attemptTimeoutTimer = Timer(timeout, () {
            if (!completer.isCompleted) {
              WizLogger.debug('Attempt $attemptNumber timed out after ${timeout.inSeconds}s');
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
            WizLogger.verbose('Waiting ${currentRetryInterval.inMilliseconds}ms before retry');
            await Future.delayed(currentRetryInterval);
            
            // Calculate next interval based on strategy
            if (retryConfig.strategy == RetryStrategy.exponential) {
              currentRetryInterval = retryConfig.nextExponentialInterval(currentRetryInterval);
            }
            // For fixed strategy, currentRetryInterval stays the same
          } else if (attemptTimedOut) {
            // No more retries, fail with timeout
            WizLogger.error('Timeout after $attemptNumber attempts to $ip');
            if (!completer.isCompleted) {
              completer.completeError(WizTimeoutError(ip: ip, timeout: timeout, retryCount: attemptNumber));
            }
            break;
          }
        }
        
        // Ensure completer is always completed (safety check)
        if (!completer.isCompleted) {
          WizLogger.error('Timeout after $attemptNumber attempts to $ip');
          completer.completeError(WizTimeoutError(ip: ip, timeout: timeout, retryCount: attemptNumber));
        }
      }

      await sendWithRetry();
      // At this point, sendWithRetry has completed, so completer should be completed
      // (either with a response or an error, due to the safety check in sendWithRetry)
      
      try {
        // Use a timeout as a safety measure to ensure we always return
        final maxWait = Duration(seconds: 1);
        final result = await completer.future.timeout(
          maxWait,
          onTimeout: () {
            // This should never happen, but ensure we always return
            if (!completer.isCompleted) {
              completer.completeError(WizTimeoutError(ip: ip, timeout: timeout, retryCount: attemptNumber));
            }
            throw WizTimeoutError(ip: ip, timeout: timeout, retryCount: attemptNumber);
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

  /// Sends a broadcast message for discovery.
  ///
  /// Returns the socket for receiving responses. Caller is responsible for closing it.
  static Future<RawDatagramSocket> sendBroadcast({
    required String ip,
    required Map<String, dynamic> message,
    int port = wizPort,
  }) async {
    final messageJson = jsonEncode(message);
    WizLogger.info('Broadcasting to $ip:$port');
    WizLogger.debug('Broadcast: $messageJson');

    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      WizLogger.verbose('Broadcast socket on port ${socket.port}');

      final data = utf8.encode(messageJson);
      final bytesSent = socket.send(data, InternetAddress(ip), port);
      WizLogger.debug('Sent $bytesSent bytes');

      return socket;
    } on SocketException catch (e) {
      WizLogger.error('Broadcast failed: $e');
      throw WizConnectionError('Broadcast to $ip:$port failed', e);
    }
  }

  /// Collects multiple responses from a socket within a timeout period.
  ///
  /// Used for discovery where multiple lights may respond.
  static Future<List<(Map<String, dynamic>, InternetAddress)>> collectResponses({
    required RawDatagramSocket socket,
    required Duration timeout,
  }) async {
    WizLogger.info('Collecting responses for ${timeout.inSeconds}s...');

    final responses = <(Map<String, dynamic>, InternetAddress)>[];
    final completer = Completer<void>();

    final subscription = socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram != null) {
          final responseText = utf8.decode(datagram.data);
          WizLogger.debug('Response from ${datagram.address.address}: $responseText');

          try {
            final response = jsonDecode(responseText) as Map<String, dynamic>;
            responses.add((response, datagram.address));
            WizLogger.verbose('Total responses: ${responses.length}');
          } catch (e) {
            WizLogger.warn('Failed to parse response: $e');
          }
        }
      }
    });

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        WizLogger.info('Discovery complete: ${responses.length} response(s)');
        completer.complete();
      }
    });

    await completer.future;
    timer.cancel();
    await subscription.cancel();

    return responses;
  }
}

void unawaited(Future<void> future) {}
