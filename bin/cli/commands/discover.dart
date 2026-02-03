import 'dart:io';

import 'package:wizctl/wizctl.dart';

import '../config.dart';

Future<void> discoverCommand({int timeout = 5, bool save = false}) async {
  stdout.writeln('Discovering WiZ lights...');

  var lights = await WizDiscovery.discover(timeout: Duration(seconds: timeout));

  if (lights.isEmpty) {
    stdout.writeln('No lights found.');
    return;
  }

  stdout.writeln('Found ${lights.length} light(s):\n');

  for (var light in lights) {
    stdout.writeln('  ${light.ip}');
    stdout.writeln('    MAC: ${light.mac}');
    if (light.moduleName != null) {
      stdout.writeln('    Module: ${light.moduleName}');
    }
    if (light.bulbClass != null) {
      stdout.writeln('    Type: ${light.bulbClass!.displayName}');
    }
    stdout.writeln();
  }

  if (save) {
    var config = await CliConfig.load();
    for (var light in lights) {
      config.lights.putIfAbsent(light.ip, () => LightConfig(mac: light.mac));
    }
    await config.save();
    stdout.writeln('Saved ${lights.length} light(s) to config.');
  }
}
