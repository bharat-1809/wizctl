import 'constants.dart';
import 'exceptions.dart';
import 'scene.dart';

/// Build a control signal with multiple settings.
///
/// ```dart
/// await light.send(ControlSignal(state: true, dimming: 80, r: 255, g: 100, b: 50));
/// ```
class ControlSignal {
  final bool? state;
  final int? dimming;
  final int? r;
  final int? g;
  final int? b;
  final int? coldWhite;
  final int? warmWhite;
  final int? temperature;
  final int? sceneId;
  final int? speed;
  final int? ratio;

  int? get brightness => dimming;

  ControlSignal({
    this.state,
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
  }) {
    _validate();
  }

  ControlSignal.on() : this(state: true);
  ControlSignal.off() : this(state: false);
  ControlSignal.brightness(int percent) : this(dimming: percent);
  ControlSignal.rgb(int r, int g, int b, {int? brightness})
    : this(r: r, g: g, b: b, dimming: brightness);
  ControlSignal.temperature(int kelvin, {int? brightness})
    : this(temperature: kelvin, dimming: brightness);
  ControlSignal.scene(WizScene scene, {int? brightness, int? speed})
    : this(sceneId: scene.id, dimming: brightness, speed: speed);
  ControlSignal.warmWhite(int value, {int? brightness})
    : this(warmWhite: value, dimming: brightness);
  ControlSignal.coldWhite(int value, {int? brightness})
    : this(coldWhite: value, dimming: brightness);
  ControlSignal.speed(int value) : this(speed: value);

  void _validate() {
    if (dimming != null &&
        (dimming! < minBrightness || dimming! > maxBrightness)) {
      throw WizArgumentError(
        argumentName: 'dimming',
        invalidValue: dimming,
        message: errorBrightnessRange,
      );
    }
    if (r != null && (r! < minColorValue || r! > maxColorValue)) {
      throw WizArgumentError(
        argumentName: 'r',
        invalidValue: r,
        message: errorRedRange,
      );
    }
    if (g != null && (g! < minColorValue || g! > maxColorValue)) {
      throw WizArgumentError(
        argumentName: 'g',
        invalidValue: g,
        message: errorGreenRange,
      );
    }
    if (b != null && (b! < minColorValue || b! > maxColorValue)) {
      throw WizArgumentError(
        argumentName: 'b',
        invalidValue: b,
        message: errorBlueRange,
      );
    }
    if (coldWhite != null &&
        (coldWhite! < minColorValue || coldWhite! > maxColorValue)) {
      throw WizArgumentError(
        argumentName: 'coldWhite',
        invalidValue: coldWhite,
        message: errorWhiteRange,
      );
    }
    if (warmWhite != null &&
        (warmWhite! < minColorValue || warmWhite! > maxColorValue)) {
      throw WizArgumentError(
        argumentName: 'warmWhite',
        invalidValue: warmWhite,
        message: errorWhiteRange,
      );
    }
    if (temperature != null &&
        (temperature! < minTemperature || temperature! > maxTemperature)) {
      throw WizArgumentError(
        argumentName: 'temperature',
        invalidValue: temperature,
        message: errorTemperatureRange,
      );
    }
    if (sceneId != null &&
        sceneId != rhythmSceneId &&
        (sceneId! < minSceneId || sceneId! > maxSceneId)) {
      throw WizArgumentError(
        argumentName: 'sceneId',
        invalidValue: sceneId,
        message: errorSceneIdRange,
      );
    }
    if (speed != null && (speed! < minSpeed || speed! > maxSpeed)) {
      throw WizArgumentError(
        argumentName: 'speed',
        invalidValue: speed,
        message: errorSpeedRange,
      );
    }
  }

  Map<String, dynamic> toJson() {
    var params = <String, dynamic>{};
    if (state != null) params[keyState] = state;
    if (dimming != null) params[keyDimming] = dimming;
    if (r != null) params[keyRed] = r;
    if (g != null) params[keyGreen] = g;
    if (b != null) params[keyBlue] = b;
    if (coldWhite != null) params[keyColdWhite] = coldWhite;
    if (warmWhite != null) params[keyWarmWhite] = warmWhite;
    if (temperature != null) params[keyTemperature] = temperature;
    if (sceneId != null) params[keySceneId] = sceneId;
    if (speed != null) params[keySpeed] = speed;
    if (ratio != null) params[keyRatio] = ratio;
    return params;
  }

  Map<String, dynamic> toMessage() => {
    keyMethod: methodSetPilot,
    keyParams: toJson(),
  };

  @override
  String toString() {
    var parts = <String>[];
    if (state != null) parts.add('state: $state');
    if (dimming != null) parts.add('dimming: $dimming%');
    if (r != null && g != null && b != null) parts.add('rgb: ($r, $g, $b)');
    if (warmWhite != null) parts.add('warmWhite: $warmWhite');
    if (coldWhite != null) parts.add('coldWhite: $coldWhite');
    if (temperature != null) parts.add('temp: ${temperature}K');
    if (sceneId != null) parts.add('sceneId: $sceneId');
    if (speed != null) parts.add('speed: $speed');
    return 'ControlSignal(${parts.join(', ')})';
  }
}
