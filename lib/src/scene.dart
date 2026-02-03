/// All built-in WiZ light scenes.
///
/// Each scene has a unique [id] that is sent to the light and a readable
/// [displayName].
///
/// Example:
/// ```dart
/// await light.setScene(WizScene.cozy);
/// print(WizScene.cozy.displayName); // "Cozy"
/// ```
enum WizScene {
  ocean(1, 'Ocean'),
  romance(2, 'Romance'),
  sunset(3, 'Sunset'),
  party(4, 'Party'),
  fireplace(5, 'Fireplace'),
  cozy(6, 'Cozy'),
  forest(7, 'Forest'),
  pastelColors(8, 'Pastel Colors'),
  wakeUp(9, 'Wake Up'),
  bedtime(10, 'Bedtime'),
  warmWhite(11, 'Warm White'),
  daylight(12, 'Daylight'),
  coolWhite(13, 'Cool White'),
  nightLight(14, 'Night Light'),
  focus(15, 'Focus'),
  relax(16, 'Relax'),
  trueColors(17, 'True Colors'),
  tvTime(18, 'TV Time'),
  plantGrowth(19, 'Plant Growth'),
  spring(20, 'Spring'),
  summer(21, 'Summer'),
  fall(22, 'Fall'),
  deepDive(23, 'Deep Dive'),
  jungle(24, 'Jungle'),
  mojito(25, 'Mojito'),
  club(26, 'Club'),
  christmas(27, 'Christmas'),
  halloween(28, 'Halloween'),
  candlelight(29, 'Candlelight'),
  goldenWhite(30, 'Golden White'),
  pulse(31, 'Pulse'),
  steampunk(32, 'Steampunk'),
  diwali(33, 'Diwali'),
  white(34, 'White'),
  alarm(35, 'Alarm'),
  rhythm(1000, 'Rhythm');

  final int id;
  final String displayName;

  const WizScene(this.id, this.displayName);

  /// Animated scenes that support speed control.
  bool get isDynamic => switch (this) {
        ocean || romance || sunset || party || fireplace || forest ||
        pastelColors || wakeUp || bedtime || spring || summer || fall ||
        deepDive || jungle || mojito || club || christmas || halloween ||
        candlelight || pulse || diwali || alarm || rhythm => true,
        _ => false,
      };

  /// Whether this scene supports speed adjustment.
  bool get supportsSpeed => isDynamic;

  /// Find a scene by its ID.
  ///
  /// Returns `null` if no scene matches the given ID.
  static WizScene? fromId(int id) {
    for (final scene in values) {
      if (scene.id == id) return scene;
    }
    return null;
  }

  /// Find a scene by its name (case-insensitive).
  ///
  /// Matches against both the enum name and displayName.
  /// Returns `null` if no scene matches.
  static WizScene? fromName(String name) {
    final lower = name.toLowerCase().replaceAll(' ', '').replaceAll('_', '');
    for (final scene in values) {
      final enumName = scene.name.toLowerCase();
      final displayLower = scene.displayName.toLowerCase().replaceAll(' ', '');
      if (enumName == lower || displayLower == lower) return scene;
    }
    return null;
  }

  @override
  String toString() => displayName;
}
