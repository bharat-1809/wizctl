import 'state.dart';

/// What a streaming scan reports while it runs.
///
/// Consumers that only want the result can wait for [ScanDone]; a UI can show
/// [ScanProgress] as a determinate bar and list lights as [ScanFound] arrives.
sealed class ScanEvent {
  const ScanEvent();
}

/// A batch of probes has been sent.
final class ScanProgress extends ScanEvent {
  /// Distinct addresses probed at least once so far. Never decreases, so it
  /// can be shown as "n of 254 addresses" even though every address is probed
  /// more than once.
  final int addressesProbed;

  /// Number of addresses in this scan.
  final int addressCount;

  /// Overall completion in `[0, 1]`, counting every round.
  final double fraction;

  /// The `a.b.c` prefix being swept, or null when probing an address list.
  final String? subnet;

  const ScanProgress({
    required this.addressesProbed,
    required this.addressCount,
    required this.fraction,
    this.subnet,
  });

  @override
  String toString() =>
      'ScanProgress($addressesProbed/$addressCount, ${(fraction * 100).round()}%)';
}

/// A light answered for the first time.
final class ScanFound extends ScanEvent {
  final DiscoveredLight light;
  const ScanFound(this.light);
}

/// A light already reported by [ScanFound] answered again with more detail
/// (a `getSystemConfig` reply landing after a `getPilot` one).
final class ScanUpdated extends ScanEvent {
  final DiscoveredLight light;
  const ScanUpdated(this.light);
}

/// The scan finished; [lights] is the deduplicated result.
final class ScanDone extends ScanEvent {
  final List<DiscoveredLight> lights;
  const ScanDone(this.lights);
}
