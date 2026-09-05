## Unreleased

### Fixed

- **Intermittent `SocketException` crashes.** `RawDatagramSocket.send` does not
  throw when the OS rejects a datagram: it returns 0 and delivers the
  `SocketException` asynchronously on the socket's own stream. None of the
  socket listeners had an `onError` handler, so every such error became an
  unhandled async error that terminated the process. Probing an address with
  nothing behind it produces exactly this ("No route to host", "Host is down"),
  so a subnet scan generated hundreds of them and crashed reliably, while a
  request to a sleeping bulb crashed with a stack trace instead of reporting
  the problem. All listeners now handle it.
- A request to an unreachable light now fails with `WizConnectionError: Cannot
  reach <ip>` naming the underlying socket error, rather than a bare timeout.
- A short send (0 bytes written, typically an unresolved ARP entry for a bulb
  that is asleep) aborted the request outright. It is now treated as a failed
  attempt and retried, which is usually enough for the next attempt to succeed.
- Discovery found no lights when the bulb's firmware addresses its registration
  reply to the WiZ port (38899) on the sender's IP rather than to the source
  port of the request. The discovery socket bound an ephemeral port, so those
  replies were delivered to nobody. It now binds the WiZ port, which works with
  both firmware behaviours, and falls back to an ephemeral port if the port is
  already in use.
- `discoverOnAllInterfaces` ignored the interfaces it enumerated and just ran
  the same default-route discovery N times. It now binds each interface's
  address so the broadcast actually leaves that interface, and skips interfaces
  that cannot broadcast (VPN tunnels) instead of crashing.
- Discovery sent its first broadcast before the response listener was attached,
  and then sent it a second time, doubling every request.
- A failed broadcast inside a retry timer surfaced as an unhandled async
  exception and killed the process.

### Added

- **Known lights are asked directly first.** `WizDiscovery.probeAddresses`
  queries a specific list of addresses, and `discover` uses it for the lights
  already in your config before considering a sweep. This is both quicker and
  far more reliable — a sweep provokes failures against every empty address,
  which can take the socket down mid-sweep and make it report nothing at all
  on a network where every light answers a direct request.
- Subnet sweeps now go out in batches, on one socket per chunk of addresses, so
  a socket lost part-way through costs one chunk instead of the whole scan.
- Sweeps probe with `getPilot` as well as `getSystemConfig`. Not every firmware
  implements the latter, and `getPilot` also carries the MAC, so an older bulb
  is found with less detail rather than not at all.
- `discover --save` matches lights by MAC, so a light that changes address
  keeps its alias instead of being saved again under the new IP.
- A sweep that comes back empty falls back to asking the known lights before
  reporting failure.
- **Unicast subnet scanning.** On some networks lights never answer the
  discovery broadcast even though they reply to unicast immediately — access
  points filter broadcast to wireless clients, and Wi-Fi power save on the bulb
  means broadcast frames only arrive on the access point's DTIM schedule. No
  broadcast-based discovery can find those lights. `WizDiscovery.scanSubnet`
  probes each address on the subnet with `getSystemConfig` instead, and
  `discover` falls back to it automatically when broadcasting turns up
  nothing.
- `discover --scan` to skip broadcasting and go straight to the subnet scan,
  and `--subnet 192.168.1` to scan a subnet other than this machine's.
- `discover --broadcast <address>` to search a specific subnet.
- `WizDiscovery.discover` accepts `localPort` and `bindAddress`.
- `discover` now falls back to per-interface discovery and prints the local
  addresses it searched, plus what to check, when nothing is found.

## 1.0.0

- Initial release
