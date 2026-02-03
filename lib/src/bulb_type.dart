/// Classification of WiZ bulb types based on their capabilities.
///
/// Module name format: `ESP01_SHDW1C_31`
/// - `ESP01` - Module family
/// - `SH/DH` - Single/Dual head
/// - `RGB/TW/DW` - Color capability
/// - `SOCKET` - Smart socket
/// - `FANDIM` - Fan with dimmable light
enum BulbClass {
  /// Full RGB + tunable white (supports color, temperature, scenes).
  rgb('RGB',
      supportsColor: true, supportsTemperature: true, supportsBrightness: true),

  /// Tunable white only (supports temperature, brightness only).
  tw('Tunable White',
      supportsColor: false,
      supportsTemperature: true,
      supportsBrightness: true),

  /// Dimmable white only (brightness only, fixed temperature).
  dw('Dimmable White',
      supportsColor: false,
      supportsTemperature: false,
      supportsBrightness: true),

  /// Smart socket (on/off only, no dimming).
  socket('Socket',
      supportsColor: false,
      supportsTemperature: false,
      supportsBrightness: false),

  /// Fan with dimmable light.
  fanDim('Fan Dimmer',
      supportsColor: false,
      supportsTemperature: false,
      supportsBrightness: true);

  /// Human-readable name for the bulb class.
  final String displayName;

  /// Whether this bulb type supports RGB color.
  final bool supportsColor;

  /// Whether this bulb type supports color temperature.
  final bool supportsTemperature;

  /// Whether this bulb type supports brightness/dimming.
  final bool supportsBrightness;

  const BulbClass(
    this.displayName, {
    required this.supportsColor,
    required this.supportsTemperature,
    required this.supportsBrightness,
  });

  /// Parses the bulb class from a module name.
  ///
  /// Module name format examples:
  /// - `ESP01_SHRGB1C_31` - RGB bulb
  /// - `ESP01_SHTW1C_31` - Tunable white
  /// - `ESP01_SHDW1C_31` - Dimmable white
  /// - `ESP03_SOCKET_01` - Smart socket
  /// - `ESP14_FANDIM_01` - Fan dimmer
  ///
  /// Returns `null` if the module name cannot be parsed.
  static BulbClass? fromModuleName(String? moduleName) {
    if (moduleName == null || moduleName.isEmpty) return null;
    var upper = moduleName.toUpperCase();

    if (upper.contains('SOCKET')) return socket;
    if (upper.contains('FANDIM')) return fanDim;
    if (upper.contains('RGB')) return rgb;
    if (upper.contains('TW')) return tw;
    if (upper.contains('DW')) return dw;
    return null;
  }

  @override
  String toString() => displayName;
}

/// Color temperature range supported by a bulb.
class KelvinRange {
  final int min;
  final int max;

  const KelvinRange({required this.min, required this.max});

  static const standard = KelvinRange(min: 2200, max: 6500);

  /// Extended Kelvin range for some newer bulbs.
  static const extended = KelvinRange(min: 1000, max: 10000);

  factory KelvinRange.fromJson(dynamic json) {
    if (json is Map<String, dynamic>) {
      return KelvinRange(
        min: json['min'] as int? ?? 2200,
        max: json['max'] as int? ?? 6500,
      );
    }
    if (json is List && json.length >= 2) {
      return KelvinRange(
          min: json[0] as int? ?? 2200, max: json[1] as int? ?? 6500);
    }
    return KelvinRange.standard;
  }

  bool contains(int kelvin) => kelvin >= min && kelvin <= max;
  int clamp(int kelvin) => kelvin.clamp(min, max);

  @override
  String toString() => 'KelvinRange($min-$max K)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KelvinRange && min == other.min && max == other.max;

  @override
  int get hashCode => Object.hash(min, max);
}
