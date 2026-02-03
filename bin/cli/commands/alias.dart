import 'dart:io';

import '../config.dart';

Future<void> aliasCommand(String ip, String alias) async {
  final config = await CliConfig.load();
  config.setAlias(ip, alias);
  await config.save();
  stdout.writeln('Set alias "$alias" for $ip');
}

Future<void> listCommand() async {
  final config = await CliConfig.load();

  if (config.lights.isEmpty) {
    stdout.writeln('No lights configured.');
    stdout.writeln('Run "wizctl discover --save" to discover and save lights.');
    return;
  }

  stdout.writeln('Configured lights:\n');
  for (final entry in config.lights.entries) {
    final ip = entry.key;
    final alias = entry.value.alias;
    final mac = entry.value.mac;

    if (alias != null) {
      stdout.writeln('  $alias');
      stdout.writeln('    IP: $ip');
    } else {
      stdout.writeln('  $ip');
    }
    if (mac != null) stdout.writeln('    MAC: $mac');
    stdout.writeln();
  }
}
