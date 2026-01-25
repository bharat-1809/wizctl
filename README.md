# wizctl

[![Pub Version](https://img.shields.io/pub/v/wizctl?color=blue)](https://pub.dev/packages/wizctl)
[![Dart SDK](https://img.shields.io/badge/Dart-%3E%3D3.9.2-blue?logo=dart)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)

Control your Philips WiZ smart lights via CLI or an App.

## Why?

The official Philips app is laggy and is available only for mobile. This package enables controlling wiz devices from all supported platforms (MacOS, Windows, Linux, iOS, Android) via CLI or an app.

## Features

- **Discovery** - Find lights on your network via UDP broadcast
- **Control** - On/off, brightness, RGB color, color temperature, scenes
- **Groups** - Control multiple lights in parallel
- **36 Scenes** - All built-in WiZ scenes with speed control
- **Bulb Type Detection** - Auto-detect RGB, Tunable White, Dimmable, Socket, Fan

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  wizctl: ^1.0.0
```

Or install via command line:

```bash
dart pub add wizctl
```

## Quick Start

```dart
import 'package:wizctl/wizctl.dart';

void main() async {
  // Discover lights
  final lights = await WizDiscovery.discover();
  print('Found ${lights.length} lights');

  // Control a light
  final light = WizLight('192.168.1.100');
  await light.turnOn();
  await light.setBrightness(75);
  await light.setColor(255, 100, 50);
  await light.setScene(WizScene.cozy);
  
  // Get state
  final state = await light.getState();
  print('Brightness: ${state.dimming}%');
}
```

## Control Examples

```dart
// Basic
await light.turnOn();
await light.turnOff();
await light.setBrightness(75);

// Color
await light.setColor(255, 100, 50);
await light.setTemperature(3000);

// Scenes with speed
await light.setScene(WizScene.ocean, speed: 150);

// Combined settings
await light.send(
  ControlSignal(
    state: true, // Light state: on/off
    dimming: 80,
    r: 255,
    g: 100,
    b: 50,
  ),
);
```


## Group Control

```dart
final lights = [
  WizLight('192.168.1.100'),
  WizLight('192.168.1.101'),
];

await WizGroup.turnOn(lights);
await WizGroup.setScene(lights, WizScene.cozy);
await WizGroup.setColor(lights, 255, 100, 50);
```

## Bulb Type Detection

```dart
final config = await light.getSystemConfig();
print('Type: ${config.bulbClass?.displayName}'); // "RGB", "Tunable White", etc.

if (config.supportsColor) {
  await light.setColor(255, 0, 0);
}
```

## Retry Configuration

For unreliable networks, you can customize retry behavior:

```dart
// Discovery with custom retry strategy
final lights = await WizDiscovery.discover(
  timeout: Duration(seconds: 10),
  retry: RetryConfig.fixed(
    count: 5,
    interval: Duration(seconds: 1),
  ),
);

// Or use exponential backoff (default)
final lights = await WizDiscovery.discover(
  retry: RetryConfig.exponential(
    count: 5,
    initialInterval: Duration(milliseconds: 500),
    maxInterval: Duration(seconds: 3),
  ),
);

// Protocol requests also support retry config
// (uses exponential backoff by default)
```

## Debugging

```dart
// Enable logging to see UDP packets
WizLogger.enable(WizLogLevel.debug);
await light.turnOn(); // Now shows packets
```

## CLI

```bash
# Install
dart pub global activate wizctl

# Help
wizctl --help

# Discover and save lights
wizctl discover --save

# Set alias (use flags for names with spaces)
wizctl alias --ip 192.168.1.100 -n "Living Room"

# Control (use -t/--target to specify light)
wizctl on -t "Living Room"
wizctl brightness -t "Living Room" -b 75
wizctl color -t "Living Room" -c 255,100,50
wizctl temp -t Kitchen -k 4000
wizctl scene -t "Living Room" -s cozy

# Groups
wizctl group add -n all -l "Living Room,Bedroom"
wizctl off -t all

# Debug mode
wizctl --debug status -t 192.168.1.100
```

### CLI Commands

| Command | Description |
|---------|-------------|
| `discover` | Find lights on the network |
| `list` | List configured lights |
| `status -t <light>` | Get current state |
| `on -t <light>` | Turn on |
| `off -t <light>` | Turn off |
| `toggle -t <light>` | Toggle on/off |
| `brightness -t <light> -b <N>` | Set brightness (10-100) |
| `color -t <light> -c <R,G,B>` | Set RGB color |
| `temp -t <light> -k <K>` | Set temperature (1000-10000) |
| `scene -t <light> -s <name>` | Apply a scene |
| `scenes` | List available scenes |
| `alias --ip <ip> -n <name>` | Set alias for a light |
| `group list` | List groups |
| `group add -n <name> -l <lights>` | Create a group (comma-separated lights) |
| `group remove -n <name>` | Remove a group |
| `config path` | Show config file location |
| `config clear` | Delete all saved config |

## Scenes

Scenes can be dynamic or static. Dynamic scenes support speed control.

| Scene | ID | Dynamic (speed) |
|-------|----|-----------------|
| Ocean | 1 | Yes |
| Romance | 2 | Yes |
| Sunset | 3 | Yes |
| Party | 4 | Yes |
| Fireplace | 5 | Yes |
| Cozy | 6 | No |
| Forest | 7 | Yes |
| Pastel Colors | 8 | Yes |
| Wake Up | 9 | Yes |
| Bedtime | 10 | Yes |
| Warm White | 11 | No |
| Daylight | 12 | No |
| Cool White | 13 | No |
| Night Light | 14 | No |
| Focus | 15 | No |
| Relax | 16 | No |
| True Colors | 17 | No |
| TV Time | 18 | No |
| Plant Growth | 19 | No |
| Spring | 20 | Yes |
| Summer | 21 | Yes |
| Fall | 22 | Yes |
| Deep Dive | 23 | Yes |
| Jungle | 24 | Yes |
| Mojito | 25 | Yes |
| Club | 26 | Yes |
| Christmas | 27 | Yes |
| Halloween | 28 | Yes |
| Candlelight | 29 | Yes |
| Golden White | 30 | No |
| Pulse | 31 | Yes |
| Steampunk | 32 | No |
| Diwali | 33 | Yes |
| White | 34 | No |
| Alarm | 35 | Yes |
| Rhythm | 1000 | Yes |

CLI: `wizctl scenes` | Dart: `WizScene.values`

## Inspiration

This is inspired by [pywizlight](https://github.com/sbidy/pywizlight) by [sbidy](https://github.com/sbidy)

## License

MIT
