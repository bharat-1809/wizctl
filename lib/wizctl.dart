/// Control Philips WiZ smart lights
///
/// ```dart
/// import 'package:wizctl/wizctl.dart';
///
/// // Enable debug logging to see UDP packets
/// WizLogger.enable(WizLogLevel.debug);
///
/// // Discover lights
/// final discovered = await WizDiscovery.discover();
///
/// // Control a light
/// final light = WizLight('192.168.1.100');
/// await light.turnOn();
/// await light.setColor(255, 100, 50);
/// await light.setScene(WizScene.cozy);
///
/// // Group control
/// final lights = [WizLight('192.168.1.100'), WizLight('192.168.1.101')];
/// await WizGroup.turnOn(lights);
/// ```
library;

export 'src/bulb_type.dart' show BulbClass, KelvinRange;
export 'src/constants.dart';
export 'src/discovery.dart' show WizDiscovery;
export 'src/exceptions.dart';
export 'src/group.dart' show WizGroup, GroupOperationResult;
export 'src/light.dart' show WizLight;
export 'src/logging.dart' show WizLogger, WizLogLevel, WizLogCallback;
export 'src/retry_config.dart' show RetryConfig, RetryStrategy;
export 'src/control_signal.dart' show ControlSignal;
export 'src/scene.dart' show WizScene;
export 'src/state.dart' show LightState, DiscoveredLight, BulbConfig;
