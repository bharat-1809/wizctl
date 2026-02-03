// CLI configuration storage for light aliases and groups.
//
// Stores configuration in ~/.config/wizctl/config.json

import 'dart:convert';
import 'dart:io';

import 'package:wizctl/wizctl.dart';

class CliConfig {
  /// Map of IP addresses to light info (alias, mac).
  final Map<String, LightConfig> lights;

  /// Map of group names to lists of IP addresses.
  final Map<String, List<String>> groups;

  CliConfig({
    Map<String, LightConfig>? lights,
    Map<String, List<String>>? groups,
  }) : lights = lights ?? {},
       groups = groups ?? {};

  /// Gets the config file path.
  static File get configFile {
    var home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return File('$home/.config/$configDirName/$configFileName');
  }

  /// Loads the configuration from disk.
  static Future<CliConfig> load() async {
    var file = configFile;
    if (!await file.exists()) return CliConfig();

    try {
      var content = await file.readAsString();
      var json = jsonDecode(content) as Map<String, dynamic>;
      return CliConfig.fromJson(json);
    } catch (_) {
      return CliConfig();
    }
  }

  /// Saves the configuration to disk.
  Future<void> save() async {
    var file = configFile;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
    );
  }

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

  /// Resolves an alias or IP to an IP address.
  ///
  /// Returns the input if it's already an IP, or looks up the alias.
  String? resolveLight(String aliasOrIp) {
    if (_isIpAddress(aliasOrIp)) return aliasOrIp;

    for (var entry in lights.entries) {
      if (entry.value.alias?.toLowerCase() == aliasOrIp.toLowerCase()) {
        return entry.key;
      }
    }
    return null;
  }

  /// Resolves a group name to a list of IPs.
  List<String>? resolveGroup(String name) => groups[name];

  void addGroup(String name, List<String> ips) => groups[name] = ips;

  void removeGroup(String name) => groups.remove(name);

  bool _isIpAddress(String value) {
    var parts = value.split('.');
    if (parts.length != 4) return false;
    return parts.every((part) {
      var n = int.tryParse(part);
      return n != null && n >= 0 && n <= 255;
    });
  }
}

/// Configuration for a single light (CLI alias/mac storage).
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
