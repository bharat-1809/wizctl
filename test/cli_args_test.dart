// Tests for CLI argument parsing, especially handling of names with spaces.
//
// These tests verify that the CLI correctly handles alias/group names
// containing spaces, apostrophes, and other special characters.

import 'package:args/args.dart';
import 'package:test/test.dart';

/// Adds --target option to a command parser and returns it for chaining.
ArgParser addTargetOption(ArgParser parser) {
  return parser
    ..addOption('target', abbr: 't', help: 'Light, alias, or group name');
}

/// Gets the target value, joining with rest arguments if the shell split a quoted name.
String? getTarget(ArgResults command, {int restOffset = 0}) {
  var target = command['target'] as String?;
  if (target == null) return null;

  var extraArgs = command.rest.length - restOffset;
  if (extraArgs > 0) {
    var parts = [target, ...command.rest.take(extraArgs)];
    return parts.join(' ');
  }
  return target;
}

/// Gets an option value, joining with rest arguments if the shell split a quoted name.
String? getOptionWithRest(ArgResults command, String optionName,
    {int restOffset = 0}) {
  var value = command[optionName] as String?;
  if (value == null) return null;

  var extraArgs = command.rest.length - restOffset;
  if (extraArgs > 0) {
    var parts = [value, ...command.rest.take(extraArgs)];
    return parts.join(' ');
  }
  return value;
}

