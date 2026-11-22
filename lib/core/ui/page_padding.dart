import 'package:material_ui/material_ui.dart';

/// Padding for a scrolling page.
///
/// The app draws edge to edge, so the bottom of a page sits under Android's
/// navigation bar (◁ ○ □). This adds the bar's height plus room to tap the
/// last button comfortably, and more when a floating action button covers
/// the bottom of the page.
EdgeInsets pagePadding(BuildContext context, {bool hasFloatingButton = false}) {
  final bottomInset = MediaQuery.paddingOf(context).bottom;
  return EdgeInsets.fromLTRB(
    16,
    16,
    16,
    16 + bottomInset + 24 + (hasFloatingButton ? 72 : 0),
  );
}
