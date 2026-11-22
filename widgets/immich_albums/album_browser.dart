import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:home_canvas/look.dart';
import 'package:home_canvas/models/immich_models.dart';
import 'package:home_canvas/services/config_service.dart';
import 'package:home_canvas/services/immich_service.dart';
import 'package:home_canvas/screens/photo_search_screen.dart';
import 'package:home_canvas/screens/setup_screen.dart';
import 'package:home_canvas/screens/slideshow_screen.dart';
import 'package:home_canvas/widgets/glass.dart';
import 'package:home_canvas/widgets/lcars.dart';
import 'package:home_canvas/widgets/remote_image.dart';
import 'package:home_canvas/l10n/l10n.dart';

import 'album_screen.dart';

/// The albums on the Immich server, whole screen: what the kiosk opened on
/// before it opened on the dashboard. Reached from the albums tile.
///
/// Everything it did it still does — the covers in a grid, sorted three
/// ways, the library searched, an album opened onto its photos, and albums
/// held to pick several for one slideshow.
class AlbumBrowserScreen extends StatefulWidget {
  const AlbumBrowserScreen({super.key, this.sort = AlbumSort.recent});

  /// The order it opens in: the tile's.
  final AlbumSort sort;

  /// The way to it, from the tile.
  static Route<void> route({AlbumSort sort = AlbumSort.recent}) =>
      MaterialPageRoute(builder: (_) => AlbumBrowserScreen(sort: sort));

  @override
  State<AlbumBrowserScreen> createState() => _AlbumBrowserScreenState();
}

