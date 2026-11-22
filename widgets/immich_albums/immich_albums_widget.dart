import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:home_canvas/models/immich_models.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/tile_bits.dart';
import 'package:home_canvas/screens/photo_search_screen.dart';
import 'package:home_canvas/widgets/pause_when_hidden.dart';
import 'package:home_canvas/widgets/shown_timers.dart';
import 'package:home_canvas/l10n/l10n.dart';

import 'album_browser.dart';

/// The albums on the Immich server, as a tile: covers to open, the library
/// to search, several albums to pick for one slideshow, and the whole
/// browser a touch away.
///
/// The kiosk opened on these before it opened on the dashboard. As a tile
/// they sit beside everything else, at whatever size suits — a strip of
/// covers, or a page of their own — and the top bar's Photos button comes
/// here.
class AlbumsTile extends StatefulWidget {
  const AlbumsTile({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  State<AlbumsTile> createState() => _AlbumsTileState();
}

class _AlbumsTileState extends State<AlbumsTile>
    with AlbumsLoading, PauseWhenHidden, ShownTimers {
  /// Albums picked for one slideshow. Picking starts from the tick button
  /// rather than a hold, which on the dashboard brings the tile close.
  final Set<String> _picked = {};
  bool _picking = false;

  AlbumSort get _sort => AlbumSort.named(widget.w.option('sort', 'recent'));

  @override
  void initState() {
    super.initState();
    unawaited(loadFast());
    // Albums change slowly — one made, photos added — but a tile can stay
    // up for days.
    everyWhileShown(const Duration(minutes: 30), () => load(silent: true));
  }

  void _toggle(Album album) => setState(() {
    if (!_picked.remove(album.id)) _picked.add(album.id);
  });

  void _stopPicking() => setState(() {
    _picking = false;
    _picked.clear();
  });

  Future<void> _play() async {
    if (await playAlbums(context, _picked.toList())) _stopPicking();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.w.theme;
    return LayoutBuilder(
      builder: (context, c) {
        // Sized to the tile: words and buttons for a small one stay small.
        final scale = (math.min(c.maxWidth, c.maxHeight * 1.6) / 900).clamp(
          0.55,
          1.0,
        );
        final problem = albumsProblem(context, fontScale: scale);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(t.textSecondary, scale),
            SizedBox(height: 10 * scale),
            Expanded(child: problem ?? _grid(c.maxWidth, scale)),
          ],
        );
      },
    );
  }

  Widget _header(Color muted, double scale) {
    final t = widget.w.theme;
    final shown = visibleAlbums(albums ?? const <Album>[]);
    final size = 26.0 * scale;
    Widget button(IconData icon, String tip, VoidCallback? go) => IconButton(
      icon: Icon(icon, size: size),
      tooltip: tip,
      color: muted,
      visualDensity: VisualDensity.compact,
      onPressed: go,
    );

    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: _picking
          ? [
              TextButton.icon(
                onPressed: _picked.isEmpty ? null : _play,
                icon: Icon(Icons.play_arrow_rounded, size: size),
                label: Text(
                  _picked.isEmpty
                      ? tr('widget.immich_albums.pick', 'Pick albums')
                      : tr('home.slideshow', 'Slideshow'),
                  style: TextStyle(fontSize: 17 * scale),
                ),
                style: TextButton.styleFrom(foregroundColor: t.accent),
              ),
              button(
                Icons.close_rounded,
                tr('home.cancelSelection', 'Cancel selection'),
                _stopPicking,
              ),
            ]
          : [
              if (connected) ...[
                button(
                  Icons.search_rounded,
                  tr('find.title', 'Find photos'),
                  () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PhotoSearchScreen(),
                    ),
                  ),
                ),
                if (shown.length > 1)
                  button(
                    Icons.checklist_rounded,
                    tr(
                      'widget.immich_albums.pickForSlideshow',
                      'Pick albums for one slideshow',
                    ),
                    () => setState(() => _picking = true),
                  ),
              ],
              button(
                Icons.open_in_full_rounded,
                tr('widget.immich_albums.openAll', 'All the albums'),
                () => Navigator.of(context).push(
                  AlbumBrowserScreen.route(sort: _sort),
                ),
              ),
            ],
    );

    final label = _picking
        ? tr('widget.immich_albums.picked', '{n} picked', {
            'n': _picked.length,
          })
        : shown.isEmpty
        ? tr('home.albums', 'Albums')
        : '${tr('home.albums', 'Albums')} · ${shown.length}';
    return TileLabel(
      icon: Icons.photo_library_outlined,
      text: label,
      theme: t,
      size: 18 * scale,
      trailing: buttons,
    );
  }

  Widget _grid(double width, double scale) {
    final sorted = sortAlbums(visibleAlbums(albums!), _sort);
    // Two across on a narrow tile, cards of about two hundred and sixty on
    // a wide one.
    final extent = math.max(120.0, math.min(260.0, width / 2.05));
    final gap = 14.0 * scale;
    return RefreshIndicator(
      onRefresh: () => load(silent: true, force: true),
      child: GridView.builder(
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: extent,
          crossAxisSpacing: gap,
          mainAxisSpacing: gap,
          childAspectRatio: 0.82,
        ),
        itemCount: sorted.length,
        itemBuilder: (context, i) {
          final album = sorted[i];
          return AlbumCard(
            album: album,
            immich: immich,
            scale: (extent / 300).clamp(0.5, 1.0),
            selected: _picked.contains(album.id),
            selectionMode: _picking,
            onTap: () => _picking ? _toggle(album) : openAlbum(context, album),
          );
        },
      ),
    );
  }
}

final albumsWidgetType = DashboardWidgetType(
  type: 'immich_albums',
  category: WidgetCategory.photosAndMedia,
  name: 'Photo albums',
  description:
      'The albums on your Immich server: tap one for its photos, a '
      'slideshow or a video; search the whole library by who, where or '
      'when; pick several albums for one slideshow. Opens the whole album '
      'browser too, and the top bar’s Photos button comes here.',
  glyph: '🖼️',
  defaultWidth: 6,
  defaultHeight: 6,
  minWidth: 3,
  minHeight: 3,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'sort',
      label: 'Order',
      kind: OptionKind.choice,
      defaultValue: 'recent',
      choices: {
        'recent': 'Most recently changed first',
        'name': 'A to Z',
        'size': 'Most photos first',
      },
    ),
  ],
  preview: const [
    PreviewLine('Albums · 24', scale: 0.12),
    PreviewLine('Summer 2025 · 412 items', scale: 0.1),
    PreviewLine('Christmas · 96 items', scale: 0.1),
    PreviewLine('The garden · 58 items', scale: 0.1, muted: true),
  ],
  build: (context, w) => AlbumsTile(w: w),
);

/// What this add-on brings: the panel registers each of these.
final widgetTypes = <DashboardWidgetType>[albumsWidgetType];
