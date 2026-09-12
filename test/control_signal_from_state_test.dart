import 'package:test/test.dart';
import 'package:wizctl/wizctl.dart';

void main() {
  group('ControlSignal.fromState', () {
    test('restores a scene with its speed and brightness', () {
      var signal = ControlSignal.fromState(
        const LightState(isOn: true, dimming: 80, sceneId: 6, speed: 120),
      );
      expect(signal.toJson(), {
        keyState: true,
        keyDimming: 80,
        keySceneId: 6,
        keySpeed: 120,
      });
    });

    test('a scene wins over colour and temperature values also present', () {
      // Bulbs report the last colour alongside an active scene.
      var signal = ControlSignal.fromState(
        const LightState(
          isOn: true,
          dimming: 50,
          sceneId: 1,
          r: 255,
          g: 0,
          b: 0,
          temperature: 2700,
        ),
      );
      expect(signal.toJson(), {keyState: true, keyDimming: 50, keySceneId: 1});
    });

    test('restores a colour temperature', () {
      var signal = ControlSignal.fromState(
        const LightState(isOn: true, dimming: 70, temperature: 2700),
      );
      expect(signal.toJson(), {
        keyState: true,
        keyDimming: 70,
        keyTemperature: 2700,
      });
    });

    test('restores an rgb colour with its white channels', () {
      var signal = ControlSignal.fromState(
        const LightState(
          isOn: true,
          dimming: 40,
          r: 255,
          g: 120,
          b: 60,
          coldWhite: 0,
          warmWhite: 30,
        ),
      );
      expect(signal.toJson(), {
        keyState: true,
        keyDimming: 40,
        keyRed: 255,
        keyGreen: 120,
        keyBlue: 60,
        keyColdWhite: 0,
        keyWarmWhite: 30,
      });
    });

    test('restores bare white channels', () {
      var signal = ControlSignal.fromState(
        const LightState(isOn: true, warmWhite: 200),
      );
      expect(signal.toJson(), {keyState: true, keyWarmWhite: 200});
    });

    test('an off light restores as off with its channel', () {
      var signal = ControlSignal.fromState(
        const LightState(isOn: false, dimming: 30, temperature: 4000),
      );
      expect(signal.state, isFalse);
      expect(signal.temperature, 4000);
    });

    test('scene id 0 means no scene', () {
      var signal = ControlSignal.fromState(
        const LightState(isOn: true, sceneId: 0, temperature: 3000),
      );
      expect(signal.sceneId, isNull);
      expect(signal.temperature, 3000);
    });

    test('an unknown scene id is ignored', () {
      var signal = ControlSignal.fromState(
        const LightState(
          isOn: true,
          dimming: 50,
          sceneId: 77,
          temperature: 3000,
        ),
      );
      expect(signal.sceneId, isNull);
      expect(signal.temperature, 3000);
    });

    test('never throws for out-of-range values a bulb reported', () {
      var signal = ControlSignal.fromState(
        const LightState(
          isOn: true,
          dimming: 5,
          sceneId: 4,
          speed: 500,
          temperature: 20000,
        ),
      );
      expect(signal.dimming, minBrightness);
      expect(signal.speed, maxSpeed);
    });

    test('drops an unsupported temperature instead of throwing', () {
      var signal = ControlSignal.fromState(
        const LightState(isOn: true, temperature: 20000, r: 1, g: 2, b: 3),
      );
      expect(signal.temperature, isNull);
      expect(signal.r, 1);
    });

    test('a state with no channel restores power and brightness only', () {
      var signal = ControlSignal.fromState(
        const LightState(isOn: true, dimming: 100),
      );
      expect(signal.toJson(), {keyState: true, keyDimming: 100});
    });
  });
}
