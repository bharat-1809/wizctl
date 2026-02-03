import 'dart:io';

import '../config.dart';

/// Lists all groups.
Future<void> groupListCommand() async {
  final config = await CliConfig.load();

  if (config.groups.isEmpty) {
    stdout.writeln('No groups configured.');
    stdout.writeln('Use "wizctl group add <name> <lights...>" to create a group.');
    return;
  }

  stdout.writeln('Configured groups:\n');
  for (final entry in config.groups.entries) {
    stdout.writeln('  ${entry.key}:');
    for (final ip in entry.value) {
      final alias = config.getAlias(ip);
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

  final config = await CliConfig.load();

  // Resolve aliases to IPs
  final ips = <String>[];
  for (final light in lights) {
    final ip = config.resolveLight(light);
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
  final config = await CliConfig.load();

  if (!config.groups.containsKey(name)) {
    stderr.writeln('Error: Group "$name" not found.');
    exitCode = 1;
    return;
  }

  config.removeGroup(name);
  await config.save();
  stdout.writeln('Removed group "$name".');
}
