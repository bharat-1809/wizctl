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
import 'cli/config.dart';

/// Adds --target option to a command parser and returns it for chaining.
ArgParser addTargetOption(ArgParser parser) {
  return parser
    ..addOption('target', abbr: 't', help: 'Light, alias, or group name');
}

/// Gets the target value, joining with rest arguments if the shell split a quoted name.
///
/// When a user types: wizctl on -t "Living Room"
/// Some shells may split this into: [on, -t, Living, Room]
/// This function rejoins them: "Living Room"
///
/// [restOffset] specifies how many rest arguments belong to other parameters
/// (e.g., for `color` command, restOffset=0 since RGB is now a flag)
String? getTarget(ArgResults command, {int restOffset = 0}) {
  var target = command['target'] as String?;
  if (target == null) return null;

  // If there are extra rest arguments beyond what's expected, they're likely
  // part of a space-separated target name that the shell split
  var extraArgs = command.rest.length - restOffset;
  if (extraArgs > 0) {
    var parts = [target, ...command.rest.take(extraArgs)];
    return parts.join(' ');
  }
  return target;
}

/// Validates that --target was provided, prints error if not.
/// Returns the target value (joined with rest args if needed) or null if missing.
String? requireTarget(ArgResults command, String usage, {int restOffset = 0}) {
  var target = getTarget(command, restOffset: restOffset);
  if (target == null) {
    stderr.writeln('Error: --target is required.');
    stderr.writeln('Usage: $usage');
    exitCode = 1;
  }
  return target;
}

/// Gets an option value, joining with rest arguments if the shell split a quoted name.
/// Similar to getTarget but for any named option.
String? getOptionWithRest(
  ArgResults command,
  String optionName, {
  int restOffset = 0,
}) {
  var value = command[optionName] as String?;
  if (value == null) return null;

  var extraArgs = command.rest.length - restOffset;
  if (extraArgs > 0) {
    var parts = [value, ...command.rest.take(extraArgs)];
    return parts.join(' ');
  }
  return value;
}

