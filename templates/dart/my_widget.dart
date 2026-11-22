// A widget to start from: a greeting, in the theme's colours.
//
// Copy this folder to widgets/<your_name_for_it>/, rename this file, and
// change what it draws. Three things make a widget:
//
//   1. A Flutter widget, handed a DashboardWidgetContext: `w.theme` for
//      colours, `w.option(key, fallback)` for its settings.
//   2. A DashboardWidgetType describing it — the editor builds its palette
//      entry and its settings form from that. `preview` is the stand-in
//      content the editor, and your screenshot, are drawn from.
//   3. A top-level `final widgetTypes = […]`, which is what gets registered.
//      It must be called exactly that.
//
// Anything the app's own code offers is yours to import, from
// `package:home_canvas/…`, and the packages in its pubspec.
import 'package:flutter/material.dart';

import 'package:home_canvas/dashboard/widget_registry.dart';

class MyWidget extends StatelessWidget {
  const MyWidget({super.key, required this.w});

  final DashboardWidgetContext w;

  @override
  Widget build(BuildContext context) {
    final name = w.option('name', 'world');
    return Center(
      child: Text(
        'Hello, $name',
        style: TextStyle(
          color: w.theme.textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

final myWidgetType = DashboardWidgetType(
  // Saved in people's dashboards: choose it once and never rename it.
  type: 'my_widget',
  name: 'My widget',
  description: 'Says hello to whoever you name.',
  glyph: '🧩',
  category: WidgetCategory.other,
  defaultWidth: 3,
  defaultHeight: 2,
  options: const [
    WidgetOption(
      key: 'name',
      label: 'Name',
      defaultValue: 'world',
      help: 'Who to greet.',
    ),
  ],
  preview: const [PreviewLine('Hello, world', scale: 0.2, centre: true)],
  build: (context, w) => MyWidget(w: w),
);

/// What this add-on brings: the panel registers each of these.
final widgetTypes = <DashboardWidgetType>[myWidgetType];
