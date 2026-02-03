// Example: Control WiZ lights with wizctl
//
// This example demonstrates all features of the wizctl library.

import 'package:wizctl/wizctl.dart';

void main() async {
  // ==========================================================================
  // Logging
  // ==========================================================================
  print('Enabling debug logging...\n');

  // Enable logging to see UDP packets and protocol details
  WizLogger.enable(WizLogLevel.info);

  // Custom log callback (optional)
  WizLogger.enable(WizLogLevel.debug, callback: (level, message) {
    print('[${level.name.toUpperCase()}] $message');
  });

  // ==========================================================================
  // Discovery
  // ==========================================================================
  print('Discovering WiZ lights...\n');

  // Simple discovery with default settings
  var discovered = await WizDiscovery.discover(timeout: Duration(seconds: 5));

  // Discovery with custom retry configuration
  var discoveredWithRetry = await WizDiscovery.discover(
    timeout: Duration(seconds: 5),
    retry: RetryConfig.exponential(
      count: 3,
      initialInterval: Duration(milliseconds: 500),
      maxInterval: Duration(seconds: 2),
    ),
  );

  // Discovery on all network interfaces (useful with multiple adapters)
  // var allInterfacesLights = await WizDiscovery.discoverOnAllInterfaces();

  if (discovered.isEmpty) {
    print('No lights found. Check WiFi connection.');
    return;
  }

  print('Found ${discovered.length} light(s):');
  for (var light in discovered) {
    print('  ${light.ip} (${light.mac})');
    if (light.moduleName != null) print('    Module: ${light.moduleName}');
    if (light.fwVersion != null) print('    Firmware: ${light.fwVersion}');
    if (light.bulbClass != null) {
      print('    Type: ${light.bulbClass!.displayName}');
      print('    Supports color: ${light.supportsColor}');
      print('    Supports temperature: ${light.supportsTemperature}');
    }
  }

  // ==========================================================================
  // Individual Light Control
  // ==========================================================================

  // Create a WizLight instance with the first discovered light
  var light = WizLight(discovered.first.ip);

  // Get current state
  var state = await light.getState();
  print('\nCurrent state: ${state.isOn ? 'ON' : 'OFF'}, ${state.dimming}%');
  if (state.scene != null) print('Scene: ${state.scene!.displayName}');

  // Check what mode the light is in
  print('Mode: ${_describeMode(state)}');

  // Get bulb configuration (cached after first call)
  var config = await light.getSystemConfig();
  print('\nBulb configuration:');
  print('  MAC: ${config.mac}');
  print('  Module: ${config.moduleName}');
  print('  Firmware: ${config.fwVersion}');
  if (config.bulbClass != null) {
    print('  Type: ${config.bulbClass!.displayName}');
    print('  Supports color: ${config.supportsColor}');
    print('  Supports temperature: ${config.supportsTemperature}');
    print('  Supports brightness: ${config.supportsBrightness}');
  }

  // Get supported Kelvin range
  var kelvinRange = await light.getKelvinRange();
  print('  Kelvin range: ${kelvinRange.min}K - ${kelvinRange.max}K');

  // ==========================================================================
  // Basic Control
  // ==========================================================================
  print('\nBasic control...');

  // Turn on with optional brightness
  await light.turnOn(brightness: 75);
  await Future.delayed(Duration(seconds: 1));

  // Toggle the light
  await light.toggle();
  await Future.delayed(Duration(seconds: 1));
  await light.toggle(); // Toggle back on
  await Future.delayed(Duration(seconds: 1));

  // Set brightness
  await light.setBrightness(50);
  await Future.delayed(Duration(seconds: 1));

  // ==========================================================================
  // Color Control
  // ==========================================================================
  print('\nColor control...');

  // RGB color
  await light.setColor(255, 100, 50);
  await Future.delayed(Duration(seconds: 2));

  // RGB with brightness
  await light.setColor(100, 200, 255, brightness: 80);
  await Future.delayed(Duration(seconds: 2));

  // Color temperature
  await light.setTemperature(3000);
  await Future.delayed(Duration(seconds: 2));

  // Color temperature with brightness
  await light.setTemperature(5000, brightness: 60);
  await Future.delayed(Duration(seconds: 2));

  // ==========================================================================
  // White LED Control
  // ==========================================================================
  print('\nWhite LED control...');

  // Set warm white intensity (0-255)
  await light.setWarmWhite(200, brightness: 70);
  await Future.delayed(Duration(seconds: 2));

  // Set cold white intensity (0-255)
  await light.setColdWhite(150, brightness: 70);
  await Future.delayed(Duration(seconds: 2));

  // Set both cold and warm white
  await light.setWhite(coldWhite: 100, warmWhite: 150, brightness: 60);
  await Future.delayed(Duration(seconds: 2));

  // ==========================================================================
  // Scenes
  // ==========================================================================
  print('\nScene control...');

  // List some available scenes
  print(
    'Available scenes: ${WizScene.values.take(5).map((s) => s.displayName).join(', ')}...',
  );

  // Apply the Cozy scene
  print('Applying "Cozy" scene...');
  await light.setScene(WizScene.cozy);
  await Future.delayed(Duration(seconds: 2));

  // Apply Sunset scene with custom brightness
  print('Applying "Sunset" scene with brightness 80...');
  await light.setScene(WizScene.sunset, brightness: 80);
  await Future.delayed(Duration(seconds: 2));

  // Apply a dynamic scene with custom speed (10-200)
  print('Applying "Party" scene with speed 150...');
  await light.setScene(WizScene.party, speed: 150);
  await Future.delayed(Duration(seconds: 2));

  // Set effect speed independently
  await light.setSpeed(100);
  await Future.delayed(Duration(seconds: 2));

  // ==========================================================================
  // ControlSignal - Combined Settings
  // ==========================================================================
  print('\nUsing ControlSignal for combined settings...');

  // Full control signal with multiple parameters
  await light.send(
    ControlSignal(state: true, dimming: 80, r: 200, g: 150, b: 255),
  );
  await Future.delayed(Duration(seconds: 2));

  // Factory constructors for common operations
  await light.send(ControlSignal.on());
  await light.send(ControlSignal.brightness(50));
  await light.send(ControlSignal.rgb(255, 100, 0, brightness: 70));
  await light.send(ControlSignal.temperature(4000, brightness: 60));
  await light.send(ControlSignal.scene(WizScene.ocean, brightness: 80));
  await light.send(ControlSignal.warmWhite(200));
  await light.send(ControlSignal.coldWhite(150));
  await light.send(ControlSignal.speed(100));
  await Future.delayed(Duration(seconds: 2));

  // ==========================================================================
  // Group Control (if multiple lights discovered)
  // ==========================================================================

  if (discoveredWithRetry.length > 1) {
    var lights = discoveredWithRetry.map((d) => WizLight(d.ip)).toList();

    print('\nControlling ${lights.length} lights together...');

    // Basic group operations
    await WizGroup.turnOn(lights, brightness: 75);
    await WizGroup.setColor(lights, 255, 100, 50);
    await WizGroup.setTemperature(lights, 4000);
    await WizGroup.setScene(lights, WizScene.cozy, brightness: 80);
    await WizGroup.setBrightness(lights, 60);
    await WizGroup.setWarmWhite(lights, 150);
    await WizGroup.setColdWhite(lights, 100);
    await WizGroup.setSpeed(lights, 100);
    await WizGroup.toggle(lights);

    // Send custom ControlSignal to all lights
    await WizGroup.send(lights, ControlSignal(state: true, dimming: 50));

    // Get states from all lights
    var states = await WizGroup.getStates(lights);
    for (var entry in states.entries) {
      print('  ${entry.key.ip}: ${entry.value?.isOn ?? false ? 'ON' : 'OFF'}');
    }

    // Check operation results for failures
    var results = await WizGroup.turnOn(lights);
    for (var result in results) {
      if (!result.success) {
        print('Failed: ${result.light.ip} - ${result.error}');
      }
    }

    await WizGroup.turnOff(lights);
  }

  // ==========================================================================
  // Error Handling
  // ==========================================================================
  print('\nError handling examples...');

  // Invalid brightness
  try {
    await light.setBrightness(150); // Invalid: must be 10-100
  } on WizArgumentError catch (e) {
    print('Caught WizArgumentError: ${e.message}');
  }

  // Invalid color value
  try {
    await light.setColor(300, 100, 50); // Invalid: must be 0-255
  } on WizArgumentError catch (e) {
    print('Caught WizArgumentError: ${e.message}');
  }

  // Invalid temperature
  try {
    await light.setTemperature(10000); // Invalid: must be 2200-6500
  } on WizArgumentError catch (e) {
    print('Caught WizArgumentError: ${e.message}');
  }

  // Timeout error (unreachable light)
  try {
    var fake = WizLight('192.168.1.254', timeout: Duration(seconds: 2));
    await fake.getState();
  } on WizTimeoutError catch (e) {
    print('Caught WizTimeoutError: ${e.message}');
  }

  // Connection error
  try {
    var fake = WizLight('999.999.999.999');
    await fake.getState();
  } on WizConnectionError catch (e) {
    print('Caught WizConnectionError: ${e.message}');
  }

  // ==========================================================================
  // Retry Configuration Examples
  // ==========================================================================
  print('\nRetry configuration examples...');

  // Retry configurations can be used with WizDiscovery.discover()
  // and are built into WizProtocol.send() for individual light communication.

  // No retries (single attempt)
  print('  RetryConfig.none() - single attempt');
  var noRetry = RetryConfig.none();
  print('    Count: ${noRetry.count}, Enabled: ${noRetry.enabled}');

  // Fixed interval retries
  print('  RetryConfig.fixed() - fixed intervals');
  var fixedRetry = RetryConfig.fixed(
    count: 3,
    interval: Duration(seconds: 1),
  );
  print('    Count: ${fixedRetry.count}, Interval: ${fixedRetry.interval}');

  // Exponential backoff (default for the library)
  print('  RetryConfig.exponential() - exponential backoff');
  var expRetry = RetryConfig.exponential(
    count: 5,
    initialInterval: Duration(milliseconds: 750),
    maxInterval: Duration(seconds: 3),
  );
  print('    Count: ${expRetry.count}, Initial: ${expRetry.interval}');

  // The library uses default exponential backoff:
  // - 5 retries with exponential backoff
  // - Starting at 750ms, capping at 3s

  // ==========================================================================
  // System Commands
  // ==========================================================================
  print('\nSystem commands (commented out for safety)...');

  // Reboot the light (it will restart and reconnect)
  // await light.reboot();

  // Factory reset (WARNING: removes WiFi settings!)
  // await light.reset();

  // Clear cached configuration
  light.clearCache();

  // ==========================================================================
  // Cleanup
  // ==========================================================================
  print('\nTurning light off...');
  await light.turnOff();

  // Disable logging
  WizLogger.disable();

  print('\nDone!');
}

/// Describes the current mode of a light based on its state.
String _describeMode(LightState state) {
  if (state.isSceneMode) return 'Scene (${state.scene?.displayName})';
  if (state.isRgbMode) return 'RGB (${state.r}, ${state.g}, ${state.b})';
  if (state.isTemperatureMode) return 'Temperature (${state.temperature}K)';
  if (state.isWhiteMode) return 'White (CW: ${state.coldWhite}, WW: ${state.warmWhite})';
  return 'Unknown';
}
