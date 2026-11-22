import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:home_canvas/dashboard/dashboard_theme.dart';

/// WCAG contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Every colour a tile can end up behind its text: the surface over each
/// background colour, over the glows, and under the sheen at its top.
List<Color> tileColours(DashboardTheme t) {
  final grounds = [
    ...t.background,
    if (t.glow != null) Color.alphaBlend(t.glow!, t.background.first),
    if (t.glowEnd != null) Color.alphaBlend(t.glowEnd!, t.background.first),
  ];
  return [
    for (final g in grounds) ...[
      Color.alphaBlend(t.surface, g),
      if (t.sheen > 0)
        Color.alphaBlend(
          Colors.white.withValues(alpha: t.sheen),
          Color.alphaBlend(t.surface, g),
        ),
    ],
  ];
}

/// The catalogue's themes, as the build copies them for their tests:
/// `test/addons/themes/<theme id>.json`. Read as a panel reads them.
Map<String, Map<String, dynamic>> themeFiles() {
  final dir = Directory('test/addons/themes');
  if (!dir.existsSync()) return const {};
  return {
    for (final f in dir.listSync().whereType<File>())
      if (f.path.endsWith('.json'))
        f.uri.pathSegments.last.replaceFirst(RegExp(r'\.json$'), ''):
            jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
  };
}

void main() {
  final files = themeFiles();

  test('the themes are here to be checked', () {
    if (files.isEmpty) {
      markTestSkipped(
        'Link the catalogue: scripts/widget-build.sh generate '
        'with HOMECANVAS_ADDON_TESTS=1.',
      );
      return;
    }
    expect(files, isNotEmpty);
  });

  // A theme has to be readable, however good it looks: body text at WCAG AA
  // or better, secondary text and the accent at the large-text minimum,
  // since both are used big or as marks on a panel across a room.
  for (final MapEntry(key: file, value: json) in files.entries) {
    final t = DashboardTheme.fromJson(json);
    group('the ${t.name} theme', () {
      test('is named as its file is', () => expect(t.id, file));

      test('keeps its text readable on its tiles', () {
        for (final tile in tileColours(t)) {
          final secondary = Color.alphaBlend(t.textSecondary, tile);
          expect(
            contrast(t.textPrimary, tile),
            greaterThanOrEqualTo(7),
            reason: 'text on $tile',
          );
          expect(
            contrast(secondary, tile),
            greaterThanOrEqualTo(3.5),
            reason: 'secondary text on $tile',
          );
          expect(
            contrast(t.accent, tile),
            greaterThanOrEqualTo(3),
            reason: 'accent on $tile',
          );
        }
      });

      test('reads back as it was written', () {
        final back = DashboardTheme.fromJson(t.toJson());
        expect(back.toJson(), t.toJson());
      });

      if (t.isLcars) {
        test('gives a console colours for its blocks', () {
          expect(t.palette, isNotEmpty);
        });
      }
    });
  }

  test('none takes the name of the app\'s own', () {
    for (final t in kBuiltInThemes) {
      expect(files.keys, isNot(contains(t.id)));
    }
  });
}
