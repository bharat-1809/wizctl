import 'bulb_type.dart';
import 'constants.dart';
import 'control_signal.dart';
import 'exceptions.dart';
import 'protocol.dart';
import 'scene.dart';
import 'state.dart';

/// Control a WiZ light by IP address.
///
/// ```dart
/// final light = WizLight('192.168.1.100');
/// await light.turnOn();
/// await light.setColor(255, 100, 50);
/// await light.setScene(WizScene.cozy);
/// ```
class WizLight {
  final String ip;

  /// The UDP port to communicate on (default: 38899).
  final int port;

  /// Timeout for UDP operations.
  final Duration timeout;

  /// Cached bulb configuration.
  BulbConfig? _cachedConfig;

  /// Creates a new [WizLight] instance.
  ///
  /// [ip] - The IP address of the WiZ light.
  /// [port] - The UDP port (defaults to [wizPort]).
  /// [timeout] - Timeout for operations (defaults to [defaultTimeout]).
  WizLight(
    this.ip, {
    this.port = wizPort,
    this.timeout = defaultTimeout,
  });

  // ===========================================================================
  // State Methods
  // ===========================================================================

  /// Gets the current state of the light.
  ///
  /// Returns a [LightState] containing the light's current settings.
  ///
  /// Throws:
  /// - [WizTimeoutError] if the light doesn't respond.
  /// - [WizConnectionError] if there's a network error.
  Future<LightState> getState() async {
    final response = await WizProtocol.send(
      ip: ip,
      message: {keyMethod: methodGetPilot, keyParams: {}},
      port: port,
      timeout: timeout,
    );
    return LightState.fromJson(response);
  }

  /// Gets the system configuration of the light.
  ///
  /// Returns a [BulbConfig] containing MAC, module name, firmware version, etc.
  /// The result is cached for subsequent calls.
  ///
  /// Throws:
  /// - [WizTimeoutError] if the light doesn't respond.
  /// - [WizConnectionError] if there's a network error.
  Future<BulbConfig> getSystemConfig() async {
    if (_cachedConfig != null) return _cachedConfig!;
    final response = await WizProtocol.send(
      ip: ip,
      message: {keyMethod: methodGetSystemConfig, keyParams: {}},
      port: port,
      timeout: timeout,
    );
    _cachedConfig = BulbConfig.fromJson(response);
    return _cachedConfig!;
  }

  /// Gets the bulb configuration, fetching it if not cached.
  ///
  /// Alias for [getSystemConfig] for backwards compatibility.
  Future<BulbConfig> getBulbConfig() => getSystemConfig();

  /// Gets the supported Kelvin range for this bulb.
  ///
  /// Tries to get from model config first (FW >1.22), falls back to defaults.
  Future<KelvinRange> getKelvinRange() async {
    try {
      final response = await WizProtocol.send(
        ip: ip,
        message: {keyMethod: methodGetModelConfig, keyParams: {}},
        port: port,
        timeout: timeout,
      );
      final result = response[keyResult] as Map<String, dynamic>? ?? response;
      if (result.containsKey(keyKelvinRange)) {
        return KelvinRange.fromJson(result[keyKelvinRange]);
      }
    } on WizMethodNotFoundError {
      // Older firmware doesn't support this
    }
    return KelvinRange.standard;
  }

  void clearCache() => _cachedConfig = null;

  // ===========================================================================
  // Control Methods
  // ===========================================================================

  Future<void> send(ControlSignal signal) async {
    await WizProtocol.send(ip: ip, message: signal.toMessage(), port: port, timeout: timeout);
  }

  /// Turns the light on.
  ///
  /// Optionally set [brightness] at the same time (10-100).
  Future<void> turnOn({int? brightness}) async {
    await send(ControlSignal(state: true, dimming: brightness));
  }

  Future<void> turnOff() async {
    await send(ControlSignal(state: false));
  }

  /// Toggles the light on or off.
  ///
  /// Gets the current state and sets it to the opposite.
  Future<void> toggle() async {
    final state = await getState();
    state.isOn ? await turnOff() : await turnOn();
  }

  /// Sets the brightness level.
  ///
  /// [percent] - Brightness level from 10 to 100.
  ///
  /// Note: WiZ lights have a minimum brightness of 10%.
  ///
  /// Throws [WizArgumentError] if [percent] is out of range.
  Future<void> setBrightness(int percent) async {
    if (percent < minBrightness || percent > maxBrightness) {
      throw WizArgumentError(argumentName: 'percent', invalidValue: percent, message: errorBrightnessRange);
    }
    await send(ControlSignal(dimming: percent));
  }

