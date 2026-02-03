/// Base class for all WiZ errors.
sealed class WizException implements Exception {
  String get message;
  Object? get cause;
}

/// Network or socket error.
class WizConnectionError extends WizException {
  @override
  final String message;
  @override
  final Object? cause;

  WizConnectionError(this.message, [this.cause]);

  @override
  String toString() => cause != null
      ? 'WizConnectionError: $message (caused by: $cause)'
      : 'WizConnectionError: $message';
}

/// Light didn't respond after all retries.
class WizTimeoutError extends WizException {
  final String ip;
  final Duration timeout;
  final int retryCount;

  @override
  String get message =>
      'Light at $ip did not respond after $retryCount attempts (${timeout.inSeconds}s timeout)';
  @override
  Object? get cause => null;

  WizTimeoutError({
    required this.ip,
    required this.timeout,
    this.retryCount = 0,
  });

  @override
  String toString() => 'WizTimeoutError: $message';
}

/// Method not supported by light firmware.
class WizMethodNotFoundError extends WizException {
  final String method;
  final String ip;

  @override
  String get message => 'Method "$method" not supported by light at $ip';
  @override
  Object? get cause => null;

  WizMethodNotFoundError({required this.method, required this.ip});

  @override
  String toString() => 'WizMethodNotFoundError: $message';
}

/// Invalid or unexpected response from light.
class WizResponseError extends WizException {
  @override
  final String message;
  final String? rawResponse;
  final int? errorCode;
  @override
  final Object? cause;

  WizResponseError(this.message,
      {this.rawResponse, this.errorCode, this.cause});

  @override
  String toString() {
    var parts = <String>['WizResponseError: $message'];
    if (errorCode != null) parts.add('(code: $errorCode)');
    if (rawResponse != null) parts.add('(response: $rawResponse)');
    return parts.join(' ');
  }
}

/// Cannot determine bulb type from module name.
class WizUnknownBulbError extends WizException {
  final String? moduleName;
  final String ip;

  @override
  String get message =>
      'Cannot determine bulb type for light at $ip${moduleName != null ? ' (module: $moduleName)' : ''}';
  @override
  Object? get cause => null;

  WizUnknownBulbError({required this.ip, this.moduleName});

  @override
  String toString() => 'WizUnknownBulbError: $message';
}

/// Invalid argument passed to a WiZ operation.
class WizArgumentError extends WizException {
  final String argumentName;
  final Object? invalidValue;
  @override
  final String message;
  @override
  Object? get cause => null;

  WizArgumentError({
    required this.argumentName,
    required this.invalidValue,
    required this.message,
  });

  @override
  String toString() =>
      'WizArgumentError: $message (argument: $argumentName, value: $invalidValue)';
}
