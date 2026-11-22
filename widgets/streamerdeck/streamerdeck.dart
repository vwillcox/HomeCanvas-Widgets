import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/dashboard/dashboard_theme.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/l10n/l10n.dart';
import 'package:home_canvas/main.dart' show rootNavigatorKey;
import 'package:home_canvas/services/computer_power.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/home_assistant_service.dart';
import 'package:home_canvas/services/home_control.dart';
import 'package:home_canvas/services/link_outbox.dart';
import 'package:home_canvas/services/screen_idle_service.dart';
import 'package:home_canvas/services/share_inbox_service.dart';

import 'deck_link.dart';
import 'deck_model.dart';
import 'deck_screen.dart';

/// StreamerDeck: a Stream Deck whose keys are on the panel's screen.
///
/// Two halves. This one, the add-on, shows the keys and runs the ones that
/// belong to the house — Home Assistant, routines, switching the computer
/// on. The other is StreamerDeck on the computer
/// (https://github.com/vwillcox/StreamerDeck): it holds the profiles, runs
/// the computer's keys, serves the editor they are laid out in, and connects
/// to the panel's Share Inbox with a sender's token. Without it there is
/// nothing to show.
///
/// What the dashboard gets is a tile: the page of keys the deck is on, in
/// small, and a tap opens them full screen. The link itself is the app's,
/// not the tile's — it is made as the app comes up, so the computer can
/// connect whether or not a tile is on screen.
///
/// Reading this list — the app does, once, as it starts — also ties the
/// deck to the app as soon as the app is up.
final widgetTypes = StreamerDeck.start(<DashboardWidgetType>[
  streamerDeckWidgetType,
]);

final streamerDeckWidgetType = DashboardWidgetType(
  type: 'streamerdeck',
  name: 'StreamerDeck',
  description:
      'The keys of StreamerDeck, an app on your computer that is needed for '
      'this: the page you are on, and a tap for all of them full screen.',
  glyph: '🎛️',
  category: WidgetCategory.homeLab,
  defaultWidth: 3,
  defaultHeight: 2,
  fitsItself: true,
  preview: const [
    PreviewLine('🎛️  StreamerDeck', scale: 0.15, accent: true),
    PreviewLine('🔆  🎙️  🎵  🖥️  🌙', scale: 0.17, centre: true),
    PreviewLine('💡  ⏯️  🔇  🎮  📁', scale: 0.17, centre: true),
    PreviewLine('Tap for every key', scale: 0.09, muted: true),
  ],
  build: (context, w) => StreamerDeckTile(w: w),
);

/// The one deck there is, and how it is tied to the app.
class StreamerDeck {
  StreamerDeck._();

  static DeckLink? _link;
  static bool _started = false;

  /// The deck, once it has been tied to the app.
  static DeckLink? get link => _link;

  /// Has [link] be the deck, as a test makes one.
  @visibleForTesting
  static void use(DeckLink? link) => _link = link;

  /// As before the app started, for a test of starting.
  @visibleForTesting
  static void reset() {
    _link = null;
    _started = false;
  }

  /// Ties the deck to the app after its first frame, when its services are
  /// there to be had; hands back [types] untouched.
  static List<DashboardWidgetType> start(List<DashboardWidgetType> types) {
    if (!_started) {
      _started = true;
      try {
        _afterFrame(0);
      } catch (_) {
        // No Flutter binding — a plain test reading the widget types —
        // and so no app to tie the deck to.
      }
    }
    return types;
  }

  // A frame's callback, not a timer: in a test that never builds the app
  // it waits for a frame that is not coming, and holds nothing up.
  static void _afterFrame(int frames) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = rootNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        tie(context);
      } else if (frames < 300) {
        _afterFrame(frames + 1);
      }
    });
  }

  /// The deck, made from the app's own services the first time it is asked
  /// for, with the Share Inbox told to hand it the computer's connection.
  /// Null when this copy of HomeCanvas has no Share Inbox to connect
  /// through.
  static DeckLink? tie(BuildContext context) {
    final had = _link;
    if (had != null) return had;
    T? optional<T>() {
      try {
        return context.read<T>();
      } on ProviderNotFoundException {
        return null;
      }
    }

    final inbox = optional<ShareInboxService>();
    final config = optional<ConfigService>();
    final home = optional<HomeAssistantService>();
    final outbox = optional<LinkOutbox>();
    if (inbox == null || config == null || home == null || outbox == null) {
      return null;
    }
    // Routines are run by the app's HomeControl, which a HomeCanvas from
    // before the deck was an add-on does not hand out: routine keys then
    // say so, and everything else works.
    final house = optional<HomeControl>();
    final computers = ComputerPower(outbox);
    final link = DeckLink(
      home: home,
      routines: () => config.config.routines,
      runRoutine: house?.runRoutine,
      computer: (on) => computers.setPower(on),
      keepAwake: optional<ScreenIdleService>()?.noteInteraction,
    );
    unawaited(link.load());
    inbox.onDeck = link.accept;
    return _link = link;
  }
}