void main(List<String> arguments) async {
  var parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help message')
    ..addFlag('version', abbr: 'v', negatable: false, help: 'Show version')
    ..addFlag(
      'debug',
      abbr: 'd',
      negatable: false,
      help: 'Enable debug logging',
    )
    ..addFlag('verbose', negatable: false, help: 'Enable verbose logging');

  parser
      .addCommand('discover')
      .addOption(
        'timeout',
        abbr: 't',
        help: 'Discovery timeout in seconds',
        defaultsTo: '$cliDefaultDiscoveryTimeoutSeconds',
      );
  (parser.commands['discover'] as ArgParser).addFlag(
    'save',
    abbr: 's',
    negatable: false,
    help: 'Save discovered lights to config',
  );

  parser.addCommand('list');
  addTargetOption(parser.addCommand('status'));
  addTargetOption(parser.addCommand('on')).addOption(
    'brightness',
    abbr: 'b',
    help: 'Brightness ($minBrightness-$maxBrightness)',
  );
  addTargetOption(parser.addCommand('off'));
  addTargetOption(parser.addCommand('toggle'));
  addTargetOption(parser.addCommand('brightness')).addOption(
    'value',
    abbr: 'b',
    help: 'Brightness value ($minBrightness-$maxBrightness)',
  );
  addTargetOption(parser.addCommand('color'))
    ..addOption('rgb', abbr: 'c', help: 'RGB color as R,G,B (e.g., 255,100,50)')
    ..addOption(
      'brightness',
      abbr: 'b',
      help: 'Brightness ($minBrightness-$maxBrightness)',
    );
  addTargetOption(parser.addCommand('temp'))
    ..addOption(
      'kelvin',
      abbr: 'k',
      help: 'Temperature in Kelvin ($minTemperature-$maxTemperature)',
    )
    ..addOption(
      'brightness',
      abbr: 'b',
      help: 'Brightness ($minBrightness-$maxBrightness)',
    );
  addTargetOption(parser.addCommand('scene'))
    ..addOption('scene', abbr: 's', help: 'Scene name')
    ..addOption(
      'brightness',
      abbr: 'b',
      help: 'Brightness ($minBrightness-$maxBrightness)',
    );
  parser.addCommand('scenes');
  parser.addCommand('alias')
    ..addOption('ip', help: 'IP address of the light')
    ..addOption('name', abbr: 'n', help: 'Alias name for the light');

  var groupParser = parser.addCommand('group');
  groupParser.addCommand('list');
  groupParser.addCommand('add')
    ..addOption('name', abbr: 'n', help: 'Group name')
    ..addOption('lights', abbr: 'l', help: 'Comma-separated list of lights');
  groupParser
      .addCommand('remove')
      .addOption('name', abbr: 'n', help: 'Group name to remove');

  var configParser = parser.addCommand('config');
  configParser.addCommand('clear').addFlag(
    'force',
    abbr: 'f',
    negatable: false,
    help: 'Skip confirmation prompt',
  );
  configParser.addCommand('path');

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

  var command = results.command!;

  try {
    switch (command.name) {
      case 'discover':
        var timeout =
            int.tryParse(command['timeout'] as String) ??
            cliDefaultDiscoveryTimeoutSeconds;
        await discoverCommand(timeout: timeout, save: command['save'] as bool);

      case 'list':
        await listCommand();

      case 'status':
        var statusTarget = requireTarget(command, '$cliName status -t <light>');
        if (statusTarget == null) return;
        await statusCommand(statusTarget);

      case 'on':
        var onTarget = requireTarget(
          command,
          '$cliName on -t <light> [--brightness N]',
        );
        if (onTarget == null) return;
        var onBrightness = command['brightness'] != null
            ? int.tryParse(command['brightness'] as String)
            : null;
        await onCommand(onTarget, brightness: onBrightness);

      case 'off':
        var offTarget = requireTarget(command, '$cliName off -t <light>');
        if (offTarget == null) return;
        await offCommand(offTarget);

      case 'toggle':
        var toggleTarget = requireTarget(command, '$cliName toggle -t <light>');
        if (toggleTarget == null) return;
        await toggleCommand(toggleTarget);

      case 'brightness':
        var brightnessTarget = requireTarget(
          command,
          '$cliName brightness -t <light> -b <percent>',
        );
        if (brightnessTarget == null) return;
        var valueStr = command['value'] as String?;
        if (valueStr == null) {
          stderr.writeln('Error: --value/-b is required.');
          stderr.writeln('Usage: $cliName brightness -t <light> -b <percent>');
          exitCode = 1;
          return;
        }
        var percent = int.tryParse(valueStr);
        if (percent == null) {
          stderr.writeln('Error: Invalid brightness value.');
          exitCode = 1;
          return;
        }
        await brightnessCommand(brightnessTarget, percent);

      case 'color':
        var colorTarget = requireTarget(
          command,
          '$cliName color -t <light> -c <R,G,B> [--brightness N]',
        );
        if (colorTarget == null) return;
        var rgbStr = command['rgb'] as String?;
        if (rgbStr == null) {
          stderr.writeln('Error: --rgb/-c is required.');
          stderr.writeln(
            'Usage: $cliName color -t <light> -c <R,G,B> [--brightness N]',
          );
          exitCode = 1;
          return;
        }
        var parts = rgbStr.split(',');
        if (parts.length != 3) {
          stderr.writeln(
            'Error: RGB must be in format R,G,B (e.g., 255,100,50).',
          );
          exitCode = 1;
          return;
        }
        var r = int.tryParse(parts[0].trim());
        var g = int.tryParse(parts[1].trim());
        var b = int.tryParse(parts[2].trim());
        if (r == null || g == null || b == null) {
          stderr.writeln('Error: Invalid RGB values.');
          exitCode = 1;
          return;
        }
        var colorBrightness = command['brightness'] != null
            ? int.tryParse(command['brightness'] as String)
            : null;
        await colorCommand(colorTarget, r, g, b, brightness: colorBrightness);

      case 'temp':
        var tempTarget = requireTarget(
          command,
          '$cliName temp -t <light> -k <kelvin> [--brightness N]',
        );
        if (tempTarget == null) return;
        var kelvinStr = command['kelvin'] as String?;
        if (kelvinStr == null) {
          stderr.writeln('Error: --kelvin/-k is required.');
          stderr.writeln(
            'Usage: $cliName temp -t <light> -k <kelvin> [--brightness N]',
          );
          exitCode = 1;
          return;
        }
        var kelvin = int.tryParse(kelvinStr);
        if (kelvin == null) {
          stderr.writeln('Error: Invalid temperature value.');
          exitCode = 1;
          return;
        }
        var tempBrightness = command['brightness'] != null
            ? int.tryParse(command['brightness'] as String)
            : null;
        await tempCommand(tempTarget, kelvin, brightness: tempBrightness);

      case 'scene':
        var sceneTarget = requireTarget(
          command,
          '$cliName scene -t <light> -s <scene_name> [--brightness N]',
        );
        if (sceneTarget == null) return;
        var sceneName = command['scene'] as String?;
        if (sceneName == null) {
          stderr.writeln('Error: --scene/-s is required.');
          stderr.writeln(
            'Usage: $cliName scene -t <light> -s <scene_name> [--brightness N]',
          );
          exitCode = 1;
          return;
        }
        var sceneBrightness = command['brightness'] != null
            ? int.tryParse(command['brightness'] as String)
            : null;
        await sceneCommand(sceneTarget, sceneName, brightness: sceneBrightness);

      case 'scenes':
        scenesCommand();

      case 'alias':
        var ip = command['ip'] as String?;
        var aliasName = getOptionWithRest(command, 'name');
        if (ip == null || aliasName == null) {
          stderr.writeln('Error: --ip and --name/-n are required.');
          stderr.writeln('Usage: $cliName alias --ip <ip> -n <name>');
          exitCode = 1;
          return;
        }
        await aliasCommand(ip, aliasName);

      case 'group':
        await handleGroupCommand(command);

      case 'config':
        await handleConfigCommand(command);

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

  var subcommand = command.command!;
  switch (subcommand.name) {
    case 'list':
      await groupListCommand();

    case 'add':
      // Syntax: group add -n <name> -l <light1,light2,...>
      var groupName = getOptionWithRest(subcommand, 'name');
      if (groupName == null) {
        stderr.writeln('Error: --name/-n is required.');
        stderr.writeln(
          'Usage: $cliName group add -n <name> -l <light1,light2,...>',
        );
        exitCode = 1;
        return;
      }
      var lightsStr = subcommand['lights'] as String?;
      if (lightsStr == null || lightsStr.isEmpty) {
        stderr.writeln('Error: --lights/-l is required.');
        stderr.writeln(
          'Usage: $cliName group add -n <name> -l <light1,light2,...>',
        );
        exitCode = 1;
        return;
      }
      var lights =
          lightsStr.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (lights.isEmpty) {
        stderr.writeln('Error: At least one light is required.');
        exitCode = 1;
        return;
      }
      await groupAddCommand(groupName, lights);

    case 'remove':
      var groupName = getOptionWithRest(subcommand, 'name');
      if (groupName == null) {
        stderr.writeln('Error: --name/-n is required.');
        stderr.writeln('Usage: $cliName group remove -n <name>');
        exitCode = 1;
        return;
      }
      await groupRemoveCommand(groupName);

    default:
      stderr.writeln('Unknown group subcommand: ${subcommand.name}');
      exitCode = 1;
  }
}

Future<void> handleConfigCommand(ArgResults command) async {
  if (command.command == null) {
    stderr.writeln('Usage: $cliName config <clear|path>');
    exitCode = 1;
    return;
  }

  var subcommand = command.command!;
  switch (subcommand.name) {
    case 'clear':
      await configClearCommand(force: subcommand['force'] as bool);

    case 'path':
      configPathCommand();

    default:
      stderr.writeln('Unknown config subcommand: ${subcommand.name}');
      exitCode = 1;
  }
}

Future<void> configClearCommand({bool force = false}) async {
  var config = await CliConfig.load();

  if (config.lights.isEmpty && config.groups.isEmpty) {
    stdout.writeln('Configuration is already empty.');
    return;
  }

  if (!force) {
    stdout.writeln('This will delete all saved lights, aliases, and groups:');
    stdout.writeln('  ${config.lights.length} light(s)');
    stdout.writeln('  ${config.groups.length} group(s)');
    stdout.write('Are you sure? [y/N] ');

    var response = stdin.readLineSync()?.toLowerCase() ?? '';
    if (response != 'y' && response != 'yes') {
      stdout.writeln('Aborted.');
      return;
    }
  }

  var deleted = await CliConfig.delete();
  if (deleted) {
    stdout.writeln('Configuration cleared.');
  } else {
    stdout.writeln('No configuration file found.');
  }
}

void configPathCommand() {
  stdout.writeln('Configuration file: ${CliConfig.configFile.path}');
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
  status -t <light> Get light state

Control (use -t/--target to specify light, alias, or group):
  on -t <light>                  Turn on
    --brightness, -b             Set brightness
  off -t <light>                 Turn off
  toggle -t <light>              Toggle state
  brightness -t <light> -b <N>   Set brightness ($minBrightness-$maxBrightness)
  color -t <light> -c <R,G,B>    Set RGB color ($minColorValue-$maxColorValue each)
    --brightness, -b             Set brightness
  temp -t <light> -k <K>         Set temperature ($minTemperature-$maxTemperature)
    --brightness, -b             Set brightness
  scene -t <light> -s <name>     Apply scene
    --brightness, -b             Set brightness
  scenes                         List available scenes

Config:
  alias --ip <ip> -n <name>      Set alias for a light
  group list                     List groups
  group add -n <name> -l <lights> Create group (lights: comma-separated)
  group remove -n <name>         Remove group
  config clear                   Delete all saved config
    --force, -f                  Skip confirmation
  config path                    Show config file location

Examples:
  $cliName discover --save
  $cliName alias --ip 192.168.1.100 -n "Living Room"
  $cliName on -t "Living Room"
  $cliName brightness -t "Living Room" -b 80
  $cliName color -t "Living Room" -c 255,100,50
  $cliName temp -t Kitchen -k 4000
  $cliName scene -t all -s cozy
  $cliName group add -n "Living Room" -l "LL-Lamp,LL-1,LL-2"
  $cliName group remove -n all
  $cliName off -t all
  $cliName --debug status -t 192.168.1.100
''');
}
