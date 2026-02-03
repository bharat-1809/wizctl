// Example: Control WiZ lights with wizctl

import 'package:wizctl/wizctl.dart';

void main() async {
  // ==========================================================================
  // Discovery
  // ==========================================================================
  print('Discovering WiZ lights...\n');

  // Discover lights on network
  final discovered = await WizDiscovery.discover(timeout: Duration(seconds: 5));

  if (discovered.isEmpty) {
    print('No lights found. Check WiFi connection.');
    return;
  }

  print('Found ${discovered.length} light(s):');
  for (final light in discovered) {
    print('  ${light.ip} (${light.mac})');
  }

  // ==========================================================================
  // Individual Light Control
  // ==========================================================================

  // Create a WizLight instance with the first discovered light
  final light = WizLight(discovered.first.ip);

  // Get state
  final state = await light.getState();
  print('\nCurrent state: ${state.isOn ? 'ON' : 'OFF'}, ${state.dimming}%');
  if (state.scene != null) print('Scene: ${state.scene!.displayName}');

  // Basic control
  await light.turnOn();
  await light.setBrightness(75);

  // RGB color
  await light.setColor(255, 100, 50);
  await Future.delayed(Duration(seconds: 2));

  // Color temperature
  await light.setTemperature(3000);
  await Future.delayed(Duration(seconds: 2));

  // ==========================================================================
  // Scenes
  // ==========================================================================

  print('\nApplying scenes...');

  // List some available scenes
  print('Available scenes: ${WizScene.values.take(5).map((s) => s.displayName).join(', ')}...');

  // Apply the Cozy scene
  print('Applying "Cozy" scene...');
  await light.setScene(WizScene.cozy);
  await Future.delayed(Duration(seconds: 2));

  // Apply Sunset scene with custom speed
  print('Applying "Sunset" scene with speed 150...');
  await light.setScene(WizScene.sunset, speed: 150);
  await Future.delayed(Duration(seconds: 2));

  // Combined settings with ControlSignal
  await light.send(ControlSignal(
    state: true,
    dimming: 80,
    r: 200,
    g: 150,
    b: 255,
  ));
  await Future.delayed(Duration(seconds: 2));

  // ==========================================================================
  // Group Control (if multiple lights discovered)
  // ==========================================================================

  if (discovered.length > 1) {
    final lights = discovered.map((d) => WizLight(d.ip)).toList();

    print('\nControlling ${lights.length} lights together...');
    await WizGroup.turnOn(lights);
    await WizGroup.setScene(lights, WizScene.cozy);

    final states = await WizGroup.getStates(lights);
    for (final entry in states.entries) {
      print('  ${entry.key.ip}: ${entry.value?.isOn ?? false ? 'ON' : 'OFF'}');
    }
  }

  // ==========================================================================
  // Error Handling
  // ==========================================================================

  try {
    await light.setBrightness(150); // Invalid
  } on WizArgumentError catch (e) {
    print('\nCaught error: ${e.message}');
  }

  try {
    final fake = WizLight('192.168.1.254', timeout: Duration(seconds: 2));
    await fake.getState();
  } on WizTimeoutError catch (e) {
    print('Timeout: ${e.message}');
  }

  // ==========================================================================
  // Cleanup
  // ==========================================================================

  print('\nTurning light off...');
  await light.turnOff();
}
