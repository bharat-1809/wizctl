# wizctl API Documentation

A Dart package for controlling Philips WiZ smart lights over UDP.

## Quick Start

```dart
import 'package:wizctl/wizctl.dart';

void main() async {
  // Discover lights on your network
  final lights = await WizDiscovery.discover();
  
  // Control a light
  final light = WizLight('192.168.1.100');
  await light.turnOn();
  await light.setColor(255, 100, 50);
  await light.setScene(WizScene.cozy);
  
  // Combined settings
  await light.send(ControlSignal(state: true, dimming: 80, r: 255, g: 100, b: 50));
}
```

---

## Discovery

### WizDiscovery

Find WiZ lights on your local network using UDP broadcast.

#### `discover()`

Discovers lights with configurable retry behavior. Uses exponential backoff by default for reliability.

**Parameters:**
- `broadcastAddress` - Broadcast address (default: `'255.255.255.255'`)
- `timeout` - **Total timeout window** for collecting responses (default: `Duration(seconds: 10)`)
- `retry` - Retry configuration (default: exponential backoff with 5 retries)
- `port` - UDP port (default: `38899`)

**Important:** Discovery uses a **total timeout** - all broadcasts happen within this window, and responses are collected continuously.

```dart
// Default discovery (exponential backoff)
final lights = await WizDiscovery.discover();

// Custom retry strategy
final lights = await WizDiscovery.discover(
  timeout: Duration(seconds: 10),
  retry: RetryConfig.fixed(
    count: 5,
    interval: Duration(seconds: 1),
  ),
);

// No retries (single broadcast)
final lights = await WizDiscovery.discover(
  retry: RetryConfig.none(),
);

for (final light in lights) {
  print('${light.ip} - ${light.mac}');
  if (light.bulbClass != null) {
    print('  Type: ${light.bulbClass!.displayName}');
  }
}
```

#### `discoverOnAllInterfaces()`

Discover on all network interfaces (useful for multi-homed systems).

```dart
final lights = await WizDiscovery.discoverOnAllInterfaces(
  timeout: Duration(seconds: 10),
  retry: RetryConfig.exponential(
    count: 5,
    initialInterval: Duration(milliseconds: 500),
  ),
);
```

### DiscoveredLight

Represents a discovered light.

| Property | Type | Description |
|----------|------|-------------|
| `ip` | `String` | IP address |
| `mac` | `String` | MAC address |
| `moduleName` | `String?` | Hardware module (e.g., "ESP01_SHRGB1C_31") |
| `fwVersion` | `String?` | Firmware version |
| `bulbClass` | `BulbClass?` | Detected bulb type |

---

## Light Control

### WizLight

Control a single WiZ light by IP address.

```dart
final light = WizLight(
  '192.168.1.100',
  port: 38899,                        // default
  timeout: Duration(seconds: 3),      // default (per-attempt timeout)
);
```

**Note:** The `timeout` parameter is a **per-attempt timeout** - each retry attempt gets its own full timeout duration. Total operation time = timeout × (attempts) + retry intervals.

#### Get State

```dart
final state = await light.getState();
print('On: ${state.isOn}');
print('Brightness: ${state.dimming}%');
print('Scene: ${state.scene?.displayName}');
print('Temperature: ${state.temperature}K');
print('RGB: (${state.r}, ${state.g}, ${state.b})');
print('Speed: ${state.speed}');
```

#### Get Bulb Configuration

```dart
final config = await light.getSystemConfig();
print('MAC: ${config.mac}');
print('Module: ${config.moduleName}');
print('Type: ${config.bulbClass?.displayName}');
print('Kelvin Range: ${config.kelvinRange}');

// Check capabilities
if (config.supportsColor) {
  await light.setColor(255, 0, 0);
}
```

#### Get Kelvin Range

```dart
final range = await light.getKelvinRange();
print('Supports ${range.min}K to ${range.max}K');
```

#### Basic Control