/// The deck on the dashboard: the page of keys it is on, and a tap opens
/// them full screen. Small, it is a button.
class StreamerDeckTile extends StatelessWidget {
  const StreamerDeckTile({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    final look = w.theme;
    final link = StreamerDeck.tie(context);
    if (link == null) {
      return _Message(
        look: look,
        title: 'StreamerDeck',
        body: tr(
          'deck.noInbox',
          'This HomeCanvas has no Share Inbox for StreamerDeck to connect '
              'through.',
        ),
      );
    }
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(DeckScreen.route(link)),
        child: LayoutBuilder(
          builder: (context, box) {
            final small = box.maxHeight < 96 || box.maxWidth < 120;
            if (small) return _Button(link: link, look: look, box: box.biggest);
            final profile = link.profile;
            return Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Heading(link: link, look: look),
                  const SizedBox(height: 8),
                  Expanded(
                    child: profile == null
                        ? _NoDeck(look: look)
                        : _MiniGrid(link: link, profile: profile),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Which computer, and whether it is there.
class _Heading extends StatelessWidget {
  const _Heading({required this.link, required this.look});

  final DeckLink link;
  final DashboardTheme look;

  @override
  Widget build(BuildContext context) {
    final on = link.connected;
    return Row(
      children: [
        Icon(Icons.apps_rounded, size: 20, color: on ? look.accent : look.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            on
                ? (link.pcName ?? tr('deck.computer', 'Computer'))
                : link.known
                ? tr('deck.computerOff', 'Computer offline')
                : 'StreamerDeck',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: look.textPrimary,
              fontFamily: look.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _Dot(on: on),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: on ? const Color(0xFF22C55E) : const Color(0xFF6B7280),
    ),
  );
}

/// The keys of the page the deck is on, in small. Touching them opens the
/// deck; none is pressed from here.
class _MiniGrid extends StatelessWidget {
  const _MiniGrid({required this.link, required this.profile});

  final DeckLink link;
  final DeckProfile profile;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final g = DeckGeometry(box.biggest, profile.cols, profile.rows);
      final page = link.page;
      final pages = link.pages.length;
      return Stack(
        children: [
          for (var r = 0; r < profile.rows; r++)
            for (var c = 0; c < profile.cols; c++)
              Positioned(
                left: g.at(c, r).dx,
                top: g.at(c, r).dy,
                width: g.key,
                height: g.key,
                child: switch (link.inFolder && c == 0 && r == 0
                    ? null
                    : page?.at(c, r)) {
                  final DeckKey k => DeckKeyView(
                    deckKey: k,
                    link: link,
                    size: g.key,
                    pageLabel: '${link.pageIndex + 1}/$pages',
                  ),
                  null => _Blank(size: g.key),
                },
              ),
        ],
      );
    },
  );
}

class _Blank extends StatelessWidget {
  const _Blank({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF0B0D12),
      borderRadius: BorderRadius.circular(size * 0.16),
      border: Border.all(color: const Color(0x14FFFFFF)),
    ),
  );
}

/// Before any computer has sent a deck: what is needed for one.
class _NoDeck extends StatelessWidget {
  const _NoDeck({required this.look});

  final DashboardTheme look;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.topLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              'deck.tileNeedsApp',
              'No keys yet. They come from StreamerDeck, an app on your '
                  'computer: install it there and pair it with a Share Inbox '
                  'sender’s token.',
            ),
            style: TextStyle(color: look.textSecondary, fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 6),
          Text(
            streamerDeckHome,
            style: TextStyle(color: look.accent, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

/// The tile too small for keys: a button that opens them.
class _Button extends StatelessWidget {
  const _Button({required this.link, required this.look, required this.box});

  final DeckLink link;
  final DashboardTheme look;
  final Size box;

  @override
  Widget build(BuildContext context) {
    final icon = (box.shortestSide * 0.5).clamp(16.0, 44.0);
    return Stack(
      children: [
        Center(
          child: Icon(
            Icons.apps_rounded,
            size: icon,
            color: link.connected ? look.accent : look.textPrimary,
          ),
        ),
        Positioned(top: 6, right: 6, child: _Dot(on: link.connected)),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.look, required this.title, required this.body});

  final DashboardTheme look;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(color: look.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(body, style: TextStyle(color: look.textSecondary, fontSize: 14, height: 1.35)),
          ],
        ),
      ),
    ),
  );
}
