enum WizLogLevel { none, error, warn, info, debug, verbose }

typedef WizLogCallback = void Function(WizLogLevel level, String message);

/// Configure logging
///
/// ```dart
/// WizLogger.enable(WizLogLevel.debug);
/// await light.turnOn(); // Now shows UDP packets
/// ```
class WizLogger {
  WizLogger._();

  static WizLogLevel _level = WizLogLevel.none;
  static WizLogCallback? _callback;

  static void enable(WizLogLevel level, {WizLogCallback? callback}) {
    _level = level;
    _callback = callback;
  }

  static void disable() {
    _level = WizLogLevel.none;
    _callback = null;
  }

  static void log(WizLogLevel level, String message) {
    if (level.index > _level.index || _level == WizLogLevel.none) return;

    if (_callback != null) {
      _callback!(level, message);
    } else {
      final prefix = switch (level) {
        WizLogLevel.error => '[ERROR]',
        WizLogLevel.warn => '[WARN] ',
        WizLogLevel.info => '[INFO] ',
        WizLogLevel.debug => '[DEBUG]',
        WizLogLevel.verbose => '[TRACE]',
        WizLogLevel.none => '',
      };
      final timestamp = DateTime.now().toIso8601String().substring(11, 23);
      print('[$timestamp] $prefix $message');
    }
  }

  static void error(String message) => log(WizLogLevel.error, message);
  static void warn(String message) => log(WizLogLevel.warn, message);
  static void info(String message) => log(WizLogLevel.info, message);
  static void debug(String message) => log(WizLogLevel.debug, message);
  static void verbose(String message) => log(WizLogLevel.verbose, message);
}
