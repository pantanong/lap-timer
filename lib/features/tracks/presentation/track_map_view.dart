import 'package:flutter_map/flutter_map.dart';
import 'package:lap_timer/features/gps/domain/gps_fix.dart';
import 'package:lap_timer/features/tracks/domain/gate_line.dart';
import 'package:lap_timer/features/tracks/domain/track.dart';
import 'package:lap_timer/theme/app_colors.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

/// Background imagery for the track map.
enum MapImagery {
  /// Aerial photos (Esri World Imagery) — best for placing lines.
  satellite,

  /// Street map (OpenStreetMap).
  street,
}

/// Map of a track with its timing lines, the live GPS position and any
/// points the user is tapping. Built on `flutter_map` (no API key).
///
/// Colours: start/finish white, sector splits teal, pit entry yellow,
/// pit exit blue.
class TrackMapView extends StatelessWidget {
  /// Creates the map.
  const TrackMapView({
    required this.track,
    this.sectorLayout,
    this.liveFix,
    this.pendingPoints = const [],
    this.previewLine,
    this.imagery = MapImagery.satellite,
    this.onTap,
    this.interactive = true,
    this.pointMarkers = const [],
    this.pathLatLng = const [],
    this.controller,
    this.panOnly = false,
    this.focus,
    this.previewLabel = 'NEW',
    super.key,
  });

  /// Track whose lines are drawn.
  final Track track;

  /// Sector layout whose splits are drawn (default layout when null).
  final SectorLayout? sectorLayout;

  /// Current GPS position, drawn as a dot.
  final GpsFix? liveFix;

  /// Points tapped so far while placing a line.
  final List<LatLng> pendingPoints;

  /// Line being placed, drawn highlighted.
  final GateLine? previewLine;

  /// Background imagery.
  final MapImagery imagery;

  /// Called with the tapped coordinate.
  final void Function(LatLng point)? onTap;

  /// Whether the map can be panned and zoomed.
  final bool interactive;

  /// Labelled points, e.g. brake points: (latitude, longitude, label,
  /// highlighted).
  final List<(double, double, String, bool)> pointMarkers;

  /// A driven line to draw, e.g. the brake coach reference lap.
  final List<(double, double)> pathLatLng;

  /// Lets the parent move the map (e.g. "show all lines" button).
  final MapController? controller;

  /// Drag to move and pinch to zoom only (no tap actions); for maps inside
  /// a scrolling page.
  final bool panOnly;

  /// When set, the map opens zoomed in on this point instead of fitting
  /// every line (e.g. on the line being adjusted).
  final LatLng? focus;

  /// Label drawn next to [previewLine].
  final String previewLabel;

  /// Every timing line of [track] (start/finish, pit lines and the splits
  /// of [layout]) as map points, for "show all lines".
  static List<LatLng> linePoints(Track track, SectorLayout? layout) => [
    for (final line in [
      ?track.startFinish,
      ?track.pitEntry,
      ?track.pitExit,
      ...?layout?.splits,
    ])
      LatLng(line.latitude, line.longitude),
  ];