```dart
// Power
await light.turnOn();
await light.turnOn(brightness: 50);
await light.turnOff();
await light.toggle();

// Brightness (10-100)
await light.setBrightness(75);
```

#### Color Control

```dart
// RGB color (0-255 each)
await light.setColor(255, 100, 50);
await light.setColor(255, 100, 50, brightness: 80);

// Color temperature (1000-10000K, typical 2200-6500K)
await light.setTemperature(3000);
await light.setTemperature(4500, brightness: 60);

// Direct warm/cold white LED control (0-255)
await light.setWarmWhite(200);
await light.setColdWhite(150, brightness: 70);
await light.setWhite(warmWhite: 200, coldWhite: 100);
```

#### Scenes

```dart
// Apply a scene
await light.setScene(WizScene.cozy);
await light.setScene(WizScene.ocean, brightness: 80);

// Dynamic scenes support speed (10-200)
await light.setScene(WizScene.sunset, speed: 150);
```

#### Scene Speed

```dart
// Change speed of current dynamic scene
await light.setSpeed(150);
```

#### System Commands

```dart
// Reboot the bulb
await light.reboot();

// Factory reset (use with caution!)
await light.reset();

// Clear cached configuration
light.clearCache();
```

---

## Retry Configuration

### RetryConfig

Configurable retry behavior for network requests. Supports two strategies: fixed interval and exponential backoff.

#### Factory Constructors

```dart
// No retries (single attempt only)
RetryConfig.none()

// Fixed interval - retries at regular intervals
RetryConfig.fixed(
  count: 5,                    // Number of retries
  interval: Duration(seconds: 1), // Time between retries
)

// Exponential backoff - interval doubles after each retry
RetryConfig.exponential(
  count: 5,                              // Number of retries
  initialInterval: Duration(milliseconds: 500), // Starting interval
  maxInterval: Duration(seconds: 3),      // Maximum interval cap (default: 3s)
)
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `count` | `int` | Number of retry attempts (0 = disabled) |
| `strategy` | `RetryStrategy` | `fixed` or `exponential` |
| `interval` | `Duration` | Base/initial interval |
| `maxInterval` | `Duration?` | Maximum interval for exponential (ignored for fixed) |
| `enabled` | `bool` | Whether retries are enabled (count > 0) |

#### Methods

**`nextExponentialInterval(Duration currentInterval)`**

Calculates the next interval for exponential backoff. Doubles the current interval, clamped to `maxInterval`. Returns `interval` for fixed strategy.

#### RetryStrategy Enum

- `RetryStrategy.fixed` - Fixed interval between retries
- `RetryStrategy.exponential` - Exponential backoff (interval doubles)

#### Usage Examples

```dart
// Discovery with fixed intervals (predictable timing)
final lights = await WizDiscovery.discover(
  retry: RetryConfig.fixed(
    count: 5,
    interval: Duration(seconds: 1),
  ),
);

// Discovery with exponential backoff (default, reduces network load)
final lights = await WizDiscovery.discover(
  retry: RetryConfig.exponential(
    count: 5,
    initialInterval: Duration(milliseconds: 500),
    maxInterval: Duration(seconds: 3),
  ),
);

// Protocol requests also support retry config
// (defaults to exponential backoff matching old behavior)
```

---

## ControlSignal (Combined Settings)

Use `ControlSignal` to set multiple properties in a single command.

```dart
await light.send(ControlSignal(
  state: true,
  dimming: 80,
  r: 255,
  g: 100,
  b: 50,
));

