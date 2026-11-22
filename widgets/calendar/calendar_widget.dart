import 'package:home_canvas/dashboard/widget_registry.dart';
import 'package:home_canvas/dashboard/widgets/calendar_view.dart';

final calendarWidgetType = DashboardWidgetType(
  type: 'calendar',
  category: WidgetCategory.timeAndDay,
  name: 'Calendar',
  description:
      'Upcoming events from one or more published calendar links, as a '
      'schedule or a month.',
  glyph: '📅',
  defaultWidth: 4,
  defaultHeight: 3,
  minWidth: 1,
  minHeight: 1,
  options: const [
    WidgetOption(
      key: 'view',
      label: 'View',
      kind: OptionKind.choice,
      defaultValue: 'schedule',
      choices: {
        'schedule': 'Schedule — what’s coming up',
        'month': 'Month — which days are busy',
      },
    ),
    WidgetOption(
      key: 'sources',
      label: 'Calendars',
      kind: OptionKind.list,
      addLabel: 'Add a calendar',
      help:
          'Each link is the secret iCal address from Google, Apple or '
          'Outlook — webcal:// works too. Anyone with one can read that '
          'calendar, so treat them as passwords.',
      fields: [
        WidgetOption(key: 'name', label: 'Name', defaultValue: ''),
        WidgetOption(key: 'url', label: 'Link (ICS)', defaultValue: ''),
        WidgetOption(
          key: 'colour',
          label: 'Colour',
          kind: OptionKind.colour,
          defaultValue: '#7DD3FC',
        ),
      ],
    ),
    WidgetOption(
      key: 'days',
      label: 'Look ahead (days)',
      kind: OptionKind.number,
      defaultValue: 14,
      help: 'Schedule view only.',
    ),
    WidgetOption(
      key: 'maxEvents',
      label: 'Most events to show',
      kind: OptionKind.number,
      defaultValue: 6,
      help: 'Schedule view only.',
    ),
  ],
  preview: const [
    PreviewLine('Dentist', scale: 0.14, px: 16),
    PreviewLine('Today 14:30', scale: 0.1, muted: true, px: 13),
    PreviewLine('Bin day', scale: 0.14, px: 16),
    PreviewLine('Tomorrow · all day', scale: 0.1, muted: true, px: 13),
  ],
  live: (config, data) {
    final feeds = data.feeds;
    if (feeds == null) return const [];
    final urls = <String>[
      for (final r in (config.options['sources'] as List?) ?? const [])
        if (r is Map && '${r['url'] ?? ''}'.isNotEmpty) '${r['url']}',
    ];
    if (urls.isEmpty && '${config.options['url'] ?? ''}'.isNotEmpty) {
      urls.add('${config.options['url']}');
    }
    if (urls.isEmpty) return const [];

    final events = [for (final u in urls) ...feeds.calendar(u)]
      ..sort((a, b) => a.start.compareTo(b.start));
    final from = DateTime.now().subtract(const Duration(hours: 12));
    final upcoming = events
        .where((e) => e.start.isAfter(from))
        .take(4)
        .toList();
    if (upcoming.isEmpty) return const [];
    return [
      for (final e in upcoming) ...[
        PreviewLine(e.title, scale: 0.14, px: 16),
        PreviewLine(calendarWhen(e), scale: 0.1, muted: true, px: 13),
      ],
    ];
  },
  build: (context, w) => DashboardCalendarWidget(w: w),
);

/// What this add-on brings: the panel registers each of these.
final widgetTypes = <DashboardWidgetType>[calendarWidgetType];
