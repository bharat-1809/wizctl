/// Retry strategy for network requests.
enum RetryStrategy {
  /// Fixed interval between retries (e.g., every 1 second).
  fixed,
  
  /// Exponential backoff - interval doubles after each retry, up to a maximum.
  exponential,
}

/// Configuration for retry behavior in network requests.
///
/// Controls how many times to retry requests and the timing strategy.
/// Use factory constructors for common configurations:
///
/// ```dart
/// // No retries (single attempt)
/// RetryConfig.none()
///
/// // Fixed interval (recommended for discovery)
/// RetryConfig.fixed(count: 5, interval: Duration(seconds: 1))
///
/// // Exponential backoff (recommended for point-to-point requests)
/// RetryConfig.exponential(
///   count: 5,
///   initialInterval: Duration(milliseconds: 750),
///   maxInterval: Duration(seconds: 3),
/// )
/// ```
class RetryConfig {
  /// Number of retry attempts. 0 means no retries (single attempt only).
  final int count;
  
  /// The retry strategy to use.
  final RetryStrategy strategy;
  
  /// Interval for fixed strategy, or initial interval for exponential strategy.
  final Duration interval;
  
  /// Maximum interval for exponential backoff (ignored for fixed strategy).
  final Duration? maxInterval;

  const RetryConfig({
    required this.count,
    required this.strategy,
    required this.interval,
    this.maxInterval,
  }) : assert(count >= 0, 'Retry count must be non-negative');

  /// No retries - single attempt only.
  const RetryConfig.none()
      : count = 0,
        strategy = RetryStrategy.fixed,
        interval = Duration.zero,
        maxInterval = null;

  /// Fixed interval retry strategy.
  ///
  /// Retries at regular intervals. Best for discovery where you want
  /// predictable timing and consistent network load.
  ///
  /// [count] - Number of retry attempts (total attempts = count + 1).
  /// [interval] - Time between each retry attempt.
  const RetryConfig.fixed({
    required int count,
    required Duration interval,
  })  : count = count,
        strategy = RetryStrategy.fixed,
        interval = interval,
        maxInterval = null;

  /// Exponential backoff retry strategy.
  ///
  /// Interval doubles after each retry, up to [maxInterval]. Reduces network
  /// load over time. Useful for point-to-point requests where you want to be
  /// aggressive initially but back off if no response is received.
  ///
  /// [count] - Number of retry attempts (total attempts = count + 1).
  /// [initialInterval] - Interval before the first retry.
  /// [maxInterval] - Maximum interval cap (defaults to 3 seconds).
  const RetryConfig.exponential({
    required int count,
    required Duration initialInterval,
    Duration? maxInterval,
  })  : count = count,
        strategy = RetryStrategy.exponential,
        interval = initialInterval,
        maxInterval = maxInterval ?? const Duration(seconds: 3);

  /// Whether retries are enabled (count > 0).
  bool get enabled => count > 0;

  /// Calculates the next interval for exponential backoff.
  ///
  /// Returns the current interval doubled, clamped to [maxInterval].
  Duration nextExponentialInterval(Duration currentInterval) {
    if (strategy != RetryStrategy.exponential) {
      return interval;
    }
    final maxMs = maxInterval?.inMilliseconds ?? double.maxFinite.toInt();
    return Duration(
      milliseconds: (currentInterval.inMilliseconds * 2).clamp(0, maxMs),
    );
  }
}
