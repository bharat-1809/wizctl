## 1.1.0

- `WizDiscovery.scanSubnetStream` and `WizDiscovery.probeAddressesStream` report
  progress and lights as they answer (`ScanProgress`, `ScanFound`, `ScanUpdated`,
  `ScanDone`); cancelling the subscription stops the scan. `scanSubnet` and
  `probeAddresses` are unchanged and now built on them.
- `ControlSignal.fromState` builds the signal that restores a captured
  `LightState`, for blink-to-identify.
- `WizLight` accepts a `retry` configuration used by every request it sends.

## 1.0.0

- Initial release
