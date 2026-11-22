import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_model.dart';
import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/parcels_view.dart';
import 'package:home_canvas/dashboard/widgets/widgets.dart';
import 'package:home_canvas/l10n/dates.dart';
import 'package:home_canvas/services/parcels_service.dart';
import 'package:home_canvas/services/side_browser.dart';

import '../theme_fixtures.dart';

void main() {
  group('the tile', () {
    setUpAll(registerBuiltInWidgets);

    // LCARS's own condensed letters, as the panel draws them: the test
    // font's are squares, three times as wide, and no heading fits.
    setUpAll(() async {
      final antonio = FontLoader('Antonio')
        ..addFont(rootBundle.load('assets/fonts/Antonio.ttf'));
      await antonio.load();
    });

    Future<void> draw(
      WidgetTester tester,
      ParcelsService s,
      Size size,
      DashboardTheme theme,
    ) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final w = DashboardWidgetContext(
        theme: theme,
        config: DashboardWidgetConfig(
          id: 'p',
          type: 'parcels',
          x: 0,
          y: 0,
          width: 4,
          height: 4,
        ),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: s,
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox.fromSize(
                  size: size,
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      fontFamily: theme.isLcars ? 'Antonio' : null,
                    ),
                    child: Builder(
                      builder: (context) =>
                          WidgetRegistry.find('parcels')!.build(context, w),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    ParcelsService filled(int n) {
      final s = ParcelsService(null, persist: false)
        ..settingsOverride = const ParcelSettings();
      final refs = [
        'QG123456785GB',
        'DPD 15501234567890',
        'H01HYA0012345678',
        '1Z999AA10123456784',
        'https://www.amazon.co.uk/progress-tracker/package/?orderId=1',
      ];
      for (var i = 0; i < n; i++) {
        final p = s.add(
          ParcelRef.find(refs[i % refs.length])!,
          label: i == 0 ? 'A very long name for a pair of trainers' : null,
        );
        p.stage = ParcelStage.values[i % ParcelStage.values.length];
        p.expected = DateTime.now().add(Duration(days: i));
        p.events = [ParcelEvent(text: 'Arrived at depot', at: DateTime.now())];
      }
      return s;
    }

    final themes = [
      for (final id in ['glass', 'lcars', 'paper'])
        testThemes.firstWhere((t) => t.id == id),
    ];

    testWidgets('fits, from a small tile to a big one, in every look', (
      tester,
    ) async {
      for (final theme in themes) {
        for (final n in [0, 1, 3, 9]) {
          for (final size in const [
            Size(300, 260),
            Size(620, 300),
            Size(620, 560),
            Size(300, 900),
          ]) {
            await draw(tester, filled(n), size, theme);
            expect(
              tester.takeException(),
              isNull,
              reason: '${theme.id}, $n parcels at $size',
            );
          }
        }
      }
    });

    testWidgets('one parcel says where it is; a tap opens it', (tester) async {
      final s = filled(1)..parcels.single.stage = ParcelStage.out;
      await draw(tester, s, const Size(620, 560), themes.first);
      expect(find.text('Out for delivery'), findsWidgets);
      expect(find.text('1 out for delivery'), findsOneWidget);
      await tester.tap(find.text('A very long name for a pair of trainers'));
      await tester.pumpAndSettle();
      expect(find.byType(ParcelSheet), findsOneWidget);
      expect(find.text('Arrived at depot'), findsOneWidget);
      await tester.tap(find.text('It’s here'));
      await tester.pump();
      expect(s.parcels.single.delivered, isTrue);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(s.parcels, isEmpty);
      expect(find.byType(ParcelSheet), findsNothing);
    });

    group('a page to itself', () {
      // No labwc in a test: the frame shows the parcel's story, and its
      // page would open in a window of its own.
      setUp(() => SideBrowser.availableOverride = false);
      tearDown(() => SideBrowser.availableOverride = null);

      testWidgets('the list beside a frame, in every look', (tester) async {
        for (final theme in themes) {
          for (final n in [1, 3, 9]) {
            for (final size in const [Size(1880, 1000), Size(1100, 560)]) {
              await draw(tester, filled(n), size, theme);
              expect(
                tester.takeException(),
                isNull,
                reason: '${theme.id}, $n parcels at $size',
              );
              expect(find.byIcon(Icons.public), findsOneWidget);
            }
          }
        }
      });

      testWidgets('a touch on the list shows that parcel in the frame', (
        tester,
      ) async {
        final s = filled(3);
        await draw(tester, s, const Size(1880, 1000), themes.first);
        final second = s.parcels[1];
        expect(find.text('Arrived at depot'), findsOneWidget);
        await tester.tap(find.text(parcelName(second)).first);
        await tester.pump();
        // Its name twice now — in the list and over the frame — and no
        // sheet over everything.
        expect(find.text(parcelName(second)), findsNWidgets(2));
        expect(find.byType(ParcelSheet), findsNothing);
        await tester.tap(find.text('It’s here'));
        await tester.pump();
        expect(s.byId(second.id)!.delivered, isTrue);
      });

      Finder inPicker(String text) => find.descendant(
        of: find.byType(DuePicker),
        matching: find.text(text),
      );

      testWidgets('the week ahead, a day a row, today lit', (tester) async {
        final s = filled(3);
        final today = DateTime.now();
        s.parcels[2].expected = null;
        await draw(tester, s, const Size(1880, 1000), themes.first);
        expect(find.text('The week ahead'), findsOneWidget);
        expect(find.text('Today'), findsWidgets);
        expect(find.text('Tomorrow'), findsWidgets);
        expect(find.text('No day yet'), findsOneWidget);
        final dayAfter = DateTime(today.year, today.month, today.day + 2);
        expect(
          find.text('${weekdayShort(dayAfter)} ${dayAfter.day}'),
          findsOneWidget,
        );
      });

      testWidgets('When? sets a day and a part of it', (tester) async {
        final s = filled(1)..parcels.single.expected = null;
        await draw(tester, s, const Size(1880, 1000), themes.first);
        await tester.tap(find.text('When?'));
        await tester.pumpAndSettle();
        expect(find.byType(DuePicker), findsOneWidget);
        await tester.tap(find.text('Tomorrow').last);
        await tester.tap(find.text('Morning'));
        await tester.pump();
        expect(find.text('Due tomorrow, 08:00–12:00'), findsOneWidget);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.byType(DuePicker), findsNothing);
        final p = s.parcels.single;
        final now = DateTime.now();
        expect(p.expected, DateTime(now.year, now.month, now.day + 1, 8));
        expect(p.expectedTo, DateTime(now.year, now.month, now.day + 1, 12));
        expect(p.dueSaid, isTrue);
      });

      testWidgets('a slot to the quarter hour, and taken back', (tester) async {
        final s = filled(1);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        s.setDue(s.parcels.single.id, (
          from: today.add(const Duration(hours: 14, minutes: 30)),
          to: today.add(const Duration(hours: 16, minutes: 30)),
        ));
        await draw(tester, s, const Size(1880, 1000), themes[1]);
        await tester.tap(find.text('WHEN?'));
        await tester.pumpAndSettle();
        // Opened on what it is now: today, the slot, from 14:30 for two.
        expect(inPicker('Due today, 14:30–16:30'), findsOneWidget);
        await tester.tap(find.text('09:30'));
        await tester.tap(find.text(':15'));
        await tester.tap(find.text('AN HOUR'));
        await tester.pump();
        expect(inPicker('Due today, 09:15–10:15'), findsOneWidget);
        await tester.tap(find.text('NOT KNOWN'));
        await tester.pumpAndSettle();
        expect(s.parcels.single.expected, isNull);
      });

      testWidgets('Done untouched keeps a "by" as it was', (tester) async {
        final s = filled(1);
        final now = DateTime.now();
        final by = (
          from: DateTime(now.year, now.month, now.day + 1),
          to: DateTime(now.year, now.month, now.day + 1, 22),
        );
        s.setDue(s.parcels.single.id, by);
        await draw(tester, s, const Size(1880, 1000), themes.first);
        await tester.tap(find.text('When?'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(s.parcels.single.expected, by.from);
        expect(s.parcels.single.expectedTo, by.to);
      });

      testWidgets('the picker fits, in every look', (tester) async {
        for (final theme in themes) {
          final s = filled(1);
          await draw(tester, s, const Size(1880, 1000), theme);
          await tester.tap(
            find.byWidgetPredicate(
              (w) => w is Text && w.data?.toLowerCase() == 'when?',
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(DuePicker), findsOneWidget, reason: theme.id);
          expect(tester.takeException(), isNull, reason: theme.id);
          await tester.tapAt(const Offset(4, 4));
          await tester.pumpAndSettle();
          expect(find.byType(DuePicker), findsNothing, reason: theme.id);
        }
      });
    });
  });
}
