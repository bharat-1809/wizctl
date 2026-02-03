import 'package:test/test.dart';
import 'package:wizctl/wizctl.dart';

void main() {
  group('WizScene', () {
    test('has correct number of scenes', () {
      expect(WizScene.values.length, equals(36)); // 35 + rhythm
    });

    test('has unique IDs', () {
      final ids = WizScene.values.map((s) => s.id).toSet();
      expect(ids.length, equals(WizScene.values.length));
    });

    test('fromId returns correct scene', () {
      expect(WizScene.fromId(1), equals(WizScene.ocean));
      expect(WizScene.fromId(6), equals(WizScene.cozy));
      expect(WizScene.fromId(32), equals(WizScene.steampunk));
      expect(WizScene.fromId(33), equals(WizScene.diwali));
      expect(WizScene.fromId(35), equals(WizScene.alarm));
      expect(WizScene.fromId(1000), equals(WizScene.rhythm));
    });

    test('fromId returns null for invalid ID', () {
      expect(WizScene.fromId(0), isNull);
      expect(WizScene.fromId(36), isNull);
      expect(WizScene.fromId(-1), isNull);
    });

    test('fromName is case-insensitive', () {
      expect(WizScene.fromName('ocean'), equals(WizScene.ocean));
      expect(WizScene.fromName('OCEAN'), equals(WizScene.ocean));
      expect(WizScene.fromName('Ocean'), equals(WizScene.ocean));
    });

    test('fromName matches display names', () {
      expect(WizScene.fromName('Warm White'), equals(WizScene.warmWhite));
      expect(WizScene.fromName('TV Time'), equals(WizScene.tvTime));
      expect(WizScene.fromName('Golden White'), equals(WizScene.goldenWhite));
    });

    test('fromName returns null for unknown name', () {
      expect(WizScene.fromName('unknown'), isNull);
      expect(WizScene.fromName(''), isNull);
    });

    test('isDynamic is correct for dynamic scenes', () {
      expect(WizScene.ocean.isDynamic, isTrue);
      expect(WizScene.party.isDynamic, isTrue);
      expect(WizScene.rhythm.isDynamic, isTrue);
      expect(WizScene.warmWhite.isDynamic, isFalse);
      expect(WizScene.daylight.isDynamic, isFalse);
    });
  });

  group('LightState', () {
    test('fromJson parses basic state', () {
      final json = {
        'result': {
          'state': true,
          'dimming': 75,
          'mac': 'aabbccddeeff',
        },
      };

      final state = LightState.fromJson(json);

      expect(state.isOn, isTrue);
      expect(state.dimming, equals(75));
      expect(state.brightness, equals(75)); // Alias
      expect(state.mac, equals('aabbccddeeff'));
    });

    test('fromJson parses RGB mode', () {
      final json = {
        'result': {
          'state': true,
          'r': 255,
          'g': 100,
          'b': 50,
          'dimming': 80,
        },
      };

      final state = LightState.fromJson(json);

      expect(state.isRgbMode, isTrue);
      expect(state.r, equals(255));
      expect(state.g, equals(100));
      expect(state.b, equals(50));
    });

    test('fromJson parses temperature mode', () {
      final json = {
        'result': {
          'state': true,
          'temp': 3000,
          'dimming': 60,
        },
      };

      final state = LightState.fromJson(json);

      expect(state.isTemperatureMode, isTrue);
      expect(state.temperature, equals(3000));
    });

    test('fromJson parses scene mode', () {
      final json = {
        'result': {
          'state': true,
          'sceneId': 6,
          'dimming': 100,
        },
      };

      final state = LightState.fromJson(json);

      expect(state.isSceneMode, isTrue);
      expect(state.sceneId, equals(6));
      expect(state.scene, equals(WizScene.cozy));
    });

    test('fromJson parses speed and ratio', () {
      final json = {
        'result': {
          'state': true,
          'sceneId': 1,
          'speed': 150,
          'ratio': 50,
        },
      };

      final state = LightState.fromJson(json);

      expect(state.speed, equals(150));
      expect(state.ratio, equals(50));
    });

    test('handles off state', () {
      final json = {
        'result': {
          'state': false,
        },
      };

      final state = LightState.fromJson(json);

      expect(state.isOn, isFalse);
    });

    test('toJson round-trips correctly', () {
      final original = LightState(
        isOn: true,
        dimming: 75,
        r: 255,
        g: 100,
        b: 50,
        speed: 100,
        mac: 'aabbccddeeff',
      );

      final json = original.toJson();

      expect(json['state'], isTrue);
      expect(json['dimming'], equals(75));
      expect(json['r'], equals(255));
      expect(json['g'], equals(100));
      expect(json['b'], equals(50));
      expect(json['speed'], equals(100));
      expect(json['mac'], equals('aabbccddeeff'));
    });
  });

  group('DiscoveredLight', () {
    test('fromJson parses discovery response', () {
      final json = {
        'result': {
          'mac': 'aabbccddeeff',
          'moduleName': 'ESP01_SHRGB1C_31',
        },
      };

      final light = DiscoveredLight.fromJson(json, '192.168.1.100');

      expect(light.ip, equals('192.168.1.100'));
      expect(light.mac, equals('aabbccddeeff'));
      expect(light.moduleName, equals('ESP01_SHRGB1C_31'));
      expect(light.bulbClass, equals(BulbClass.rgb));
    });

    test('equality based on ip and mac', () {
      final light1 = DiscoveredLight(ip: '192.168.1.100', mac: 'aabbcc');
      final light2 = DiscoveredLight(ip: '192.168.1.100', mac: 'aabbcc');
      final light3 = DiscoveredLight(ip: '192.168.1.101', mac: 'aabbcc');

      expect(light1, equals(light2));
      expect(light1, isNot(equals(light3)));
    });
  });

  group('BulbClass', () {
    test('fromModuleName parses RGB bulb', () {
      expect(BulbClass.fromModuleName('ESP01_SHRGB1C_31'), equals(BulbClass.rgb));
      expect(BulbClass.fromModuleName('ESP01_DHRGB_31'), equals(BulbClass.rgb));
    });

    test('fromModuleName parses TW bulb', () {
      expect(BulbClass.fromModuleName('ESP01_SHTW1C_31'), equals(BulbClass.tw));
    });

    test('fromModuleName parses DW bulb', () {
      expect(BulbClass.fromModuleName('ESP01_SHDW1C_31'), equals(BulbClass.dw));
    });

    test('fromModuleName parses socket', () {
      expect(BulbClass.fromModuleName('ESP03_SOCKET_01'), equals(BulbClass.socket));
    });

    test('fromModuleName parses fan dimmer', () {
      expect(BulbClass.fromModuleName('ESP14_FANDIM_01'), equals(BulbClass.fanDim));
    });

    test('fromModuleName returns null for unknown', () {
      expect(BulbClass.fromModuleName('UNKNOWN_MODULE'), isNull);
      expect(BulbClass.fromModuleName(null), isNull);
    });

    test('capabilities are correct', () {
      expect(BulbClass.rgb.supportsColor, isTrue);
      expect(BulbClass.rgb.supportsTemperature, isTrue);
      expect(BulbClass.tw.supportsColor, isFalse);
      expect(BulbClass.tw.supportsTemperature, isTrue);
      expect(BulbClass.socket.supportsBrightness, isFalse);
    });
  });

  group('KelvinRange', () {
    test('standard range', () {
      expect(KelvinRange.standard.min, equals(2200));
      expect(KelvinRange.standard.max, equals(6500));
    });

    test('contains checks correctly', () {
      expect(KelvinRange.standard.contains(3000), isTrue);
      expect(KelvinRange.standard.contains(1000), isFalse);
      expect(KelvinRange.standard.contains(7000), isFalse);
    });

    test('clamp works correctly', () {
      expect(KelvinRange.standard.clamp(3000), equals(3000));
      expect(KelvinRange.standard.clamp(1000), equals(2200));
      expect(KelvinRange.standard.clamp(8000), equals(6500));
    });
  });

  group('ControlSignal', () {
    test('basic state pilot', () {
      final pilot = ControlSignal(state: true);
      final json = pilot.toJson();

      expect(json, equals({'state': true}));
    });

    test('brightness pilot', () {
      final pilot = ControlSignal(dimming: 75);
      final json = pilot.toJson();

      expect(json, equals({'dimming': 75}));
    });

    test('RGB pilot', () {
      final pilot = ControlSignal(r: 255, g: 100, b: 50, dimming: 80);
      final json = pilot.toJson();

      expect(json, equals({'r': 255, 'g': 100, 'b': 50, 'dimming': 80}));
    });

    test('temperature pilot', () {
      final pilot = ControlSignal(temperature: 3000);
      final json = pilot.toJson();

      expect(json, equals({'temp': 3000}));
    });

    test('scene pilot with speed', () {
      final pilot = ControlSignal(sceneId: 6, speed: 150);
      final json = pilot.toJson();

      expect(json, equals({'sceneId': 6, 'speed': 150}));
    });

    test('factory constructors', () {
      expect(ControlSignal.on().toJson(), equals({'state': true}));
      expect(ControlSignal.off().toJson(), equals({'state': false}));
      expect(ControlSignal.brightness(50).toJson(), equals({'dimming': 50}));
      expect(ControlSignal.rgb(255, 0, 0).toJson(), equals({'r': 255, 'g': 0, 'b': 0}));
      expect(ControlSignal.temperature(4000).toJson(), equals({'temp': 4000}));
      expect(ControlSignal.scene(WizScene.cozy).toJson(), equals({'sceneId': 6}));
      expect(ControlSignal.warmWhite(128).toJson(), equals({'w': 128}));
      expect(ControlSignal.coldWhite(128).toJson(), equals({'c': 128}));
      expect(ControlSignal.speed(150).toJson(), equals({'speed': 150}));
    });

    test('toMessage includes method', () {
      final pilot = ControlSignal(state: true);
      final message = pilot.toMessage();

      expect(message['method'], equals('setPilot'));
      expect(message['params'], equals({'state': true}));
    });

    test('validates brightness range', () {
      expect(() => ControlSignal(dimming: 5), throwsA(isA<WizArgumentError>()));
      expect(() => ControlSignal(dimming: 101), throwsA(isA<WizArgumentError>()));
      expect(() => ControlSignal(dimming: 10), returnsNormally);
      expect(() => ControlSignal(dimming: 100), returnsNormally);
    });

    test('validates RGB range', () {
      expect(() => ControlSignal(r: -1, g: 0, b: 0), throwsA(isA<WizArgumentError>()));
      expect(() => ControlSignal(r: 0, g: 256, b: 0), throwsA(isA<WizArgumentError>()));
      expect(() => ControlSignal(r: 0, g: 0, b: 300), throwsA(isA<WizArgumentError>()));
    });

    test('validates temperature range', () {
      expect(() => ControlSignal(temperature: 500), throwsA(isA<WizArgumentError>()));
      expect(() => ControlSignal(temperature: 15000), throwsA(isA<WizArgumentError>()));
      expect(() => ControlSignal(temperature: 2200), returnsNormally);
      expect(() => ControlSignal(temperature: 6500), returnsNormally);
    });

    test('validates scene ID range', () {
      expect(() => ControlSignal(sceneId: 0), throwsA(isA<WizArgumentError>()));
      expect(() => ControlSignal(sceneId: 36), throwsA(isA<WizArgumentError>()));
      expect(() => ControlSignal(sceneId: 1), returnsNormally);
      expect(() => ControlSignal(sceneId: 35), returnsNormally);
      expect(() => ControlSignal(sceneId: 1000), returnsNormally); // rhythm
    });

    test('validates speed range', () {
      expect(() => ControlSignal(speed: 5), throwsA(isA<WizArgumentError>()));
      expect(() => ControlSignal(speed: 250), throwsA(isA<WizArgumentError>()));
      expect(() => ControlSignal(speed: 10), returnsNormally);
      expect(() => ControlSignal(speed: 200), returnsNormally);
    });
  });

  group('WizLight', () {
    test('creates with default port and timeout', () {
      final light = WizLight('192.168.1.100');

      expect(light.ip, equals('192.168.1.100'));
      expect(light.port, equals(wizPort));
      expect(light.timeout, equals(defaultTimeout));
    });

    test('creates with custom port and timeout', () {
      final light = WizLight(
        '192.168.1.100',
        port: 12345,
        timeout: Duration(seconds: 5),
      );

      expect(light.port, equals(12345));
      expect(light.timeout, equals(Duration(seconds: 5)));
    });

    test('equality based on ip and port', () {
      final light1 = WizLight('192.168.1.100');
      final light2 = WizLight('192.168.1.100');
      final light3 = WizLight('192.168.1.101');
      final light4 = WizLight('192.168.1.100', port: 12345);

      expect(light1, equals(light2));
      expect(light1, isNot(equals(light3)));
      expect(light1, isNot(equals(light4)));
    });

    test('validates brightness in setBrightness', () {
      final light = WizLight('192.168.1.100');

      expect(
        () => light.setBrightness(5),
        throwsA(isA<WizArgumentError>()),
      );
      expect(
        () => light.setBrightness(101),
        throwsA(isA<WizArgumentError>()),
      );
    });

    test('validates temperature in setTemperature', () {
      final light = WizLight('192.168.1.100');

      expect(
        () => light.setTemperature(500),
        throwsA(isA<WizArgumentError>()),
      );
      expect(
        () => light.setTemperature(15000),
        throwsA(isA<WizArgumentError>()),
      );
    });

    test('validates speed in setSpeed', () {
      final light = WizLight('192.168.1.100');

      expect(
        () => light.setSpeed(5),
        throwsA(isA<WizArgumentError>()),
      );
      expect(
        () => light.setSpeed(250),
        throwsA(isA<WizArgumentError>()),
      );
    });
  });

  group('Exceptions', () {
    test('WizTimeoutError has correct message', () {
      final exception = WizTimeoutError(
        ip: '192.168.1.100',
        timeout: Duration(seconds: 13),
        retryCount: 6,
      );

      expect(exception.ip, equals('192.168.1.100'));
      expect(exception.timeout, equals(Duration(seconds: 13)));
      expect(exception.retryCount, equals(6));
      expect(exception.message, contains('192.168.1.100'));
      expect(exception.message, contains('6 attempts'));
    });

    test('WizConnectionError includes cause', () {
      final cause = Exception('Socket error');
      final exception = WizConnectionError('Failed to connect', cause);

      expect(exception.message, equals('Failed to connect'));
      expect(exception.cause, equals(cause));
      expect(exception.toString(), contains('Socket error'));
    });

    test('WizResponseError includes raw response', () {
      final exception = WizResponseError(
        'Invalid JSON',
        rawResponse: 'not json',
        errorCode: -32600,
      );

      expect(exception.rawResponse, equals('not json'));
      expect(exception.errorCode, equals(-32600));
      expect(exception.toString(), contains('not json'));
    });

    test('WizArgumentError includes details', () {
      final exception = WizArgumentError(
        argumentName: 'brightness',
        invalidValue: 150,
        message: 'Value out of range',
      );

      expect(exception.argumentName, equals('brightness'));
      expect(exception.invalidValue, equals(150));
      expect(exception.toString(), contains('brightness'));
      expect(exception.toString(), contains('150'));
    });

    test('WizMethodNotFoundError', () {
      final exception = WizMethodNotFoundError(
        method: 'getModelConfig',
        ip: '192.168.1.100',
      );

      expect(exception.method, equals('getModelConfig'));
      expect(exception.ip, equals('192.168.1.100'));
      expect(exception.toString(), contains('getModelConfig'));
    });

    test('WizUnknownBulbError', () {
      final exception = WizUnknownBulbError(
        ip: '192.168.1.100',
        moduleName: 'UNKNOWN_TYPE',
      );

      expect(exception.ip, equals('192.168.1.100'));
      expect(exception.moduleName, equals('UNKNOWN_TYPE'));
      expect(exception.toString(), contains('UNKNOWN_TYPE'));
    });
  });

  group('GroupOperationResult', () {
    test('success result', () {
      final light = WizLight('192.168.1.100');
      final result = GroupOperationResult(light: light, success: true);

      expect(result.success, isTrue);
      expect(result.error, isNull);
      expect(result.toString(), contains('success'));
    });

    test('failure result', () {
      final light = WizLight('192.168.1.100');
      final error = WizTimeoutError(
        ip: '192.168.1.100',
        timeout: Duration(seconds: 13),
      );
      final result = GroupOperationResult(
        light: light,
        success: false,
        error: error,
      );

      expect(result.success, isFalse);
      expect(result.error, equals(error));
      expect(result.toString(), contains('failed'));
    });
  });

  group('RetryStrategy', () {
    test('has correct values', () {
      expect(RetryStrategy.values.length, equals(2));
      expect(RetryStrategy.values, contains(RetryStrategy.fixed));
      expect(RetryStrategy.values, contains(RetryStrategy.exponential));
    });
  });

  group('RetryConfig', () {
    test('none() factory creates disabled config', () {
      final config = RetryConfig.none();

      expect(config.count, equals(0));
      expect(config.strategy, equals(RetryStrategy.fixed));
      expect(config.interval, equals(Duration.zero));
      expect(config.maxInterval, isNull);
      expect(config.enabled, isFalse);
    });

    test('fixed() factory creates fixed interval config', () {
      final config = RetryConfig.fixed(
        count: 5,
        interval: Duration(seconds: 1),
      );

      expect(config.count, equals(5));
      expect(config.strategy, equals(RetryStrategy.fixed));
      expect(config.interval, equals(Duration(seconds: 1)));
      expect(config.maxInterval, isNull);
      expect(config.enabled, isTrue);
    });

    test('exponential() factory creates exponential config with default maxInterval', () {
      final config = RetryConfig.exponential(
        count: 5,
        initialInterval: Duration(milliseconds: 500),
      );

      expect(config.count, equals(5));
      expect(config.strategy, equals(RetryStrategy.exponential));
      expect(config.interval, equals(Duration(milliseconds: 500)));
      expect(config.maxInterval, equals(Duration(seconds: 3)));
      expect(config.enabled, isTrue);
    });

    test('exponential() factory creates exponential config with custom maxInterval', () {
      final config = RetryConfig.exponential(
        count: 3,
        initialInterval: Duration(milliseconds: 250),
        maxInterval: Duration(seconds: 2),
      );

      expect(config.count, equals(3));
      expect(config.strategy, equals(RetryStrategy.exponential));
      expect(config.interval, equals(Duration(milliseconds: 250)));
      expect(config.maxInterval, equals(Duration(seconds: 2)));
    });

    test('enabled returns true when count > 0', () {
      expect(RetryConfig.none().enabled, isFalse);
      expect(RetryConfig.fixed(count: 1, interval: Duration(seconds: 1)).enabled, isTrue);
      expect(RetryConfig.fixed(count: 0, interval: Duration(seconds: 1)).enabled, isFalse);
    });

    test('nextExponentialInterval doubles interval for exponential strategy', () {
      final config = RetryConfig.exponential(
        count: 5,
        initialInterval: Duration(milliseconds: 500),
        maxInterval: Duration(seconds: 5),
      );

      var current = config.interval;
      expect(current, equals(Duration(milliseconds: 500)));

      current = config.nextExponentialInterval(current);
      expect(current, equals(Duration(milliseconds: 1000)));

      current = config.nextExponentialInterval(current);
      expect(current, equals(Duration(milliseconds: 2000)));

      current = config.nextExponentialInterval(current);
      expect(current, equals(Duration(milliseconds: 4000)));

      current = config.nextExponentialInterval(current);
      expect(current, equals(Duration(milliseconds: 5000))); // Capped at maxInterval
    });

    test('nextExponentialInterval respects maxInterval cap', () {
      final config = RetryConfig.exponential(
        count: 5,
        initialInterval: Duration(milliseconds: 1000),
        maxInterval: Duration(milliseconds: 2000),
      );

      var current = Duration(milliseconds: 1000);
      current = config.nextExponentialInterval(current);
      expect(current, equals(Duration(milliseconds: 2000)));

      // Should stay at maxInterval
      current = config.nextExponentialInterval(current);
      expect(current, equals(Duration(milliseconds: 2000)));
    });

    test('nextExponentialInterval returns interval for fixed strategy', () {
      final config = RetryConfig.fixed(
        count: 5,
        interval: Duration(seconds: 2),
      );

      final result = config.nextExponentialInterval(Duration(seconds: 5));
      // Should return the fixed interval, not the current interval
      expect(result, equals(Duration(seconds: 2)));
    });

    test('nextExponentialInterval handles zero maxInterval', () {
      final config = RetryConfig.exponential(
        count: 5,
        initialInterval: Duration(milliseconds: 100),
        maxInterval: Duration.zero,
      );

      var current = Duration(milliseconds: 100);
      current = config.nextExponentialInterval(current);
      // Should be clamped to 0
      expect(current, equals(Duration.zero));
    });

    test('nextExponentialInterval handles very large intervals', () {
      final config = RetryConfig.exponential(
        count: 5,
        initialInterval: Duration(milliseconds: 1000),
        maxInterval: Duration(seconds: 10),
      );

      var current = Duration(seconds: 5);
      current = config.nextExponentialInterval(current);
      expect(current, equals(Duration(seconds: 10))); // Capped at maxInterval
    });

    test('constructor validates count is non-negative', () {
      // This test verifies the assert in the constructor
      // Note: In release mode, asserts are disabled, so this might not throw
      expect(
        () => RetryConfig(
          count: -1,
          strategy: RetryStrategy.fixed,
          interval: Duration(seconds: 1),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('factory constructors create distinct instances', () {
      final config1 = RetryConfig.fixed(count: 5, interval: Duration(seconds: 1));
      final config2 = RetryConfig.fixed(count: 5, interval: Duration(seconds: 1));
      final config3 = RetryConfig.fixed(count: 3, interval: Duration(seconds: 1));
      final config4 = RetryConfig.exponential(
        count: 5,
        initialInterval: Duration(seconds: 1),
      );

      // Verify properties are set correctly
      expect(config1.count, equals(config2.count));
      expect(config1.strategy, equals(config2.strategy));
      expect(config1.interval, equals(config2.interval));
      expect(config1.count, isNot(equals(config3.count)));
      expect(config1.strategy, isNot(equals(config4.strategy)));
    });

    test('exponential config properties are set correctly', () {
      final config1 = RetryConfig.exponential(
        count: 5,
        initialInterval: Duration(milliseconds: 500),
        maxInterval: Duration(seconds: 3),
      );
      final config2 = RetryConfig.exponential(
        count: 5,
        initialInterval: Duration(milliseconds: 500),
        maxInterval: Duration(seconds: 3),
      );

      expect(config1.count, equals(config2.count));
      expect(config1.strategy, equals(config2.strategy));
      expect(config1.interval, equals(config2.interval));
      expect(config1.maxInterval, equals(config2.maxInterval));
    });

    test('exponential config with different maxInterval have different properties', () {
      final config1 = RetryConfig.exponential(
        count: 5,
        initialInterval: Duration(milliseconds: 500),
        maxInterval: Duration(seconds: 2),
      );
      final config2 = RetryConfig.exponential(
        count: 5,
        initialInterval: Duration(milliseconds: 500),
        maxInterval: Duration(seconds: 3),
      );

      expect(config1.count, equals(config2.count));
      expect(config1.interval, equals(config2.interval));
      expect(config1.maxInterval, isNot(equals(config2.maxInterval)));
    });
  });
}
