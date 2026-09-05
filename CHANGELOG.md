## 1.0.0

Initial release.

### Features

- **Discovery** - find lights by UDP broadcast, by sweeping a subnet one
  address at a time, or by asking known addresses directly.
- **Control** - on/off, brightness, RGB colour, colour temperature, and all 36
  built-in scenes with speed control.
- **Groups** - drive several lights in parallel.
- **Bulb type detection** - RGB, tunable white, dimmable, socket and fan, from
  the reported module name.
- **CLI** - `wizctl` with aliases, groups and saved configuration.
- **Retries** - configurable fixed or exponential backoff for both discovery
  and individual requests.

### Discovery notes

Broadcast discovery does not work on every network. Some access points filter
broadcast towards wireless clients, and Wi-Fi power save on the bulb means
broadcast frames only arrive on the access point's DTIM schedule — on such a
network no broadcast-based tool can find the lights, even though they answer a
direct request instantly.

`wizctl discover` therefore tries several things in order: the lights already
in your configuration, then a broadcast, then a unicast sweep of the subnet.
`--scan` goes straight to the sweep. See "When discovery finds nothing" in the
README.

A sweep is deliberately batched across several sockets. Probing hundreds of
empty addresses provokes socket failures and fills the kernel's ARP queue,
which can otherwise leave a sweep reporting nothing at all on a network where
every light is reachable.
