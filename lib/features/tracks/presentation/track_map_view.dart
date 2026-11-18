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

  /// Package name sent to tile servers, as their usage policies require.
  static const String userAgentPackageName = 'com.pantanong.lap_timer';

  LatLng get _initialCentre {
    final line = track.startFinish ?? track.pitEntry;
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
    final lines = <(GateLine, Color, String)>[
      if (track.startFinish case final l?) (l, Colors.white, 'S/F'),
      if (track.pitEntry case final l?) (l, colors.warning, 'PIT IN'),
      if (track.pitExit case final l?) (l, const Color(0xFF3B82F6), 'PIT OUT'),
      for (final (i, l) in (layout?.splits ?? const <GateLine>[]).indexed)
        (l, colors.accent, 'S${i + 1}|${i + 2}'),
      if (previewLine case final l?) (l, colors.slower, 'NEW'),
    ];
    return FlutterMap(
      options: MapOptions(
        initialCenter: _initialCentre,
        initialZoom: 17,
        maxZoom: 20,
        onTap: onTap == null ? null : (_, point) => onTap?.call(point),
        interactionOptions: InteractionOptions(
          flags: interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        _tileLayer(),
        PolylineLayer(
          polylines: [
            for (final (line, color, _) in lines)
              if (_toPolyline(line) case final points?)
                Polyline(points: points, color: color, strokeWidth: 5),
          ],
        ),
        CircleLayer(
          circles: [
            // Lines set while standing still: only a point is known.
            for (final (line, color, _) in lines)
              if (line.endpoints() == null)
                CircleMarker(
                  point: LatLng(line.latitude, line.longitude),
                  radius: 6,
                  color: color,
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
            for (final (line, color, label) in lines)
              Marker(
                point: LatLng(line.latitude, line.longitude),
                width: 70,
                height: 40,
                alignment: Alignment.topCenter,
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

  Widget _attribution() => SimpleAttributionWidget(
    source: Text(switch (imagery) {
      MapImagery.satellite => 'Esri, Maxar, Earthstar Geographics',
      MapImagery.street => 'OpenStreetMap contributors',
    }),
  );

  static List<LatLng>? _toPolyline(GateLine line) {
    final ends = line.endpoints();
    if (ends == null) return null;
    final ((latA, lonA), (latB, lonB)) = ends;
    return [LatLng(latA, lonA), LatLng(latB, lonB)];
  }
}