await light.send(ControlSignal(
  sceneId: WizScene.ocean.id,
  speed: 120,
  dimming: 70,
));
```

### Factory Constructors

```dart
await light.send(ControlSignal.on());
await light.send(ControlSignal.off());
await light.send(ControlSignal.brightness(75));
await light.send(ControlSignal.rgb(255, 100, 50));
await light.send(ControlSignal.temperature(3000));
await light.send(ControlSignal.scene(WizScene.cozy, brightness: 80));
await light.send(ControlSignal.warmWhite(200));
await light.send(ControlSignal.coldWhite(150));
await light.send(ControlSignal.speed(120));
```

---

## Group Control

### WizGroup

Control multiple lights in parallel.

```dart
final lights = [
  WizLight('192.168.1.100'),
  WizLight('192.168.1.101'),
  WizLight('192.168.1.102'),
];

// Basic control
await WizGroup.turnOn(lights);
await WizGroup.turnOn(lights, brightness: 75);
await WizGroup.turnOff(lights);
await WizGroup.toggle(lights);

// Color
await WizGroup.setColor(lights, 255, 100, 50);
await WizGroup.setTemperature(lights, 3000);

// Scenes
await WizGroup.setScene(lights, WizScene.cozy);
await WizGroup.setScene(lights, WizScene.ocean, speed: 100);

// White
await WizGroup.setWarmWhite(lights, 200);
await WizGroup.setColdWhite(lights, 150);
await WizGroup.setSpeed(lights, 120);
```

### Handling Results

```dart
final results = await WizGroup.turnOn(lights);

for (final result in results) {
  if (result.success) {
    print('${result.light.ip}: OK');
  } else {
    print('${result.light.ip}: Failed - ${result.error}');
  }
}
```

### Get States from All Lights

```dart
final states = await WizGroup.getStates(lights);

for (final entry in states.entries) {
  final light = entry.key;
  final state = entry.value;
  
  if (state != null) {
    print('${light.ip}: ${state.isOn ? 'ON' : 'OFF'}');
  } else {
    print('${light.ip}: No response');
  }
}
```

---

## Scenes

### WizScene

36 built-in scenes (35 standard + rhythm).

```dart
// List all scenes
for (final scene in WizScene.values) {
  print('${scene.name}: ${scene.displayName} (ID: ${scene.id})');
}

// Find by name
final scene = WizScene.fromName('cozy');
final scene2 = WizScene.fromName('Warm White'); // display name works too

// Find by ID
final scene3 = WizScene.fromId(6); // WizScene.cozy

// Check if dynamic (supports speed)
if (scene.isDynamic) {
  await light.setScene(scene, speed: 150);
}
```

### Available Scenes

| Name | ID | Dynamic |
|------|-----|---------|
| ocean | 1 | ✓ |
| romance | 2 | ✓ |
| sunset | 3 | ✓ |
| party | 4 | ✓ |
| fireplace | 5 | ✓ |
| cozy | 6 | |
| forest | 7 | ✓ |
| pastelColors | 8 | ✓ |
| wakeUp | 9 | ✓ |
| bedtime | 10 | ✓ |
| warmWhite | 11 | |
| daylight | 12 | |
| coolWhite | 13 | |
| nightLight | 14 | |
| focus | 15 | |
| relax | 16 | |
| trueColors | 17 | |
| tvTime | 18 | |
| plantGrowth | 19 | |
| spring | 20 | ✓ |
| summer | 21 | ✓ |
| fall | 22 | ✓ |
| deepDive | 23 | ✓ |
| jungle | 24 | ✓ |
| mojito | 25 | ✓ |
| club | 26 | ✓ |
| christmas | 27 | ✓ |
| halloween | 28 | ✓ |
| candlelight | 29 | ✓ |
| goldenWhite | 30 | |
| pulse | 31 | ✓ |
| steampunk | 32 | |
| diwali | 33 | ✓ |
| white | 34 | |
| alarm | 35 | ✓ |
| rhythm | 1000 | ✓ |

---

## Bulb Types

### BulbClass

Bulb capabilities detected from module name.

```dart
final config = await light.getSystemConfig();
final bulbClass = config.bulbClass;

