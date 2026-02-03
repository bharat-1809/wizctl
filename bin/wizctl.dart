#!/usr/bin/env dart

// wizctl - Control WiZ smart lights from the command line.

import 'dart:io';

import 'package:args/args.dart';
import 'package:wizctl/wizctl.dart';

import 'cli/commands/alias.dart';
import 'cli/commands/control.dart';
import 'cli/commands/discover.dart';
import 'cli/commands/group.dart';
import 'cli/commands/status.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help message')
    ..addFlag('version', abbr: 'v', negatable: false, help: 'Show version')
    ..addFlag('debug', abbr: 'd', negatable: false, help: 'Enable debug logging')
    ..addFlag('verbose', negatable: false, help: 'Enable verbose logging');

  parser.addCommand('discover')
    .addOption('timeout', abbr: 't', defaultsTo: '$cliDefaultDiscoveryTimeoutSeconds', help: 'Discovery timeout in seconds');
  (parser.commands['discover'] as ArgParser).addFlag('save', abbr: 's', negatable: false, help: 'Save discovered lights to config');

  parser.addCommand('list');
  parser.addCommand('status');
  parser.addCommand('on').addOption('brightness', abbr: 'b', help: 'Brightness ($minBrightness-$maxBrightness)');
  parser.addCommand('off');
  parser.addCommand('toggle');
  parser.addCommand('brightness');
  parser.addCommand('color').addOption('brightness', abbr: 'b', help: 'Brightness ($minBrightness-$maxBrightness)');
  parser.addCommand('temp').addOption('brightness', abbr: 'b', help: 'Brightness ($minBrightness-$maxBrightness)');
  parser.addCommand('scene').addOption('brightness', abbr: 'b', help: 'Brightness ($minBrightness-$maxBrightness)');
  parser.addCommand('scenes');
  parser.addCommand('alias');

  final groupParser = parser.addCommand('group');
  groupParser.addCommand('list');
  groupParser.addCommand('add');
  groupParser.addCommand('remove');

  ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln('Run "$cliName --help" for usage.');
    exitCode = 1;
    return;
  }

  if (results['verbose'] as bool) {
    WizLogger.enable(WizLogLevel.verbose);
  } else if (results['debug'] as bool) {
    WizLogger.enable(WizLogLevel.debug);
  }

  if (results['help'] as bool) {
    printUsage();
    return;
  }

  if (results['version'] as bool) {
    stdout.writeln('$cliName $cliVersion');
    return;
  }

  if (results.command == null) {
    printUsage();
    return;
  }

  final command = results.command!;

  try {
    switch (command.name) {
      case 'discover':
        final timeout = int.tryParse(command['timeout'] as String) ?? cliDefaultDiscoveryTimeoutSeconds;
        await discoverCommand(timeout: timeout, save: command['save'] as bool);

      case 'list':
        await listCommand();

      case 'status':
        if (command.rest.isEmpty) {
          stderr.writeln('Usage: $cliName status <light>');
          exitCode = 1;
          return;
        }
        await statusCommand(command.rest.first);

      case 'on':
        if (command.rest.isEmpty) {
          stderr.writeln('Usage: $cliName on <light> [--brightness N]');
          exitCode = 1;
          return;
        }
        final brightness = command['brightness'] != null ? int.tryParse(command['brightness'] as String) : null;
        await onCommand(command.rest.first, brightness: brightness);

      case 'off':
        if (command.rest.isEmpty) {
          stderr.writeln('Usage: $cliName off <light>');
          exitCode = 1;
          return;
        }
        await offCommand(command.rest.first);

      case 'toggle':
        if (command.rest.isEmpty) {
          stderr.writeln('Usage: $cliName toggle <light>');
          exitCode = 1;
          return;
        }
        await toggleCommand(command.rest.first);

      case 'brightness':
        if (command.rest.length < 2) {
          stderr.writeln('Usage: $cliName brightness <light> <percent>');
          exitCode = 1;
          return;
        }
        final percent = int.tryParse(command.rest[1]);
        if (percent == null) {
          stderr.writeln('Error: Invalid brightness value.');
          exitCode = 1;
          return;
        }
        await brightnessCommand(command.rest.first, percent);

      case 'color':
        if (command.rest.length < 4) {
          stderr.writeln('Usage: $cliName color <light> <R> <G> <B> [--brightness N]');
          exitCode = 1;
          return;
        }
        final r = int.tryParse(command.rest[1]);
        final g = int.tryParse(command.rest[2]);
        final b = int.tryParse(command.rest[3]);
        if (r == null || g == null || b == null) {
          stderr.writeln('Error: Invalid RGB values.');
          exitCode = 1;
          return;
        }
        final brightness = command['brightness'] != null ? int.tryParse(command['brightness'] as String) : null;
        await colorCommand(command.rest.first, r, g, b, brightness: brightness);

      case 'temp':
        if (command.rest.length < 2) {
          stderr.writeln('Usage: $cliName temp <light> <kelvin> [--brightness N]');
          exitCode = 1;
          return;
        }
        final kelvin = int.tryParse(command.rest[1]);
        if (kelvin == null) {
          stderr.writeln('Error: Invalid temperature value.');
          exitCode = 1;
          return;
        }
        final brightness = command['brightness'] != null ? int.tryParse(command['brightness'] as String) : null;
        await tempCommand(command.rest.first, kelvin, brightness: brightness);

      case 'scene':
        if (command.rest.length < 2) {
          stderr.writeln('Usage: $cliName scene <light> <scene_name> [--brightness N]');
          exitCode = 1;
          return;
        }
        final brightness = command['brightness'] != null ? int.tryParse(command['brightness'] as String) : null;
        await sceneCommand(command.rest.first, command.rest[1], brightness: brightness);

      case 'scenes':
        scenesCommand();

      case 'alias':
        if (command.rest.length < 2) {
          stderr.writeln('Usage: $cliName alias <ip> "<name with spaces>"');
          exitCode = 1;
          return;
        }
        final aliasName = command.rest.skip(1).join(' ');
        await aliasCommand(command.rest[0], aliasName);

      case 'group':
        await handleGroupCommand(command);

      default:
        stderr.writeln('Unknown command: ${command.name}');
        printUsage();
        exitCode = 1;
    }
  } catch (e) {
    stderr.writeln('Error: $e');
    exitCode = 1;
  }
}

