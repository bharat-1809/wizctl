import 'dart:io';

import 'package:test/test.dart';
import 'package:wizctl/wizctl.dart';

void main() {
  group('version', () {
    test('cliVersion matches the version in pubspec.yaml', () {
      // These drifted apart once already: the package was at 1.0.0 while
      // `wizctl --version` still reported 0.1.0. Nothing else checks them
      // against each other, so this test is the only thing that will.
      var pubspec = File('pubspec.yaml').readAsStringSync();
      var match = RegExp(
        r'^version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(pubspec);

      expect(match, isNotNull, reason: 'pubspec.yaml has no version field');
      expect(
        cliVersion,
        match!.group(1),
        reason:
            'Update cliVersion in lib/src/constants.dart to match '
            'the version in pubspec.yaml',
      );
    });

    test('the changelog documents the version being released', () {
      // pub.dev renders CHANGELOG.md as-is, so a leftover "Unreleased" heading
      // ships to the package page.
      var changelog = File('CHANGELOG.md').readAsStringSync();
      var headings = RegExp(
        r'^##\s+(.+)$',
        multiLine: true,
      ).allMatches(changelog).map((m) => m.group(1)!.trim()).toList();

      expect(headings, isNotEmpty, reason: 'CHANGELOG.md has no headings');
      expect(
        headings.any((h) => h.startsWith(cliVersion)),
        isTrue,
        reason: 'CHANGELOG.md has no entry for $cliVersion (found: $headings)',
      );
    });
  });
}
