import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/parcels_view.dart';

final parcelsWidgetType = DashboardWidgetType(
  type: 'parcels',
  category: WidgetCategory.house,
  name: 'Parcels',
  description:
      'Parcels on their way: share a tracking link or number to the panel '
      'from the phone app — a Royal Mail, DPD, Evri or Yodel email, a '
      'courier’s page — and it goes on this list. With a tracking service '
      'set below, each is looked up every half an hour and pops up when it '
      'is out for delivery or has come. Tap one for its story and its '
      'carrier’s page.',
  glyph: '📦',
  defaultWidth: 4,
  defaultHeight: 4,
  minWidth: 2,
  minHeight: 2,
  fitsItself: true,
  options: const [
    WidgetOption(
      key: 'service',
      label: 'Tracking service',
      kind: OptionKind.choice,
      defaultValue: 'none',
      choices: {
        'none': 'None — links only',
        '17track': '17TRACK',
        'ship24': 'Ship24',
      },
      help:
          'Looks each parcel up with its carrier: Royal Mail, DPD, Evri, '
          'Yodel and hundreds more. Each needs a free account and its API '
          'key — 17TRACK gives 200 parcels once, Ship24 10 a month. Without '
          'one, a parcel is its carrier’s tracking page, a touch away.',
    ),
    WidgetOption(
      key: 'apiKey',
      label: 'API key',
      kind: OptionKind.secret,
      help:
          '17TRACK: Settings → Security in its API console. Ship24: API '
          'keys in its dashboard.',
    ),
    WidgetOption(
      key: 'postcode',
      label: 'Delivery postcode',
      help:
          'Ship24 says more about some carriers’ parcels with it — DPD’s '
          'for one. It goes to the tracking service and nowhere else.',
    ),
    WidgetOption(
      key: 'tell',
      label: 'Pop up when a parcel is out for delivery or has come',
      kind: OptionKind.boolean,
      defaultValue: true,
    ),
    WidgetOption(
      key: 'keepDays',
      label: 'Keep delivered parcels for',
      kind: OptionKind.choice,
      defaultValue: '2',
      choices: {'1': 'A day', '2': 'Two days', '7': 'A week'},
    ),
  ],
  preview: const [
    PreviewLine('DPD · Out for delivery', scale: 0.12, accent: true),
    PreviewLine('Royal Mail · Due tomorrow', scale: 0.12),
    PreviewLine('Evri · Delivered', scale: 0.12, muted: true),
  ],
  build: (context, w) => ParcelsWidget(w: w),
);

/// What this add-on brings: the panel registers each of these.
final widgetTypes = <DashboardWidgetType>[parcelsWidgetType];
