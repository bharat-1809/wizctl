import 'dart:io';

import 'package:wizctl/wizctl.dart';

import '../config.dart';

/// Gets the status of a light.
Future<void> statusCommand(String target) async {
  final config = await CliConfig.load();
  final ip = config.resolveLight(target);

  if (ip == null) {
    stderr.writeln('Error: Light "$target" not found.');
    stderr.writeln('Use an IP address or a configured alias.');
    exitCode = 1;
    return;
  }

  final light = WizLight(ip);

  try {
    final state = await light.getState();
    final alias = config.getAlias(ip);

    stdout.writeln('Light: $ip${alias != null ? ' ($alias)' : ''}');
    stdout.writeln('  State: ${state.isOn ? 'ON' : 'OFF'}');
    if (state.dimming != null) stdout.writeln('  Brightness: ${state.dimming}%');
    if (state.isRgbMode) stdout.writeln('  Color: RGB(${state.r}, ${state.g}, ${state.b})');
    if (state.temperature != null) stdout.writeln('  Temperature: ${state.temperature}K');
    if (state.scene != null) stdout.writeln('  Scene: ${state.scene!.displayName}');
    if (state.speed != null) stdout.writeln('  Speed: ${state.speed}');
    if (state.mac != null) stdout.writeln('  MAC: ${state.mac}');
  } on WizTimeoutError {
    stderr.writeln('Error: Light at $ip did not respond.');
    exitCode = 1;
  } on WizException catch (e) {
    stderr.writeln('Error: $e');
    exitCode = 1;
  }
}