print('Type: ${bulbClass?.displayName}');
print('Supports color: ${bulbClass?.supportsColor}');
print('Supports temperature: ${bulbClass?.supportsTemperature}');
print('Supports brightness: ${bulbClass?.supportsBrightness}');
```

| Type | Color | Temperature | Brightness |
|------|-------|-------------|------------|
| RGB | ✓ | ✓ | ✓ |
| Tunable White (TW) | | ✓ | ✓ |
| Dimmable White (DW) | | | ✓ |
| Socket | | | |
| Fan Dimmer | | | ✓ |

### KelvinRange

```dart
final range = await light.getKelvinRange();
print('${range.min}K to ${range.max}K');

// Check if a temperature is supported
if (range.contains(3000)) {
  await light.setTemperature(3000);
}

// Clamp to valid range
final validTemp = range.clamp(1500); // Returns 2200 if min is 2200
```

---

## Logging

### WizLogger

Enable logging to see UDP packets for debugging.

```dart
// Debug level - shows request/response
WizLogger.enable(WizLogLevel.debug);

// Verbose level - shows everything
WizLogger.enable(WizLogLevel.verbose);

// Custom callback
WizLogger.enable(WizLogLevel.debug, callback: (level, message) {
  myLogger.log(message);
});

// Disable
WizLogger.disable();
```

### Log Levels

| Level | Description |
|-------|-------------|
| `none` | No logging (default) |
| `error` | Errors only |
| `warn` | Warnings and errors |
| `info` | Request/response summaries |
| `debug` | Full packet contents |
| `verbose` | Everything including socket details |

---

## Error Handling

### Exception Types

All exceptions extend `WizException`:

```dart
try {
  await light.turnOn();
} on WizTimeoutError catch (e) {
  // Light didn't respond after all retries
  // timeout is per-attempt timeout, retryCount is total attempts made
  print('Timeout: ${e.ip}');
  print('Per-attempt timeout: ${e.timeout}');
  print('Total attempts: ${e.retryCount}');
} on WizConnectionError catch (e) {
  // Network/socket error
  print('Connection failed: ${e.message}');
  print('Cause: ${e.cause}');
} on WizResponseError catch (e) {
  // Invalid response from light
  print('Bad response: ${e.message}');
  print('Raw: ${e.rawResponse}');
  print('Error code: ${e.errorCode}');
} on WizMethodNotFoundError catch (e) {
  // Method not supported by firmware
  print('${e.method} not supported by ${e.ip}');
} on WizArgumentError catch (e) {
  // Invalid parameter
  print('Invalid ${e.argumentName}: ${e.invalidValue}');
  print(e.message);
} on WizUnknownBulbError catch (e) {
  // Can't detect bulb type
  print('Unknown bulb at ${e.ip}');
}
```

---

## Constants

### Network

| Constant | Value | Description |
|----------|-------|-------------|
| `wizPort` | 38899 | UDP port for WiZ communication |
| `defaultTimeout` | 3 seconds | **Per-attempt** timeout for protocol requests |
| `defaultDiscoveryTimeout` | 10 seconds | **Total** timeout window for discovery |

**Important:** 
- `defaultTimeout` is per-attempt - each retry gets its own full timeout
- `defaultDiscoveryTimeout` is total - all broadcasts happen within this window

### Validation Limits

| Constant | Value |
|----------|-------|
| `minBrightness` | 10 |
| `maxBrightness` | 100 |
| `minColorValue` | 0 |
| `maxColorValue` | 255 |
| `minTemperature` | 1000 |
| `maxTemperature` | 10000 |
| `minSpeed` | 10 |
| `maxSpeed` | 200 |

---

## Protocol Details

wizctl uses UDP communication on port 38899. Messages are JSON-encoded.

### Communication Protocol

**Protocol Requests (`WizProtocol.send`):**
- Uses **per-attempt timeout** - each retry attempt gets its own full timeout duration
- Default: 3 seconds per attempt
- Default retry: Exponential backoff with 5 retries (750ms initial, 3s max)
- Total operation time = timeout × (attempts) + retry intervals
- Maximum total time: ~18 seconds (3s × 6 attempts + retry intervals)

**Discovery (`WizDiscovery.discover`):**
- Uses **total timeout** - single timeout window for collecting all responses
- Default: 10 seconds total window
- Default retry: Exponential backoff with 5 retries (500ms initial, 3s max)
- All broadcasts (initial + retries) happen within the timeout window
- Responses are collected continuously throughout the period

### Retry Behavior

**Default Configuration:**
- **Protocol requests**: Exponential backoff, 5 retries, 750ms initial, 3s max
- **Discovery**: Exponential backoff, 5 retries, 500ms initial, 3s max

**Retry Strategies:**

1. **Fixed Interval** - Regular intervals (e.g., every 1 second)
   - Best for: Discovery where you want predictable timing
   - Example: `RetryConfig.fixed(count: 5, interval: Duration(seconds: 1))`

2. **Exponential Backoff** - Interval doubles after each retry
   - Best for: Point-to-point requests, reduces network load over time
   - Example: `RetryConfig.exponential(count: 5, initialInterval: Duration(milliseconds: 500))`
   - Intervals: 500ms → 1s → 2s → 3s → 3s (capped)

**Why Different Timeout Strategies?**

- **Per-attempt for protocol**: Each request should have a fair chance to receive a response. If one attempt times out, the next gets a fresh timeout.
- **Total for discovery**: Discovery collects responses from multiple devices over time. We want a fixed window to gather all responses, not per-device timeouts.

### Example Messages

**Get State:**
```json
{"method":"getPilot","params":{}}
```

**Response:**
```json
{
  "method":"getPilot",
  "result":{
    "state":true,
    "dimming":75,
    "sceneId":6,
    "mac":"abc123"
  }
}
```

**Set Color:**
```json
{"method":"setPilot","params":{"r":255,"g":100,"b":50,"dimming":80}}
```

---

## CLI Usage

Install globally:

```bash
dart pub global activate wizctl
```

Commands:

```bash
# Discovery
wizctl discover --save
wizctl list