Future<void> handleGroupCommand(ArgResults command) async {
  if (command.command == null) {
    stderr.writeln('Usage: $cliName group <list|add|remove>');
    exitCode = 1;
    return;
  }

  switch (command.command!.name) {
    case 'list':
      await groupListCommand();

    case 'add':
      if (command.command!.rest.length < 2) {
        stderr.writeln('Usage: $cliName group add <name> <lights...>');
        exitCode = 1;
        return;
      }
      await groupAddCommand(command.command!.rest.first, command.command!.rest.skip(1).toList());

    case 'remove':
      if (command.command!.rest.isEmpty) {
        stderr.writeln('Usage: $cliName group remove <name>');
        exitCode = 1;
        return;
      }
      await groupRemoveCommand(command.command!.rest.first);

    default:
      stderr.writeln('Unknown group subcommand: ${command.command!.name}');
      exitCode = 1;
  }
}

void printUsage() {
  stdout.writeln('''
$cliName - Control WiZ smart lights

Usage: $cliName [options] <command> [arguments]

Options:
  --help, -h        Show help
  --version, -v     Show version
  --debug, -d       Show UDP packets
  --verbose         Maximum detail

Discovery:
  discover          Find lights on the network
    --timeout, -t   Timeout in seconds (default: $cliDefaultDiscoveryTimeoutSeconds)
    --save, -s      Save discovered lights
  list              Show configured lights
  status <light>    Get light state

Control:
  on <light>           Turn on
    --brightness, -b   Set brightness
  off <light>          Turn off
  toggle <light>       Toggle state
  brightness <light> N Set brightness ($minBrightness-$maxBrightness)
  color <light> R G B  Set RGB color ($minColorValue-$maxColorValue each)
  temp <light> K       Set temperature ($minTemperature-$maxTemperature)
  scene <light> NAME   Apply scene
  scenes               List available scenes

Config:
  alias <ip> <name>    Set alias for a light
  group list           List groups
  group add <n> <l..>  Create group
  group remove <name>  Remove group

Examples:
  $cliName discover --save
  $cliName alias 192.168.1.100 "Living Room"
  $cliName on "Living Room"
  $cliName color "Living Room" 255 100 50
  $cliName scene "Living Room" cozy
  $cliName group add all "Living Room" "Bedroom"
  $cliName on all
  $cliName --debug status 192.168.1.100
''');
}
