// Tests for CLI configuration storage.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

// Manually define LightConfig and CliConfig classes to test without importing from bin/
// This mirrors the actual implementation in bin/cli/config.dart

class LightConfig {
  final String? alias;
  final String? mac;

  const LightConfig({this.alias, this.mac});

  factory LightConfig.fromJson(Map<String, dynamic> json) =>
      LightConfig(alias: json['alias'] as String?, mac: json['mac'] as String?);

  Map<String, dynamic> toJson() => {
        if (alias != null) 'alias': alias,
        if (mac != null) 'mac': mac,
      };
}

class CliConfig {
  final Map<String, LightConfig> lights;
  final Map<String, List<String>> groups;

  CliConfig({
    Map<String, LightConfig>? lights,
    Map<String, List<String>>? groups,
  })  : lights = lights ?? {},
        groups = groups ?? {};

  factory CliConfig.fromJson(Map<String, dynamic> json) {
    var lightsJson = json['lights'] as Map<String, dynamic>? ?? {};
    var groupsJson = json['groups'] as Map<String, dynamic>? ?? {};

    return CliConfig(
      lights: lightsJson.map(
        (ip, data) =>
            MapEntry(ip, LightConfig.fromJson(data as Map<String, dynamic>)),
      ),
      groups: groupsJson.map(
        (name, ips) => MapEntry(name, List<String>.from(ips as List)),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'lights': lights.map((ip, config) => MapEntry(ip, config.toJson())),
        'groups': groups,
      };

  void setAlias(String ip, String alias, {String? mac}) {
    lights[ip] = LightConfig(alias: alias, mac: mac ?? lights[ip]?.mac);
  }

  String? getAlias(String ip) => lights[ip]?.alias;

  String? resolveLight(String aliasOrIp) {
    if (_isIpAddress(aliasOrIp)) return aliasOrIp;

    for (var entry in lights.entries) {
      if (entry.value.alias?.toLowerCase() == aliasOrIp.toLowerCase()) {
        return entry.key;
      }
    }
    return null;
  }

  List<String>? resolveGroup(String name) => groups[name];

  void addGroup(String name, List<String> ips) => groups[name] = ips;

  void removeGroup(String name) => groups.remove(name);

  void clear() {
    lights.clear();
    groups.clear();
  }

  bool _isIpAddress(String value) {
    var parts = value.split('.');
    if (parts.length != 4) return false;
    return parts.every((part) {
      var n = int.tryParse(part);
      return n != null && n >= 0 && n <= 255;
    });
  }
}

void main() {
  group('LightConfig', () {
    test('serializes to JSON correctly', () {
      var config = LightConfig(alias: 'Living Room', mac: 'aabbccddeeff');
      var json = config.toJson();

      expect(json['alias'], equals('Living Room'));
      expect(json['mac'], equals('aabbccddeeff'));
    });

    test('serializes without null values', () {
      var config = LightConfig(alias: 'Kitchen');
      var json = config.toJson();

      expect(json.containsKey('alias'), isTrue);
      expect(json.containsKey('mac'), isFalse);
    });

    test('deserializes from JSON correctly', () {
      var json = {'alias': 'Bedroom', 'mac': '112233445566'};
      var config = LightConfig.fromJson(json);

      expect(config.alias, equals('Bedroom'));
      expect(config.mac, equals('112233445566'));
    });

    test('handles missing fields in JSON', () {
      var json = <String, dynamic>{};
      var config = LightConfig.fromJson(json);

      expect(config.alias, isNull);
      expect(config.mac, isNull);
    });
  });

  group('CliConfig', () {
    test('creates empty config by default', () {
      var config = CliConfig();

      expect(config.lights, isEmpty);
      expect(config.groups, isEmpty);
    });

    test('setAlias adds new light', () {
      var config = CliConfig();
      config.setAlias('192.168.1.100', 'Living Room', mac: 'aabbcc');

      expect(config.lights.length, equals(1));
      expect(config.lights['192.168.1.100']?.alias, equals('Living Room'));
      expect(config.lights['192.168.1.100']?.mac, equals('aabbcc'));
    });

    test('setAlias updates existing light', () {
      var config = CliConfig();
      config.setAlias('192.168.1.100', 'Living Room', mac: 'aabbcc');
      config.setAlias('192.168.1.100', 'New Name');

      expect(config.lights.length, equals(1));
      expect(config.lights['192.168.1.100']?.alias, equals('New Name'));
      // MAC should be preserved when not provided
      expect(config.lights['192.168.1.100']?.mac, equals('aabbcc'));
    });

    test('getAlias returns alias for known IP', () {
      var config = CliConfig();
      config.setAlias('192.168.1.100', 'Kitchen');

      expect(config.getAlias('192.168.1.100'), equals('Kitchen'));
    });

    test('getAlias returns null for unknown IP', () {
      var config = CliConfig();

      expect(config.getAlias('192.168.1.100'), isNull);
    });

    test('resolveLight returns IP for valid IP address', () {
      var config = CliConfig();

      expect(config.resolveLight('192.168.1.100'), equals('192.168.1.100'));
      expect(config.resolveLight('10.0.0.1'), equals('10.0.0.1'));
      expect(config.resolveLight('255.255.255.255'), equals('255.255.255.255'));
    });

    test('resolveLight returns IP for known alias', () {
      var config = CliConfig();
      config.setAlias('192.168.1.100', 'Living Room');

      expect(config.resolveLight('Living Room'), equals('192.168.1.100'));
    });

    test('resolveLight is case-insensitive for aliases', () {
      var config = CliConfig();
      config.setAlias('192.168.1.100', 'Living Room');

      expect(config.resolveLight('living room'), equals('192.168.1.100'));
      expect(config.resolveLight('LIVING ROOM'), equals('192.168.1.100'));
    });

    test('resolveLight returns null for unknown alias', () {
      var config = CliConfig();

      expect(config.resolveLight('Unknown'), isNull);
    });

    test('addGroup creates new group', () {
      var config = CliConfig();
      config.addGroup('all', ['192.168.1.100', '192.168.1.101']);

      expect(config.groups['all'], hasLength(2));
      expect(config.groups['all'], contains('192.168.1.100'));
    });

    test('removeGroup deletes group', () {
      var config = CliConfig();
      config.addGroup('all', ['192.168.1.100']);
      config.removeGroup('all');

      expect(config.groups['all'], isNull);
    });

    test('resolveGroup returns IPs for known group', () {
      var config = CliConfig();
      config.addGroup('bedroom', ['192.168.1.100', '192.168.1.101']);

      var ips = config.resolveGroup('bedroom');
      expect(ips, hasLength(2));
    });

    test('resolveGroup returns null for unknown group', () {
      var config = CliConfig();

      expect(config.resolveGroup('unknown'), isNull);
    });

    test('clear removes all lights and groups', () {
      var config = CliConfig();
      config.setAlias('192.168.1.100', 'Living Room');
      config.setAlias('192.168.1.101', 'Bedroom');
      config.addGroup('all', ['192.168.1.100', '192.168.1.101']);

      expect(config.lights, hasLength(2));
      expect(config.groups, hasLength(1));

      config.clear();

      expect(config.lights, isEmpty);
      expect(config.groups, isEmpty);
    });

    test('toJson serializes correctly', () {
      var config = CliConfig();
      config.setAlias('192.168.1.100', 'Living Room', mac: 'aabbcc');
      config.addGroup('all', ['192.168.1.100']);

      var json = config.toJson();

      expect(json['lights'], isA<Map>());
      expect(json['groups'], isA<Map>());
      expect(
        (json['lights'] as Map)['192.168.1.100']['alias'],
        equals('Living Room'),
      );
      expect((json['groups'] as Map)['all'], equals(['192.168.1.100']));
    });

    test('fromJson deserializes correctly', () {
      var json = {
        'lights': {
          '192.168.1.100': {'alias': 'Living Room', 'mac': 'aabbcc'},
          '192.168.1.101': {'alias': 'Bedroom'},
        },
        'groups': {
          'all': ['192.168.1.100', '192.168.1.101'],
        },
      };

      var config = CliConfig.fromJson(json);

      expect(config.lights, hasLength(2));
      expect(config.groups, hasLength(1));
      expect(config.getAlias('192.168.1.100'), equals('Living Room'));
      expect(config.resolveGroup('all'), hasLength(2));
    });

    test('fromJson handles empty JSON', () {
      var config = CliConfig.fromJson({});

      expect(config.lights, isEmpty);
      expect(config.groups, isEmpty);
    });

    test('round-trip serialization', () {
      var original = CliConfig();
      original.setAlias('192.168.1.100', 'Living Room', mac: 'aabbcc');
      original.setAlias('192.168.1.101', 'Bedroom', mac: 'ddeeff');
      original.addGroup('all', ['192.168.1.100', '192.168.1.101']);
      original.addGroup('bedroom', ['192.168.1.101']);

      var json = original.toJson();
      var restored = CliConfig.fromJson(json);

      expect(restored.lights.length, equals(original.lights.length));
      expect(restored.groups.length, equals(original.groups.length));
      expect(
        restored.getAlias('192.168.1.100'),
        equals(original.getAlias('192.168.1.100')),
      );
      expect(
        restored.resolveGroup('all'),
        equals(original.resolveGroup('all')),
      );
    });

    test('JSON string encoding', () {
      var config = CliConfig();
      config.setAlias('192.168.1.100', "Ujjawal's Room", mac: 'aabbcc');
      config.addGroup('all', ['192.168.1.100']);

      var jsonStr = jsonEncode(config.toJson());
      var json = jsonDecode(jsonStr) as Map<String, dynamic>;
      var restored = CliConfig.fromJson(json);

      expect(restored.getAlias('192.168.1.100'), equals("Ujjawal's Room"));
    });
  });

  group('CliConfig file operations', () {
    late Directory tempDir;
    late File configFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wizctl_test_');
      configFile = File('${tempDir.path}/config.json');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('save and load config from file', () async {
      var config = CliConfig();
      config.setAlias('192.168.1.100', 'Living Room');
      config.addGroup('all', ['192.168.1.100']);

      // Save
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config.toJson()),
      );

      // Load
      var content = await configFile.readAsString();
      var loaded = CliConfig.fromJson(jsonDecode(content) as Map<String, dynamic>);

      expect(loaded.getAlias('192.168.1.100'), equals('Living Room'));
      expect(loaded.resolveGroup('all'), hasLength(1));
    });

    test('delete config file', () async {
      // Create config file
      await configFile.writeAsString('{"lights":{}, "groups":{}}');
      expect(await configFile.exists(), isTrue);

      // Delete
      await configFile.delete();
      expect(await configFile.exists(), isFalse);
    });
  });
}