# Control (use -t/--target to specify light, alias, or group)
wizctl on -t "Living Room"
wizctl off -t "Living Room"
wizctl toggle -t "Living Room"
wizctl brightness -t "Living Room" -b 75
wizctl color -t "Living Room" -c 255,100,50
wizctl temp -t "Living Room" -k 3000
wizctl scene -t "Living Room" -s cozy

# Aliases (use --ip and -n/--name flags)
wizctl alias --ip 192.168.1.100 -n "Living Room"

# Groups
wizctl group add -n "Living Room" -l "LL-Lamp,LL-1,LL-2"
wizctl group remove -n all
wizctl off -t all

# Config management
wizctl config path              # Show config file location
wizctl config clear             # Delete all config (with confirmation)
wizctl config clear --force     # Delete all config (no confirmation)

# Debug
wizctl --debug status -t 192.168.1.100
```

### CLI Flags Reference

| Flag | Abbr | Used In | Description |
|------|------|---------|-------------|
| `--target` | `-t` | Control commands | Light, alias, or group to control |
| `--brightness` | `-b` | on, color, temp, scene, brightness | Brightness value (10-100) |
| `--rgb` | `-c` | color | RGB color as R,G,B (e.g., 255,100,50) |
| `--kelvin` | `-k` | temp | Temperature in Kelvin (1000-10000) |
| `--scene` | `-s` | scene | Scene name |
| `--ip` | | alias | IP address of the light |
| `--name` | `-n` | alias, group add, group remove | Alias or group name |
| `--lights` | `-l` | group add | Comma-separated list of lights |
| `--force` | `-f` | config clear | Skip confirmation prompt |

### Config Commands

| Command | Description |
|---------|-------------|
| `config path` | Show the location of the config file |
| `config clear` | Delete all saved lights, aliases, and groups (prompts for confirmation) |
| `config clear --force` | Delete all config without confirmation |