  /// Sets an RGB color.
  ///
  /// [r], [g], [b] - Color components from 0 to 255.
  /// [brightness] - Optional brightness level (10-100).
  ///
  /// Throws [WizArgumentError] if any value is out of range.
  Future<void> setColor(int r, int g, int b, {int? brightness}) async {
    await send(ControlSignal(r: r, g: g, b: b, dimming: brightness));
  }

  /// Sets the color temperature.
  ///
  /// [kelvin] - Color temperature in Kelvin (2200-6500).
  /// [brightness] - Optional brightness level (10-100).
  ///
  /// Throws [WizArgumentError] if [kelvin] is out of range.
  Future<void> setTemperature(int kelvin, {int? brightness}) async {
    if (kelvin < minTemperature || kelvin > maxTemperature) {
      throw WizArgumentError(argumentName: 'kelvin', invalidValue: kelvin, message: errorTemperatureRange);
    }
    await send(ControlSignal(temperature: kelvin, dimming: brightness));
  }

  /// Applies a built-in scene.
  ///
  /// [scene] - The scene to apply.
  /// [brightness] - Optional brightness level (10-100).
  /// [speed] - Optional effect speed (10-200) for dynamic scenes.
  Future<void> setScene(WizScene scene, {int? brightness, int? speed}) async {
    await send(ControlSignal(sceneId: scene.id, dimming: brightness, speed: speed));
  }

  /// Sets the warm white LED intensity.
  ///
  /// [value] - Warm white intensity from 0 to 255.
  /// [brightness] - Optional brightness level (10-100).
  Future<void> setWarmWhite(int value, {int? brightness}) async {
    if (value < minColorValue || value > maxColorValue) {
      throw WizArgumentError(argumentName: 'value', invalidValue: value, message: errorWhiteRange);
    }
    await send(ControlSignal(warmWhite: value, dimming: brightness));
  }

  /// Sets the cold white LED intensity.
  ///
  /// [value] - Cold white intensity from 0 to 255.
  /// [brightness] - Optional brightness level (10-100).
  Future<void> setColdWhite(int value, {int? brightness}) async {
    if (value < minColorValue || value > maxColorValue) {
      throw WizArgumentError(argumentName: 'value', invalidValue: value, message: errorWhiteRange);
    }
    await send(ControlSignal(coldWhite: value, dimming: brightness));
  }

  /// Sets white light with cold/warm balance.
  ///
  /// [coldWhite] - Cold white intensity (0-255).
  /// [warmWhite] - Warm white intensity (0-255).
  /// [brightness] - Optional brightness level (10-100).
  Future<void> setWhite({int? coldWhite, int? warmWhite, int? brightness}) async {
    await send(ControlSignal(coldWhite: coldWhite, warmWhite: warmWhite, dimming: brightness));
  }

  /// Sets the effect speed for dynamic scenes.
  ///
  /// [speed] - Effect speed from 10 (slow) to 200 (fast).
  ///
  /// Throws [WizArgumentError] if [speed] is out of range.
  Future<void> setSpeed(int speed) async {
    if (speed < minSpeed || speed > maxSpeed) {
      throw WizArgumentError(argumentName: 'speed', invalidValue: speed, message: errorSpeedRange);
    }
    await send(ControlSignal(speed: speed));
  }

  // ===========================================================================
  // System Methods
  // ===========================================================================

  /// Reboots the light.
  ///
  /// The light will restart and reconnect to the network.
  Future<void> reboot() async {
    await WizProtocol.send(ip: ip, message: {keyMethod: methodReboot, keyParams: {}}, port: port, timeout: timeout);
  }

  /// Resets the light to factory settings.
  ///
  /// WARNING: This will remove all configuration including WiFi settings.
  /// The light will need to be set up again.
  Future<void> reset() async {
    await WizProtocol.send(ip: ip, message: {keyMethod: methodReset, keyParams: {}}, port: port, timeout: timeout);
  }

  @override
  String toString() => 'WizLight($ip)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is WizLight && ip == other.ip && port == other.port;

  @override
  int get hashCode => Object.hash(ip, port);
}