void main() {
  group('getTarget', () {
    late ArgParser parser;

    setUp(() {
      parser = ArgParser();
      addTargetOption(parser.addCommand('on'));
      addTargetOption(parser.addCommand('off'));
      addTargetOption(parser.addCommand('color'))
        ..addOption('rgb', abbr: 'c')
        ..addOption('brightness', abbr: 'b');
      addTargetOption(parser.addCommand('temp'))
        ..addOption('kelvin', abbr: 'k')
        ..addOption('brightness', abbr: 'b');
      addTargetOption(parser.addCommand('scene'))
        ..addOption('scene', abbr: 's')
        ..addOption('brightness', abbr: 'b');
      addTargetOption(parser.addCommand('brightness'))
          .addOption('value', abbr: 'b');
    });

    group('simple commands (on/off)', () {
      test('single word target', () {
        // wizctl on -t Kitchen
        var results = parser.parse(['on', '-t', 'Kitchen']);
        var command = results.command!;
        expect(getTarget(command), equals('Kitchen'));
      });

      test('IP address target', () {
        // wizctl on -t 192.168.1.100
        var results = parser.parse(['on', '-t', '192.168.1.100']);
        var command = results.command!;
        expect(getTarget(command), equals('192.168.1.100'));
      });

      test('two word target (shell-split simulation)', () {
        // wizctl on -t "Living Room" -> shell splits to: on -t Living Room
        var results = parser.parse(['on', '-t', 'Living', 'Room']);
        var command = results.command!;
        expect(getTarget(command), equals('Living Room'));
      });

      test('three word target (shell-split simulation)', () {
        // wizctl on -t "Living Room Light" -> shell splits to: on -t Living Room Light
        var results = parser.parse(['on', '-t', 'Living', 'Room', 'Light']);
        var command = results.command!;
        expect(getTarget(command), equals('Living Room Light'));
      });

      test('target with apostrophe (shell-split simulation)', () {
        // wizctl on -t "Ujjawal's Room" -> shell splits to: on -t Ujjawal's Room
        var results = parser.parse(['on', '-t', "Ujjawal's", 'Room']);
        var command = results.command!;
        expect(getTarget(command), equals("Ujjawal's Room"));
      });

      test('target with multiple special chars', () {
        // wizctl on -t "Room #1 (Main)" -> shell splits
        var results = parser.parse(['on', '-t', 'Room', '#1', '(Main)']);
        var command = results.command!;
        expect(getTarget(command), equals('Room #1 (Main)'));
      });
    });

    group('color command with flags', () {
      test('target before -c flag', () {
        // wizctl color -t "Living Room" -c 255,100,50
        // Shell: color -t Living Room -c 255,100,50
        var results =
            parser.parse(['color', '-t', 'Living', 'Room', '-c', '255,100,50']);
        var command = results.command!;
        expect(getTarget(command), equals('Living Room'));
        expect(command['rgb'], equals('255,100,50'));
      });

      test('target after -c flag', () {
        // wizctl color -c 255,100,50 -t "Living Room"
        // Shell: color -c 255,100,50 -t Living Room
        var results =
            parser.parse(['color', '-c', '255,100,50', '-t', 'Living', 'Room']);
        var command = results.command!;
        expect(getTarget(command), equals('Living Room'));
        expect(command['rgb'], equals('255,100,50'));
      });

      test('target between flags', () {
        // wizctl color -c 255,100,50 -t "Living Room" -b 80
        // Shell: color -c 255,100,50 -t Living Room -b 80
        var results = parser.parse(
            ['color', '-c', '255,100,50', '-t', 'Living', 'Room', '-b', '80']);
        var command = results.command!;
        expect(getTarget(command), equals('Living Room'));
        expect(command['rgb'], equals('255,100,50'));
        expect(command['brightness'], equals('80'));
      });

      test('three word target with all flags', () {
        // wizctl color -t "Living Room Light" -c 255,100,50 -b 80
        var results = parser.parse([
          'color',
          '-t',
          'Living',
          'Room',
          'Light',
          '-c',
          '255,100,50',
          '-b',
          '80'
        ]);
        var command = results.command!;
        expect(getTarget(command), equals('Living Room Light'));
        expect(command['rgb'], equals('255,100,50'));
        expect(command['brightness'], equals('80'));
      });

      test('target at end after all flags', () {
        // wizctl color -c 255,100,50 -b 80 -t "Living Room"
        var results = parser.parse(
            ['color', '-c', '255,100,50', '-b', '80', '-t', 'Living', 'Room']);
        var command = results.command!;
        expect(getTarget(command), equals('Living Room'));
        expect(command['rgb'], equals('255,100,50'));
        expect(command['brightness'], equals('80'));
      });
    });

    group('temp command', () {
      test('target with kelvin flag', () {
        // wizctl temp -t "Living Room" -k 4000
        var results =
            parser.parse(['temp', '-t', 'Living', 'Room', '-k', '4000']);
        var command = results.command!;
        expect(getTarget(command), equals('Living Room'));
        expect(command['kelvin'], equals('4000'));
      });

      test('target with kelvin and brightness', () {
        // wizctl temp -t "Ujjawal's Room" -k 4000 -b 80
        var results = parser.parse(
            ['temp', '-t', "Ujjawal's", 'Room', '-k', '4000', '-b', '80']);
        var command = results.command!;
        expect(getTarget(command), equals("Ujjawal's Room"));
        expect(command['kelvin'], equals('4000'));
        expect(command['brightness'], equals('80'));
      });
    });

    group('scene command', () {
      test('target with scene flag', () {
        // wizctl scene -t "Living Room" -s cozy
        var results =
            parser.parse(['scene', '-t', 'Living', 'Room', '-s', 'cozy']);
        var command = results.command!;
        expect(getTarget(command), equals('Living Room'));
        expect(command['scene'], equals('cozy'));
      });

      test('all flags in different order', () {
        // wizctl scene -s cozy -b 80 -t "Living Room"
        var results = parser
            .parse(['scene', '-s', 'cozy', '-b', '80', '-t', 'Living', 'Room']);
        var command = results.command!;
        expect(getTarget(command), equals('Living Room'));
        expect(command['scene'], equals('cozy'));
        expect(command['brightness'], equals('80'));
      });
    });

    group('brightness command', () {
      test('target with value flag', () {
        // wizctl brightness -t "Living Room" -b 80
        var results =
            parser.parse(['brightness', '-t', 'Living', 'Room', '-b', '80']);
        var command = results.command!;
        expect(getTarget(command), equals('Living Room'));
        expect(command['value'], equals('80'));
      });
    });

    group('edge cases', () {
      test('no target provided', () {
        var results = parser.parse(['on']);
        var command = results.command!;
        expect(getTarget(command), isNull);
      });

      test('empty rest args with single word target', () {
        var results = parser.parse(['on', '-t', 'Kitchen']);
        var command = results.command!;
        expect(command.rest, isEmpty);
        expect(getTarget(command), equals('Kitchen'));
      });

      test('long form --target flag', () {
        var results = parser.parse(['on', '--target', 'Living', 'Room']);
        var command = results.command!;
        expect(getTarget(command), equals('Living Room'));
      });
    });
  });

  group('getOptionWithRest', () {
    late ArgParser parser;

    setUp(() {
      parser = ArgParser();
      parser.addCommand('alias')
        ..addOption('ip')
        ..addOption('name', abbr: 'n');
      var groupParser = parser.addCommand('group');
      groupParser.addCommand('remove').addOption('name', abbr: 'n');
    });

    group('alias command', () {
      test('name with spaces', () {
        // wizctl alias --ip 192.168.1.100 -n "Living Room"
        // Shell: alias --ip 192.168.1.100 -n Living Room
        var results = parser
            .parse(['alias', '--ip', '192.168.1.100', '-n', 'Living', 'Room']);
        var command = results.command!;
        expect(command['ip'], equals('192.168.1.100'));
        expect(getOptionWithRest(command, 'name'), equals('Living Room'));
      });

      test('name with apostrophe', () {
        // wizctl alias --ip 192.168.1.100 -n "Ujjawal's Room"
        var results = parser.parse(
            ['alias', '--ip', '192.168.1.100', '-n', "Ujjawal's", 'Room']);
        var command = results.command!;
        expect(getOptionWithRest(command, 'name'), equals("Ujjawal's Room"));
      });

      test('single word name', () {
        var results =
            parser.parse(['alias', '--ip', '192.168.1.100', '-n', 'Kitchen']);
        var command = results.command!;
        expect(getOptionWithRest(command, 'name'), equals('Kitchen'));
      });

      test('three word name', () {
        var results = parser.parse([
          'alias',
          '--ip',
          '192.168.1.100',
          '-n',
          'Living',
          'Room',
          'Light'
        ]);
        var command = results.command!;
        expect(getOptionWithRest(command, 'name'), equals('Living Room Light'));
      });
    });

    group('group remove command', () {
      test('group name with spaces', () {
        // wizctl group remove -n "All Lights"
        var results =
            parser.parse(['group', 'remove', '-n', 'All', 'Lights']);
        var command = results.command!.command!;
        expect(getOptionWithRest(command, 'name'), equals('All Lights'));
      });

      test('single word group name', () {
        var results = parser.parse(['group', 'remove', '-n', 'bedroom']);
        var command = results.command!.command!;
        expect(getOptionWithRest(command, 'name'), equals('bedroom'));
      });
    });
  });

  group('regression tests', () {
    late ArgParser parser;

    setUp(() {
      parser = ArgParser();
      addTargetOption(parser.addCommand('on'));
      addTargetOption(parser.addCommand('color'))
        ..addOption('rgb', abbr: 'c')
        ..addOption('brightness', abbr: 'b');
    });

    test('original issue: apostrophe in name', () {
      // This was the original failing case
      // wizctl on -t "Ujjawal's Room"
      var results = parser.parse(['on', '-t', "Ujjawal's", 'Room']);
      var command = results.command!;
      expect(getTarget(command), equals("Ujjawal's Room"));
    });

    test('original issue: spaces in name', () {
      // wizctl on -t "Living Room Light"
      var results = parser.parse(['on', '-t', 'Living', 'Room', 'Light']);
      var command = results.command!;
      expect(getTarget(command), equals('Living Room Light'));
    });

    test('color command does not consume RGB as part of target', () {
      // Ensure -c flag properly terminates target collection
      var results =
          parser.parse(['color', '-t', 'Living', 'Room', '-c', '255,100,50']);
      var command = results.command!;
      expect(getTarget(command), equals('Living Room'));
      expect(command['rgb'], equals('255,100,50'));
      // RGB should NOT be part of target
      expect(getTarget(command), isNot(contains('255')));
    });
  });
}