class _AlbumBrowserScreenState extends State<AlbumBrowserScreen>
    with AlbumsLoading {
  /// Ids of albums picked for a combined slideshow. Non-empty = selection mode.
  final Set<String> _selected = {};
  bool get _selectionMode => _selected.isNotEmpty;

  late AlbumSort _sort = widget.sort;

  @override
  void initState() {
    super.initState();
    unawaited(loadFast());
  }

  void _toggleSelect(Album album) {
    setState(() {
      if (!_selected.remove(album.id)) _selected.add(album.id);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  Future<void> _slideshowFromSelection() async {
    final ids = _selected.toList();
    if (await playAlbums(context, ids)) _clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    return ModernScaffold(
      header: _selectionMode ? _selectionHeader() : _header(),
      body: _buildBody(),
    );
  }

  Widget _header() {
    final shown = visibleAlbums(albums ?? const <Album>[]);
    final photos = shown.fold<int>(0, (n, a) => n + a.assetCount);
    return ScreenHeader(
      onBack: () => Navigator.of(context).maybePop(),
      title: tr('home.albums', 'Albums'),
      subtitle: shown.isEmpty
          ? null
          : '${albumCount(shown.length)} · ${itemCount(photos)}',
      trailing: GlassIconButton(
        icon: Icons.refresh,
        tooltip: tr('modules.refresh', 'Refresh'),
        onPressed: () => load(force: true),
      ),
    );
  }

  Widget _selectionHeader() {
    return ScreenHeader(
      onBack: _clearSelection,
      backIcon: Icons.close,
      backTooltip: tr('home.cancelSelection', 'Cancel selection'),
      title: '${_selected.length} selected',
      subtitle: tr(
        'home.tapMoreAlbumsToAdd',
        'Tap more albums to add them to one slideshow',
      ),
      trailing: FilledButton.icon(
        onPressed: _slideshowFromSelection,
        icon: const Icon(Icons.play_arrow_rounded, size: 30),
        label: Text(tr('home.slideshow', 'Slideshow')),
        style: whitePillButton(context),
      ),
    );
  }

  Widget _buildBody() {
    final problem = albumsProblem(context, fontScale: 1);
    if (problem != null) return problem;
    final sorted = sortAlbums(visibleAlbums(albums!), _sort);
    return RefreshIndicator(
      onRefresh: () => load(silent: true, force: true),
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(40, 12, 40, 18),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  const FindPhotosButton(),
                  const Spacer(),
                  for (final s in AlbumSort.values) ...[
                    const SizedBox(width: 10),
                    ChoicePill(
                      label: s.label,
                      selected: _sort == s,
                      onTap: () => setState(() => _sort = s),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(40, 0, 40, 48),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 300,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
                childAspectRatio: 0.82,
              ),
              delegate: SliverChildBuilderDelegate(childCount: sorted.length, (
                context,
                i,
              ) {
                final album = sorted[i];
                return AlbumCard(
                  album: album,
                  immich: immich,
                  selected: _selected.contains(album.id),
                  selectionMode: _selectionMode,
                  // In selection mode a tap toggles; otherwise it opens
                  // the album.
                  onTap: () => _selectionMode
                      ? _toggleSelect(album)
                      : openAlbum(context, album),
                  onLongPress: () => _toggleSelect(album),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// The albums, read from the disk cache at once and then from the server:
/// what the tile and the whole-screen browser both start from.
mixin AlbumsLoading<T extends StatefulWidget> on State<T> {
  late final ImmichService immich = context.read<ImmichService>();
  List<Album>? albums;
  String? error;

  /// Whether there is an Immich to ask. The albums need one; the dashboard
  /// does not, so a panel may well have none yet.
  bool get connected => immich.config.isConfigured;

  /// Paints from the disk cache immediately (instant cold start), then
  /// refreshes from the server in the background.
  Future<void> loadFast() async {
    if (!connected) return;
    final cached = await immich.getCachedAlbums();
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() => albums = cached);
    }
    await load(silent: cached != null && cached.isNotEmpty);
  }

  Future<void> load({bool silent = false, bool force = false}) async {
    if (!connected) return;
    if (!silent) {
      setState(() {
        albums = null;
        error = null;
      });
    }
    try {
      final a = await immich.getAlbums(forceRefresh: force);
      if (mounted) {
        setState(() {
          albums = a;
          error = null;
        });
      }
      // Warm every album cover into the disk cache in the background so the
      // whole grid is populated before it's scrolled.
      unawaited(immich.warmAlbumCovers(a));
    } catch (e) {
      // Keep showing cached content if we have it; only surface a hard error
      // when there's nothing on screen.
      if (mounted && albums == null) setState(() => error = '$e');
    }
  }

  /// What to show instead of the albums, when there are none to show: not
  /// connected, Immich unreachable, still loading, or nothing in them. Null
  /// when there are albums. [fontScale] shrinks it to a tile.
  Widget? albumsProblem(BuildContext context, {required double fontScale}) {
    final look = context.look;
    Widget words(String big, [String? small, Widget? action]) => Center(
      child: Padding(
        padding: EdgeInsets.all(24 * fontScale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              big,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26 * fontScale,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (small != null) ...[
              SizedBox(height: 8 * fontScale),
              Text(
                small,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: look.textSecondary,
                  fontSize: 17 * fontScale,
                ),
              ),
            ],
            if (action != null) ...[
              SizedBox(height: 20 * fontScale),
              action,
            ],
          ],
        ),
      ),
    );

    if (!connected) {
      return words(
        tr('widget.immich_albums.notConnected', 'Not connected to Immich'),
        tr(
          'widget.immich_albums.connectHow',
          'Give the panel your Immich server’s address and an API key.',
        ),
        FilledButton.icon(
          onPressed: () => connectImmich(context, then: loadFast),
          icon: const Icon(Icons.link_rounded),
          label: Text(
            tr('widget.immich_albums.connect', 'Connect to Immich'),
          ),
          style: whitePillButton(context),
        ),
      );
    }
    if (error != null) {
      return words(
        tr('home.couldNotReachImmich', 'Could not reach Immich'),
        error,
        FilledButton.icon(
          onPressed: () => load(force: true),
          icon: const Icon(Icons.refresh),
          label: Text(tr('home.tryAgain', 'Try again')),
          style: whitePillButton(context),
        ),
      );
    }
    final all = albums;
    if (all == null) return const Center(child: CircularProgressIndicator());
    if (all.isEmpty) return words(tr('home.noAlbumsYet', 'No albums yet'));
    if (visibleAlbums(all).isEmpty) {
      return words(
        tr('home.noAlbumsWithAnythingIn', 'No albums with anything in them yet'),
      );
    }
    return null;
  }
}

/// Opens the panel's Immich connection — the same screen as Settings does —
/// and runs [then] once it has been set.
Future<void> connectImmich(
  BuildContext context, {
  Future<void> Function()? then,
}) async {
  final connected = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const SetupScreen()),
  );
  if (connected == true && then != null) await then();
}

/// Opens [album] onto its photos.
void openAlbum(BuildContext context, Album album) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => AlbumScreen(album: album)));
}

/// Every photo from the albums [ids], as one slideshow. False when there was
/// nothing to show, and the reason has been said.
Future<bool> playAlbums(BuildContext context, List<String> ids) async {
  if (ids.isEmpty) return false;
  final immich = context.read<ImmichService>();
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  void snack(String msg) =>
      messenger.showSnackBar(SnackBar(content: Text(msg)));

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  final images = <Asset>[];
  final seen = <String>{};
  try {
    final results = await Future.wait(ids.map(immich.getAlbumAssets));
    for (final assets in results) {
      for (final a in assets) {
        if (a.isImage && seen.add(a.id)) images.add(a);
      }
    }
  } catch (e) {
    navigator.pop();
    snack(
      tr(
        'home.couldNotLoadTheSelected',
        'Could not load the selected albums: {e}',
        {'e': e},
      ),
    );
    return false;
  }

  navigator.pop(); // dismiss loading
  if (images.isEmpty) {
    snack(tr('home.noPhotosInTheSelected', 'No photos in the selected albums'));
    return false;
  }
  if (!context.mounted) return false;
  final count = ids.length;
  unawaited(
    navigator.push(
      MaterialPageRoute(
        builder: (_) => SlideshowScreen(
          images: images,
          source: immich,
          settings: context.read<ConfigService>().slideshow,
          title: '$count album${count == 1 ? '' : 's'}',
        ),
      ),
    ),
  );
  return true;
}

/// How the album grid is ordered.
enum AlbumSort {
  recent,
  name,
  size;

  /// What the sort button says, in the panel's language.
  String get label => switch (this) {
    recent => tr('home.recent', 'Recent'),
    name => tr('home.aToZ', 'A–Z'),
    size => tr('home.mostItems', 'Most items'),
  };

  /// The sort saved as [name] in the tile's settings; recent otherwise.
  static AlbumSort named(String name) => AlbumSort.values.firstWhere(
    (s) => s.name == name,
    orElse: () => AlbumSort.recent,
  );
}

/// [albums] in [sort] order. Stable, so equal albums keep Immich's order.
List<Album> sortAlbums(List<Album> albums, AlbumSort sort) {
  final indexed = [for (var i = 0; i < albums.length; i++) (i, albums[i])];
  int byIndex((int, Album) a, (int, Album) b) => a.$1.compareTo(b.$1);
  switch (sort) {
    case AlbumSort.recent:
      final never = DateTime.fromMillisecondsSinceEpoch(0);
      indexed.sort((a, b) {
        final c = (b.$2.updatedAt ?? never).compareTo(a.$2.updatedAt ?? never);
        return c != 0 ? c : byIndex(a, b);
      });
    case AlbumSort.name:
      indexed.sort((a, b) {
        final c = a.$2.name.toLowerCase().compareTo(b.$2.name.toLowerCase());
        return c != 0 ? c : byIndex(a, b);
      });
    case AlbumSort.size:
      indexed.sort((a, b) {
        final c = b.$2.assetCount.compareTo(a.$2.assetCount);
        return c != 0 ? c : byIndex(a, b);
      });
  }
  return [for (final e in indexed) e.$2];
}

/// The albums worth showing: those with something in them.
///
/// An empty album on a wall of photographs is a grey placeholder tile that
/// opens onto "This album is empty". Immich keeps them for good reasons — an
/// album made ready for a trip, one whose photos were moved — but none of
/// those reasons is a reason to show it here.
List<Album> visibleAlbums(List<Album> albums) => [
  for (final a in albums)
    if (a.assetCount > 0) a,
];

/// Find photos: the whole library searched by who, where, when or what is
/// in them, beside the albums it would otherwise take opening one by one.
class FindPhotosButton extends StatelessWidget {
  const FindPhotosButton({super.key});

  void _open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const PhotoSearchScreen()));

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final label = tr('find.title', 'Find photos');
    if (look.isLcars) {
      return LcarsBlock(
        colour: look.block(2),
        onTap: () => _open(context),
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Text(lcarsCaps(label), style: const TextStyle(fontSize: 19)),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: PressScale(
        scale: 0.97,
        child: GestureDetector(
          onTap: () => _open(context),
          child: Glass(
            tint: 0.07,
            padding: const EdgeInsets.fromLTRB(20, 12, 26, 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_rounded, size: 26, color: look.textSecondary),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: look.textPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    tr('find.example', '“the beach in 2019”'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 18, color: look.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One album: its cover, its name and how much is in it. [scale] shrinks the
/// words and corners with the card, for the smaller cards of a tile.
class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.album,
    required this.immich,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    this.onLongPress,
    this.scale = 1,
  });

  final Album album;
  final ImmichService immich;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final radius = 24.0 * scale;
    final ring = 5.0 * scale;
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          // The selection ring sits outside the photo, so choosing an album
          // does not crop into its cover.
          padding: EdgeInsets.all(selected ? ring : 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius + ring),
            color: selected ? accent : Colors.transparent,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                album.thumbnailAssetId != null
                    ? RemoteImage(
                        url: immich.thumbUrl(album.thumbnailAssetId!),
                        fallbackUrl: immich.previewUrl(album.thumbnailAssetId!),
                        headers: immich.authHeaders,
                      )
                    : ColoredBox(
                        color: context.look.solidSurface,
                        child: Icon(
                          Icons.photo_album_outlined,
                          size: 56 * scale,
                          color: context.look.wash(0.24),
                        ),
                      ),
                // A scrim under the words only, so the photo stays the photo.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xD9000000)],
                      stops: [0.42, 1.0],
                    ),
                  ),
                ),
                // A hairline edge: without it a dark photo's corners melt into
                // the dark background and the card loses its shape.
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                Positioned(
                  left: 18 * scale,
                  right: 18 * scale,
                  bottom: 16 * scale,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21 * scale,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      SizedBox(height: 2 * scale),
                      Text(
                        itemCount(album.assetCount),
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16 * scale,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selectionMode)
                  Positioned(
                    top: 12 * scale,
                    right: 12 * scale,
                    child: AnimatedScale(
                      scale: selected ? 1.0 : 0.85,
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        decoration: BoxDecoration(
                          color: selected ? accent : Colors.black45,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        padding: EdgeInsets.all(5 * scale),
                        child: Icon(
                          selected ? Icons.check : Icons.circle_outlined,
                          size: 24 * scale,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
