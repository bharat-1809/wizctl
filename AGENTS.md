# AGENTS.md

Guidance for coding agents working on `wizctl`. Humans are welcome to read it
too — most of it is the kind of thing you only learn by losing an afternoon to
it.

## What this package is

A Dart library and CLI for Philips WiZ lights. WiZ devices speak a JSON-over-UDP
protocol on port **38899**. There is no cloud in this package: everything is
local network traffic.

- `lib/src/protocol.dart` — the UDP transport (`WizProtocol.send`, sockets, retries)
- `lib/src/discovery.dart` — finding lights (`discover`, `scanSubnet`, `probeAddresses`)
- `lib/src/light.dart`, `group.dart` — the device API
- `bin/wizctl.dart`, `bin/cli/` — the CLI
- `lib/wizctl.dart` — the public export surface. `WizProtocol` is **not** exported;
  it is free to change.

## Commands

```bash
dart pub get
dart analyze --fatal-infos lib bin test example   # exactly what CI runs
dart format --output=none --set-exit-if-changed lib bin test example
dart test                              # ~60s, all of it should pass
dart pub publish --dry-run             # before any release
```

CI runs exactly these on every push and pull request.

## The rule that matters most: never trust a network for a test

Every test in `test/` runs offline. Do not write a test that expects a real
light, a real broadcast, or a reachable LAN — it will pass on your machine and
fail everywhere else, and it will pass for reasons you have not verified.

`test/discovery_test.dart` has a `FakeBulb` harness. Use it.

- It binds loopback and answers `registration`, `getSystemConfig` and `getPilot`.
- `ReplyMode.sourcePort` vs `ReplyMode.fixedPort` models the two firmware
  behaviours — some bulbs reply to the datagram's source port, some to the WiZ
  port on the sender's IP. Discovery has to work with both.
- `supportedMethods` models older firmware that does not implement every method.

To test error paths deterministically without a network: **a socket bound to
loopback cannot reach a routable address**. Sending from `127.0.0.1` to, say,
`10.99.99.1` reliably produces a socket failure. That is how the asynchronous
socket error tests work.

**Socket semantics differ between macOS and Linux, and CI runs Linux.** Binding
a UDP port that another socket already holds fails on macOS but succeeds on
Linux, because Dart binds with `SO_REUSEADDR`. A test that depends on such a
difference should *detect* the behaviour at runtime and `markTestSkipped` when
the platform cannot provide it — never assume, and never assert the behaviour
of the machine you happen to be on. Run the CI commands locally before pushing,
but treat a green local run on macOS as necessary rather than sufficient.

## Things about UDP in Dart that will bite you

These are load-bearing. Changing the code without knowing them reintroduces
bugs that were expensive to find.

1. **`RawDatagramSocket.send` does not throw when the OS rejects a datagram.**
   It returns `0` and delivers the `SocketException` *asynchronously on the
   socket's own stream*. A `try/catch` around `send` is close to dead code.
   Every `socket.listen(...)` therefore **must** pass `onError`, or the error
   becomes an unhandled async error that kills the process. Measured during one
   subnet sweep: 0 synchronous throws, 241 asynchronous errors.

2. **Completing a `Completer` with an error before anything awaits it** is
   reported as an unhandled async error. `WizProtocol.send` attaches a
   `catchError` to the completer's future immediately to avoid this.

3. **A short send is not fatal.** `bytesSent != data.length` usually means an
   unresolved ARP entry for a bulb that is asleep. Retry it; the next attempt
   normally succeeds. Do not turn it into an error.

4. **Bind the WiZ port, not an ephemeral one.** Firmware that addresses its
   reply to port 38899 on the sender's IP is invisible to a socket on an
   ephemeral port. `openBroadcastSocket` binds 38899 and falls back to an
   ephemeral port if it is taken. Do not add `reusePort` — sharing the port
   makes the bind succeed while unicast replies get delivered to whichever
   socket the kernel picks, which loses lights at random and silently.

5. **Sweeping a subnet is not free.** Probing ~250 empty addresses provokes
   socket failures that can take the socket down mid-sweep, after which it
   delivers no replies at all, and it fills the kernel's ARP table with
   incomplete entries that persist for `net.link.ether.inet.max_age`
   (20 minutes on macOS). One greedy sweep can make the next several return
   nothing on a network where every light is reachable. This is why sweeps are
   batched across one socket per chunk, and why known addresses are probed
   directly first.

## Testing against real hardware

Optional, and never in the automated suite. If you do have lights:

```bash
dart run bin/wizctl.dart --verbose discover --scan
dart run bin/wizctl.dart status -t <ip>
```

Two warnings from experience:

- **WiZ bulbs do not answer ICMP.** A ping sweep, and any "live host" list built
  from one, excludes them by construction. Probe UDP 38899 directly instead.
- **Broadcast discovery genuinely does not work on some networks.** If
  `discover` finds nothing, check unicast to a known bulb IP before concluding
  the code is wrong. `pywizlight` is a useful independent reference: if it finds
  nothing either, the problem is not this package.
- The IP shown in the WiZ app can be stale, because the app controls lights
  through Philips' cloud. It keeps working when the bulb is unreachable locally.

## Conventions

- Match the surrounding style; comments explain *why*, not *what*.
- Public API needs dartdoc. `constants.dart` holds tuning values, each with a
  comment explaining the number.
- Update `CHANGELOG.md` under the version being developed.
- `cliVersion` in `lib/src/constants.dart` must match `pubspec.yaml`.
  `test/version_test.dart` enforces this — it has drifted before.

## Releasing

1. `dart analyze`, `dart format`, `dart test` all clean.
2. Bump `version` in `pubspec.yaml` and `cliVersion` in `lib/src/constants.dart`.
3. Add the matching `CHANGELOG.md` heading.
4. `dart pub publish --dry-run` — expect 0 warnings.
5. `dart pub publish`.