  /// Camera showing all [points] (or null when there are fewer than two
  /// distinct ones).
  static CameraFit? fitFor(List<LatLng> points) {
    if (points.toSet().length < 2) return null;
    return CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.all(48),
      maxZoom: 18,
    );
  }

  /// Package name sent to tile servers, as their usage policies require.
  static const String userAgentPackageName = 'com.pantanong.lap_timer';

  LatLng get _initialCentre {
    final line = track.startFinish ?? track.pitEntry ?? track.pitExit;
    if (line != null) return LatLng(line.latitude, line.longitude);
    final fix = liveFix;
    if (fix != null) return LatLng(fix.latitude, fix.longitude);
    // Chang International Circuit, Buriram — a sensible default.
    return const LatLng(14.9605, 103.0845);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final layout = sectorLayout ?? track.defaultSectorLayout;
    // Labels sit on different sides of their line so that lines close to
    // each other stay readable: S/F above, pit lines below, splits right.
    final lines = <(GateLine, Color, String, Alignment)>[
      if (track.startFinish case final l?)
        (l, Colors.white, 'S/F', Alignment.topCenter),
      if (track.pitEntry case final l?)
        (l, colors.warning, 'PIT IN', Alignment.bottomLeft),
      if (track.pitExit case final l?)
        (l, const Color(0xFF3B82F6), 'PIT OUT', Alignment.bottomRight),
      for (final (i, l) in (layout?.splits ?? const <GateLine>[]).indexed)
        (l, colors.accent, 'S${i + 1}|${i + 2}', Alignment.centerRight),
      if (previewLine case final l?)
        (l, colors.slower, previewLabel, Alignment.topCenter),
    ];
    final int flags;
    if (!interactive) {
      flags = InteractiveFlag.none;
    } else if (panOnly) {
      flags = InteractiveFlag.drag | InteractiveFlag.pinchZoom;
    } else {
      flags = InteractiveFlag.all & ~InteractiveFlag.rotate;
    }
    final fix = liveFix;
    final fit = fitFor([
      ...linePoints(track, layout),
      if (fix != null && track.startFinish == null)
        LatLng(fix.latitude, fix.longitude),
    ]);
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: focus ?? _initialCentre,
        initialZoom: focus == null ? 17 : 18.5,
        initialCameraFit: focus == null ? fit : null,
        maxZoom: 20,
        onTap: onTap == null ? null : (_, point) => onTap?.call(point),
        interactionOptions: InteractionOptions(flags: flags),
      ),
      children: [
        _tileLayer(),
        PolylineLayer(
          polylines: [
            if (pathLatLng.length >= 2)
              Polyline(
                points: [for (final (lat, lon) in pathLatLng) LatLng(lat, lon)],
                color: Colors.white.withValues(alpha: 0.5),
                strokeWidth: 2,
              ),
            for (final (line, color, _, _) in lines)
              if (_toPolyline(line) case final points?)
                Polyline(points: points, color: color, strokeWidth: 5),
          ],
        ),
        CircleLayer(
          circles: [
            // Lines set while standing still: only a point is known.
            for (final (line, color, _, _) in lines)
              if (line.endpoints() == null)
                CircleMarker(
                  point: LatLng(line.latitude, line.longitude),
                  radius: 6,
                  color: color,
                ),
            for (final (lat, lon, _, highlighted) in pointMarkers)
              CircleMarker(
                point: LatLng(lat, lon),
                radius: highlighted ? 10 : 7,
                color: highlighted ? colors.warning : colors.slower,
                borderColor: Colors.white,
                borderStrokeWidth: highlighted ? 3 : 1,
              ),
            for (final p in pendingPoints)
              CircleMarker(point: p, radius: 7, color: colors.slower),
            if (liveFix case final fix?)
              CircleMarker(
                point: LatLng(fix.latitude, fix.longitude),
                radius: 8,
                color: const Color(0xFF3B82F6),
                borderColor: Colors.white,
                borderStrokeWidth: 2,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final (lat, lon, label, _) in pointMarkers)
              Marker(
                point: LatLng(lat, lon),
                width: 40,
                height: 40,
                alignment: Alignment.bottomCenter,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    shadows: [Shadow(blurRadius: 3)],
                  ),
                ),
              ),
            for (final (line, color, label, alignment) in lines)
              Marker(
                point: LatLng(line.latitude, line.longitude),
                width: 70,
                height: 40,
                alignment: alignment,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    shadows: const [Shadow(blurRadius: 3)],
                  ),
                ),
              ),
          ],
        ),
        _attribution(),
      ],
    );
  }

  Widget _tileLayer() => switch (imagery) {
    MapImagery.satellite => TileLayer(
      urlTemplate:
          'https://server.arcgisonline.com/ArcGIS/rest/services/'
          'World_Imagery/MapServer/tile/{z}/{y}/{x}',
      userAgentPackageName: userAgentPackageName,
    ),
    MapImagery.street => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: userAgentPackageName,
    ),
  };

  // Small and never enlarged by the system font size, so the credit line
  // always fits on a phone map.
  Widget _attribution() => MediaQuery.withNoTextScaling(
    child: SimpleAttributionWidget(
      source: Text(switch (imagery) {
        MapImagery.satellite => 'Esri, Maxar, Earthstar Geographics',
        MapImagery.street => 'OpenStreetMap contributors',
      }, style: const TextStyle(fontSize: 11)),
    ),
  );

  static List<LatLng>? _toPolyline(GateLine line) {
    final ends = line.endpoints();
    if (ends == null) return null;
    final ((latA, lonA), (latB, lonB)) = ends;
    return [LatLng(latA, lonA), LatLng(latB, lonB)];
  }
}
