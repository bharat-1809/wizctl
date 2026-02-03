import 'dart:async';

import 'control_signal.dart';
import 'light.dart';
import 'scene.dart';
import 'state.dart';

/// Result of a group operation on one light.
class GroupOperationResult {
  final WizLight light;

  /// Whether the operation succeeded.
  final bool success;

  /// Error that occurred, if any.
  final Object? error;

  const GroupOperationResult(
      {required this.light, required this.success, this.error});

  @override
  String toString() =>
      'GroupOperationResult(${light.ip}: ${success ? 'success' : 'failed: $error'})';
}

/// Utility class for controlling multiple WiZ lights at once.
///
/// All operations are executed in parallel for fast group control.
/// Operations that fail on some lights don't prevent others from succeeding.
///
/// ```dart
/// final lights = [WizLight('192.168.1.100'), WizLight('192.168.1.101')];
///
/// // Turn all lights on
/// await WizGroup.turnOn(lights);
///
/// // Set the same color on all lights
/// await WizGroup.setColor(lights, 255, 100, 50);
///
/// // Get results to check for failures
/// final results = await WizGroup.setPilot(lights, Pilot(dimming: 50));
/// for (final result in results) {
///   if (!result.success) {
///     print('Failed: ${result.light.ip} - ${result.error}');
///   }
/// }
/// ```
class WizGroup {
  WizGroup._();

  static Future<List<GroupOperationResult>> send(
      List<WizLight> lights, ControlSignal signal) async {
    return _executeOnAll(lights, (light) => light.send(signal));
  }

  static Future<List<GroupOperationResult>> turnOn(List<WizLight> lights,
      {int? brightness}) async {
    return _executeOnAll(
        lights, (light) => light.turnOn(brightness: brightness));
  }

  static Future<List<GroupOperationResult>> turnOff(
      List<WizLight> lights) async {
    return _executeOnAll(lights, (light) => light.turnOff());
  }

  static Future<List<GroupOperationResult>> toggle(
      List<WizLight> lights) async {
    return _executeOnAll(lights, (light) => light.toggle());
  }

  static Future<List<GroupOperationResult>> setBrightness(
      List<WizLight> lights, int percent) async {
    return _executeOnAll(lights, (light) => light.setBrightness(percent));
  }

  static Future<List<GroupOperationResult>> setColor(
      List<WizLight> lights, int r, int g, int b,
      {int? brightness}) async {
    return _executeOnAll(
        lights, (light) => light.setColor(r, g, b, brightness: brightness));
  }

  static Future<List<GroupOperationResult>> setTemperature(
      List<WizLight> lights, int kelvin,
      {int? brightness}) async {
    return _executeOnAll(lights,
        (light) => light.setTemperature(kelvin, brightness: brightness));
  }

  static Future<List<GroupOperationResult>> setScene(
      List<WizLight> lights, WizScene scene,
      {int? brightness, int? speed}) async {
    return _executeOnAll(lights,
        (light) => light.setScene(scene, brightness: brightness, speed: speed));
  }

  static Future<List<GroupOperationResult>> setWarmWhite(
      List<WizLight> lights, int value,
      {int? brightness}) async {
    return _executeOnAll(
        lights, (light) => light.setWarmWhite(value, brightness: brightness));
  }

  static Future<List<GroupOperationResult>> setColdWhite(
      List<WizLight> lights, int value,
      {int? brightness}) async {
    return _executeOnAll(
        lights, (light) => light.setColdWhite(value, brightness: brightness));
  }

  static Future<List<GroupOperationResult>> setSpeed(
      List<WizLight> lights, int speed) async {
    return _executeOnAll(lights, (light) => light.setSpeed(speed));
  }

  static Future<Map<WizLight, LightState?>> getStates(
      List<WizLight> lights) async {
    var results = await Future.wait(
      lights.map((light) async {
        try {
          return (light, await light.getState());
        } catch (_) {
          return (light, null);
        }
      }),
    );
    return {for (final (light, state) in results) light: state};
  }

  /// Executes an operation on all lights in parallel.
  static Future<List<GroupOperationResult>> _executeOnAll(
    List<WizLight> lights,
    Future<void> Function(WizLight light) operation,
  ) async {
    return Future.wait(
      lights.map((light) async {
        try {
          await operation(light);
          return GroupOperationResult(light: light, success: true);
        } catch (e) {
          return GroupOperationResult(light: light, success: false, error: e);
        }
      }),
    );
  }
}
