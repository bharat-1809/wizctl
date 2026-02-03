// =============================================================================
// Network Configuration
// =============================================================================

/// Default UDP port for WiZ light communication.
const int wizPort = 38899;

/// Default timeout for UDP operations (per-attempt timeout for protocol requests).
///
/// This timeout applies to each individual retry attempt in [WizProtocol.send].
/// Each attempt waits for this full duration before timing out and retrying.
/// Total operation time = timeout * (attempts) + retry_intervals.
const Duration defaultTimeout = Duration(seconds: 3);

/// Default timeout for discovery operations (total timeout window).
///
/// This is a total timeout window for [WizDiscovery.discover]. All broadcasts
/// (initial + retries) happen within this window, and responses are collected
/// continuously throughout the period.
const Duration defaultDiscoveryTimeout = Duration(seconds: 10);

// =============================================================================
// Retry Configuration
// =============================================================================

/// Maximum number of retry attempts for UDP operations.
const int maxSendDatagrams = 6;

/// Initial delay between retries.
const Duration firstSendInterval = Duration(milliseconds: 750);

/// Maximum delay between retries (backoff caps at this value).
const Duration maxBackoff = Duration(seconds: 3);

// =============================================================================
// Protocol Constants
// =============================================================================

/// Method name for getting light state.
const String methodGetPilot = 'getPilot';

/// Method name for setting light state.
const String methodSetPilot = 'setPilot';

/// Method name for device registration/discovery.
const String methodRegistration = 'registration';

/// Method name for getting system configuration.
const String methodGetSystemConfig = 'getSystemConfig';

/// Method name for getting user configuration.
const String methodGetUserConfig = 'getUserConfig';

/// Method name for getting model configuration.
const String methodGetModelConfig = 'getModelConfig';

/// Method name for rebooting the bulb.
const String methodReboot = 'reboot';

/// Method name for factory reset.
const String methodReset = 'reset';

// =============================================================================
// Protocol Parameter Keys
// =============================================================================

/// JSON key for the method field.
const String keyMethod = 'method';

/// JSON key for the params field.
const String keyParams = 'params';
const String keyResult = 'result';
const String keyError = 'error';
const String keyCode = 'code';
const String keyState = 'state';
const String keyDimming = 'dimming';
const String keyRed = 'r';
const String keyGreen = 'g';
const String keyBlue = 'b';
const String keyColdWhite = 'c';
const String keyWarmWhite = 'w';
const String keyTemperature = 'temp';
const String keySceneId = 'sceneId';
const String keySpeed = 'speed';
const String keyRatio = 'ratio';
const String keyMac = 'mac';
const String keyRssi = 'rssi';
const String keyModuleName = 'moduleName';
const String keyFwVersion = 'fwVersion';
const String keyTypeId = 'typeId';
const String keyKelvinRange = 'kelvinRange';
const String keyExtRange = 'extRange';
const String keyWhiteRange = 'whiteRange';
const String keySource = 'src';

// =============================================================================
// Error Codes
// =============================================================================

/// Error code for method not found.
const int errorCodeMethodNotFound = -32601;

// =============================================================================
// Discovery Parameters
// =============================================================================

/// Fake phone MAC address used in discovery registration.
const String discoveryPhoneMac = 'AAAAAAAAAAAA';

/// Fake phone IP used in discovery registration.
const String discoveryPhoneIp = '1.2.3.4';

/// Default broadcast address for discovery.
const String defaultBroadcastAddress = '255.255.255.255';
const Duration discoveryBroadcastInterval = Duration(seconds: 1);

// =============================================================================
// Validation Limits
// =============================================================================

/// Minimum brightness level (WiZ lights don't go below 10%).
const int minBrightness = 10;

/// Maximum brightness level.
const int maxBrightness = 100;
const int minColorValue = 0;
const int maxColorValue = 255;
const int minTemperature = 1000;
const int maxTemperature = 10000;
const int typicalMinTemperature = 2200;
const int typicalMaxTemperature = 6500;
const int minSceneId = 1;
const int maxSceneId = 35;
const int rhythmSceneId = 1000;
const int minSpeed = 10;
const int maxSpeed = 200;
const int defaultSpeed = 100;

// =============================================================================
// Error Messages
// =============================================================================

/// Error message for brightness out of range.
const String errorBrightnessRange =
    'Brightness must be between $minBrightness and $maxBrightness';

/// Error message for red value out of range.
const String errorRedRange =
    'Red value must be between $minColorValue and $maxColorValue';
const String errorGreenRange =
    'Green value must be between $minColorValue and $maxColorValue';
const String errorBlueRange =
    'Blue value must be between $minColorValue and $maxColorValue';
const String errorTemperatureRange =
    'Color temperature must be between ${minTemperature}K and ${maxTemperature}K';
const String errorSceneIdRange =
    'Scene ID must be between $minSceneId and $maxSceneId';
const String errorSpeedRange = 'Speed must be between $minSpeed and $maxSpeed';
const String errorWhiteRange =
    'White value must be between $minColorValue and $maxColorValue';

// =============================================================================
// CLI Constants
// =============================================================================

/// CLI tool version.
const String cliVersion = '0.1.0';

/// CLI tool name.
const String cliName = 'wizctl';
const int cliDefaultDiscoveryTimeoutSeconds = 5;
const String configDirName = 'wizctl';
const String configFileName = 'config.json';
