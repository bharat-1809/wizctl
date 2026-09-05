import 'dart:io';

import 'package:wizctl/wizctl.dart';

import '../config.dart';

Future<void> discoverCommand({
  int timeout = 5,
  bool save = false,
  String? broadcast,
  bool scan = false,
  String? subnet,
}) async {
  var config = await CliConfig.load();
  var lights = <DiscoveredLight>[];

  // Lights we have seen before get asked directly. That is both quicker and
  // far more reliable than sweeping the subnet, which floods the kernel's ARP
  // hold queue and can then miss lights that answer a direct request happily.
  // --scan means "go and look properly", so it skips this shortcut.
  if (!scan &&
      config.lights.isNotEmpty &&
      subnet == null &&
      broadcast == null) {
    stdout.writeln('Checking ${config.lights.length} known light(s)...');
    lights = await WizDiscovery.probeAddresses(
      addresses: config.lights.keys,
      timeout: Duration(seconds: timeout),
    );
    if (lights.length == config.lights.length) {
      // Everything we know about is present, so there is nothing to gain from
      // sweeping. A new light still needs a scan, so say so rather than
      // leaving the user wondering why it never turns up.
      stdout.writeln('  all ${lights.length} responded.');
      stdout.writeln('  (run "$cliName discover --scan" to look for new ones)');
    } else if (lights.isNotEmpty) {
      stdout.writeln(
        '  ${lights.length} of ${config.lights.length} responded, '
        'looking for the rest...',
      );
      lights = [];
    }
  }

  // --scan skips the broadcast phases entirely. Where the lights are known
  // not to answer broadcast, those phases only waste the user's time.
  if (lights.isEmpty && !scan) {
    stdout.writeln('Discovering WiZ lights...');
    try {
      lights = await WizDiscovery.discover(
        broadcastAddress: broadcast ?? defaultBroadcastAddress,
        timeout: Duration(seconds: timeout),
      );
    } on WizConnectionError catch (e) {
      // The default route may be a VPN tunnel, which has no broadcast domain.
      // That's a reason to try the other interfaces, not to give up.
      stdout.writeln('Broadcast on the default route failed: ${e.message}');
    }

    // A VPN or a second adapter can own the default route, in which case the
    // global broadcast goes somewhere the lights aren't.
    if (lights.isEmpty && broadcast == null) {
      stdout.writeln('Nothing on the default route, trying each interface...');
      lights = await WizDiscovery.discoverOnAllInterfaces(
        timeout: Duration(seconds: timeout),
      );
    }
  }

  // Some lights never answer the discovery broadcast — AP broadcast filtering
  // or Wi-Fi power save on the bulb — while staying perfectly reachable one
  // address at a time. That makes them invisible to broadcast discovery.
  if (lights.isEmpty) {
    stdout.writeln(
      scan
          ? 'Scanning the subnet...'
          : 'Broadcast found nothing. Scanning the subnet directly...',
    );
    try {
      lights = await WizDiscovery.scanSubnet(
        subnet: subnet,
        timeout: Duration(seconds: timeout),
      );
    } on WizConnectionError catch (e) {
      stdout.writeln('Scan failed: ${e.message}');
    }
  }

  // A sweep can come back empty on a network where every light answers a
  // direct request. Never report nothing while we still hold addresses that
  // worked before - ask them before giving up.
  if (lights.isEmpty && config.lights.isNotEmpty) {
    stdout.writeln('Sweep found nothing, asking known lights directly...');
    lights = await WizDiscovery.probeAddresses(
      addresses: config.lights.keys,
      timeout: Duration(seconds: timeout),
    );
  }

  if (lights.isEmpty) {
    await _printNoLightsHelp();
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
    for (var light in lights) {
      // A light that moved to a new address keeps its alias: match on MAC,
      // which is stable, rather than on the IP, which DHCP can change.
      String? alias;
      config.lights.removeWhere((ip, entry) {
        if (entry.mac != light.mac || ip == light.ip) return false;
        alias = entry.alias;
        stdout.writeln('  ${light.mac} moved: $ip -> ${light.ip}');
        return true;
      });
      var existing = config.lights[light.ip];
      config.lights[light.ip] = LightConfig(
        alias: existing?.alias ?? alias,
        mac: light.mac,
      );
    }
    await config.save();
    stdout.writeln('Saved ${lights.length} light(s) to config.');
  }
}

/// Discovery failing is almost always the network, not the light. Print what
/// we searched so the user has somewhere concrete to start.
Future<void> _printNoLightsHelp() async {
  stdout.writeln('No lights found.');
  stdout.writeln();

  try {
    var interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    stdout.writeln('Searched from:');
    for (var interface in interfaces) {
      for (var address in interface.addresses) {
        stdout.writeln('  ${interface.name}: ${address.address}');
      }
    }
    stdout.writeln();
  } catch (_) {
    // Interface listing is a nicety; don't fail the command over it.
  }

  stdout.writeln('Things to check:');
  stdout.writeln(
    '  1. Check your router\'s DHCP client list (usually http://192.168.0.1)',
  );
  stdout.writeln(
    '     for the lights. Note the IP shown in the WiZ app can be stale - the',
  );
  stdout.writeln(
    '     app controls lights through the cloud, so it keeps working even when',
  );
  stdout.writeln('     the light is unreachable on your network.');
  stdout.writeln(
    '  2. If the lights are on a different subnet, scan it directly:',
  );
  stdout.writeln('       $cliName discover --scan --subnet 192.168.1');
  stdout.writeln(
    '  3. Lights are 2.4GHz only. If yours are on a separate IoT or guest',
  );
  stdout.writeln(
    '     network, this machine has to be on that network to reach them.',
  );
  stdout.writeln(
    '  4. Re-run with --debug to see the packets that go out and come back:',
  );
  stdout.writeln('       $cliName --debug discover');
}
