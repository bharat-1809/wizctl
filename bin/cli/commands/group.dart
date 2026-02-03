import 'dart:io';

import '../config.dart';

/// Lists all groups.
Future<void> groupListCommand() async {
  var config = await CliConfig.load();

  if (config.groups.isEmpty) {
    stdout.writeln('No groups configured.');
    stdout.writeln(
      'Use "wizctl group add -n <name> -l <lights>" to create a group.',
    );
    return;
  }

  stdout.writeln('Configured groups:\n');
  for (var entry in config.groups.entries) {
    stdout.writeln('  ${entry.key}:');
    for (var ip in entry.value) {
      var alias = config.getAlias(ip);
      if (alias != null) {
        stdout.writeln('    - $alias ($ip)');
      } else {
        stdout.writeln('    - $ip');
      }
    }
    stdout.writeln();
  }
}

/// Adds a new group.
Future<void> groupAddCommand(String name, List<String> lights) async {
  if (lights.isEmpty) {
    stderr.writeln('Error: At least one light is required.');
    exitCode = 1;
    return;
  }

  var config = await CliConfig.load();

  // Resolve aliases to IPs
  var ips = <String>[];
  for (var light in lights) {
    var ip = config.resolveLight(light);
    if (ip == null) {
      stderr.writeln('Error: Light "$light" not found.');
      exitCode = 1;
      return;
    }
    ips.add(ip);
  }

  config.addGroup(name, ips);
  await config.save();
  stdout.writeln('Created group "$name" with ${ips.length} light(s).');
}

/// Removes a group.
Future<void> groupRemoveCommand(String name) async {
  var config = await CliConfig.load();

  if (!config.groups.containsKey(name)) {
    stderr.writeln('Error: Group "$name" not found.');
    exitCode = 1;
    return;
  }

  config.removeGroup(name);
  await config.save();
  stdout.writeln('Removed group "$name".');
}
