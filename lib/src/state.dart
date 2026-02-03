import 'bulb_type.dart';
import 'constants.dart';
import 'scene.dart';

/// Current state of a WiZ light.
class LightState {
  final bool isOn;

  /// Current brightness level (10-100), or null if not set.
  final int? dimming;

  /// Red component of RGB color (0-255), or null if using scene/temperature.
  final int? r;

  /// Green component of RGB color (0-255), or null if using scene/temperature.
  final int? g;

  /// Blue component of RGB color (0-255), or null if using scene/temperature.
  final int? b;

  /// Cold white intensity (0-255), or null if not set.
  final int? coldWhite;

  /// Warm white intensity (0-255), or null if not set.
  final int? warmWhite;

  /// Color temperature in Kelvin (2200-6500), or null if using RGB/scene.
  final int? temperature;

  /// Active scene ID, or null if no scene is active.
  final int? sceneId;

  /// Effect speed (10-200) for dynamic scenes.
  final int? speed;

  /// Warm/cold white ratio (0-100).
  final int? ratio;

  /// MAC address of the light.
  final String? mac;

  /// Signal strength in dBm.
  final int? rssi;

  /// Source of the last change (e.g., "udp", "cloud").
  final String? source;

  /// The currently active scene, if any.
  WizScene? get scene => sceneId != null ? WizScene.fromId(sceneId!) : null;

  /// Alias for [dimming] for backwards compatibility.
  int? get brightness => dimming;

  /// Whether the light is currently displaying an RGB color.
  bool get isRgbMode => r != null && g != null && b != null;

  /// Whether the light is currently in color temperature mode.
  bool get isTemperatureMode => temperature != null && !isRgbMode;

  /// Whether a scene is currently active.
  bool get isSceneMode => sceneId != null && sceneId! > 0;

  /// Whether the light is using white LEDs directly.
  bool get isWhiteMode =>
      (coldWhite != null || warmWhite != null) &&
      !isRgbMode &&
      !isTemperatureMode;

  const LightState({
    required this.isOn,
    this.dimming,
    this.r,
    this.g,
    this.b,
    this.coldWhite,
    this.warmWhite,
    this.temperature,
    this.sceneId,
    this.speed,
    this.ratio,
    this.mac,
    this.rssi,
    this.source,
  });

