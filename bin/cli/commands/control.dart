import 'dart:io';

import 'package:wizctl/wizctl.dart';

import '../config.dart';

/// Resolves a target to a list of WizLight objects.
Future<List<WizLight>?> resolveLights(String target) async {
  final config = await CliConfig.load();

  // Check if it's a group
  final groupIps = config.resolveGroup(target);
  if (groupIps != null) return groupIps.map((ip) => WizLight(ip)).toList();

  // Try to resolve as a single light
  final ip = config.resolveLight(target);
  if (ip == null) {
    stderr.writeln('Error: Light or group "$target" not found.');
    stderr.writeln('Use an IP address, alias, or group name.');
    return null;
  }

  return [WizLight(ip)];
}

/// Executes an operation on lights and handles errors.
Future<void> executeOnLights(
  String target,
  String actionName,
  Future<void> Function(WizLight light) action,
) async {
  final lights = await resolveLights(target);
  if (lights == null) {
    exitCode = 1;
    return;
  }

  final results = await Future.wait(
    lights.map((light) async {
      try {
        await action(light);
        return (light, true, null);
      } catch (e) {
        return (light, false, e);
      }
    }),
  );

  var hasError = false;
  for (final (light, success, error) in results) {
    if (success) {
      stdout.writeln('$actionName: ${light.ip}');
    } else {
      stderr.writeln('Error ($actionName ${light.ip}): $error');
      hasError = true;
    }
  }

  if (hasError) exitCode = 1;
}

/// Turns a light on.
Future<void> onCommand(String target, {int? brightness}) async {
  await executeOnLights(target, 'Turned on', (light) => light.turnOn(brightness: brightness));
}

/// Turns a light off.
Future<void> offCommand(String target) async {
  await executeOnLights(target, 'Turned off', (light) => light.turnOff());
}

/// Toggles a light.
Future<void> toggleCommand(String target) async {
  await executeOnLights(target, 'Toggled', (light) => light.toggle());
}

/// Sets brightness.
Future<void> brightnessCommand(String target, int percent) async {
  if (percent < minBrightness || percent > maxBrightness) {
    stderr.writeln('Error: $errorBrightnessRange');
    exitCode = 1;
    return;
  }
  await executeOnLights(target, 'Brightness set to $percent%', (light) => light.setBrightness(percent));
}

/// Sets RGB color.
Future<void> colorCommand(String target, int r, int g, int b, {int? brightness}) async {
  if (r < minColorValue || r > maxColorValue ||
      g < minColorValue || g > maxColorValue ||
      b < minColorValue || b > maxColorValue) {
    stderr.writeln('Error: RGB values must be between $minColorValue and $maxColorValue.');
    exitCode = 1;
    return;
  }
  await executeOnLights(target, 'Color set to RGB($r, $g, $b)', (light) => light.setColor(r, g, b, brightness: brightness));
}

/// Sets color temperature.
Future<void> tempCommand(String target, int kelvin, {int? brightness}) async {
  if (kelvin < minTemperature || kelvin > maxTemperature) {
    stderr.writeln('Error: $errorTemperatureRange');
    exitCode = 1;
    return;
  }
  await executeOnLights(target, 'Temperature set to ${kelvin}K', (light) => light.setTemperature(kelvin, brightness: brightness));
}

/// Applies a scene.
Future<void> sceneCommand(String target, String sceneName, {int? brightness}) async {
  final scene = WizScene.fromName(sceneName);
  if (scene == null) {
    stderr.writeln('Error: Unknown scene "$sceneName".');
    stderr.writeln('Use "$cliName scenes" to list available scenes.');
    exitCode = 1;
    return;
  }
  await executeOnLights(target, 'Scene set to ${scene.displayName}', (light) => light.setScene(scene, brightness: brightness));
}

/// Lists available scenes.
void scenesCommand() {
  stdout.writeln('Available scenes:\n');
  for (final scene in WizScene.values) {
    stdout.writeln('  ${scene.name.padRight(15)} (${scene.displayName})');
  }
}