  factory LightState.fromJson(Map<String, dynamic> json) {
    var result = json[keyResult] as Map<String, dynamic>? ?? json;
    return LightState(
      isOn: result[keyState] as bool? ?? false,
      dimming: result[keyDimming] as int?,
      r: result[keyRed] as int?,
      g: result[keyGreen] as int?,
      b: result[keyBlue] as int?,
      coldWhite: result[keyColdWhite] as int?,
      warmWhite: result[keyWarmWhite] as int?,
      temperature: result[keyTemperature] as int?,
      sceneId: result[keySceneId] as int?,
      speed: result[keySpeed] as int?,
      ratio: result[keyRatio] as int?,
      mac: result[keyMac] as String?,
      rssi: result[keyRssi] as int?,
      source: result[keySource] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        keyState: isOn,
        if (dimming != null) keyDimming: dimming,
        if (r != null) keyRed: r,
        if (g != null) keyGreen: g,
        if (b != null) keyBlue: b,
        if (coldWhite != null) keyColdWhite: coldWhite,
        if (warmWhite != null) keyWarmWhite: warmWhite,
        if (temperature != null) keyTemperature: temperature,
        if (sceneId != null) keySceneId: sceneId,
        if (speed != null) keySpeed: speed,
        if (ratio != null) keyRatio: ratio,
        if (mac != null) keyMac: mac,
        if (rssi != null) keyRssi: rssi,
        if (source != null) keySource: source,
      };

  @override
  String toString() {
    var parts = <String>['isOn: $isOn'];
    if (dimming != null) parts.add('dimming: $dimming%');
    if (isRgbMode) parts.add('rgb: ($r, $g, $b)');
    if (temperature != null) parts.add('temp: ${temperature}K');
    if (scene != null) parts.add('scene: ${scene!.displayName}');
    if (speed != null) parts.add('speed: $speed');
    if (mac != null) parts.add('mac: $mac');
    return 'LightState(${parts.join(', ')})';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LightState &&
          isOn == other.isOn &&
          dimming == other.dimming &&
          r == other.r &&
          g == other.g &&
          b == other.b &&
          temperature == other.temperature &&
          sceneId == other.sceneId &&
          speed == other.speed &&
          mac == other.mac;

  @override
  int get hashCode =>
      Object.hash(isOn, dimming, r, g, b, temperature, sceneId, speed, mac);
}

/// A WiZ light discovered on the network.
class DiscoveredLight {
  final String ip;
  final String mac;
  final String? moduleName;

  /// Firmware version, if available.
  final String? fwVersion;

  BulbClass? get bulbClass => BulbClass.fromModuleName(moduleName);

  /// Whether the light supports color (derived from bulb class).
  bool get supportsColor => bulbClass?.supportsColor ?? true;

  /// Whether the light supports color temperature (derived from bulb class).
  bool get supportsTemperature => bulbClass?.supportsTemperature ?? true;

  const DiscoveredLight({
    required this.ip,
    required this.mac,
    this.moduleName,
    this.fwVersion,
  });

  factory DiscoveredLight.fromJson(Map<String, dynamic> json, String ip) {
    var result = json[keyResult] as Map<String, dynamic>? ?? json;
    return DiscoveredLight(
      ip: ip,
      mac: result[keyMac] as String? ?? '',
      moduleName: result[keyModuleName] as String?,
      fwVersion: result[keyFwVersion] as String?,
    );
  }

  @override
  String toString() =>
      'DiscoveredLight(ip: $ip, mac: $mac${moduleName != null ? ', module: $moduleName' : ''})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredLight && ip == other.ip && mac == other.mac;

  @override
  int get hashCode => Object.hash(ip, mac);
}

/// System configuration of a WiZ bulb.
class BulbConfig {
  /// MAC address of the light.
  final String? mac;

  /// Module name/type of the light.
  final String? moduleName;

  /// Firmware version.
  final String? fwVersion;

  /// The bulb class determined from module name.
  final BulbClass? bulbClass;

  /// Supported Kelvin range for color temperature.
  final KelvinRange? kelvinRange;

  /// Home ID the bulb is registered to.
  final int? homeId;

  /// Room ID the bulb is registered to.
  final int? roomId;

  /// Whether the bulb supports color.
  bool get supportsColor => bulbClass?.supportsColor ?? true;

  /// Whether the bulb supports color temperature.
  bool get supportsTemperature => bulbClass?.supportsTemperature ?? true;

  /// Whether the bulb supports brightness.
  bool get supportsBrightness => bulbClass?.supportsBrightness ?? true;

  const BulbConfig({
    this.mac,
    this.moduleName,
    this.fwVersion,
    this.bulbClass,
    this.kelvinRange,
    this.homeId,
    this.roomId,
  });

  factory BulbConfig.fromJson(Map<String, dynamic> json) {
    var result = json[keyResult] as Map<String, dynamic>? ?? json;
    var moduleName = result[keyModuleName] as String?;

    KelvinRange? kelvinRange;
    if (result.containsKey(keyKelvinRange)) {
      kelvinRange = KelvinRange.fromJson(result[keyKelvinRange]);
    } else if (result.containsKey(keyExtRange)) {
      kelvinRange = KelvinRange.fromJson(result[keyExtRange]);
    } else if (result.containsKey(keyWhiteRange)) {
      kelvinRange = KelvinRange.fromJson(result[keyWhiteRange]);
    }

    return BulbConfig(
      mac: result[keyMac] as String?,
      moduleName: moduleName,
      fwVersion: result[keyFwVersion] as String?,
      bulbClass: BulbClass.fromModuleName(moduleName),
      kelvinRange: kelvinRange,
      homeId: result['homeId'] as int?,
      roomId: result['roomId'] as int?,
    );
  }

  @override
  String toString() {
    var parts = <String>[];
    if (mac != null) parts.add('mac: $mac');
    if (moduleName != null) parts.add('module: $moduleName');
    if (bulbClass != null) parts.add('type: ${bulbClass!.displayName}');
    if (kelvinRange != null) parts.add('kelvin: $kelvinRange');
    return 'BulbConfig(${parts.join(', ')})';
  }
}
