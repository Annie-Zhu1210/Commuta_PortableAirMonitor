import 'package:flutter/material.dart';

import '../../core/constants/app_colours.dart';
import '../../core/constants/map_constants.dart';
import '../../core/utils/daqi_utils.dart';
import '../../data/models/tfl_station.dart';
import '../../services/app_services.dart';
import '../../services/tfl_map_data.dart';
import '../../widgets/reading_floating_window.dart';
import 'station_picker.dart';
import 'tfl_map_painter.dart';

/// The TfL rail map view.
///
/// Phase 5: the sage halo behind the user's currently classified station
/// is driven by the [StationClassificationService], which owns the
/// `currentStationId` notifier. This view just listens to that notifier
/// and repaints — it no longer owns or mutates the classified-station
/// state.
///
/// Session 1 (manual override) added a chip pinned top-centre over the
/// map. The chip has three visual states:
///   • No station tagged — "No station tagged — tap to set"
///   • Auto-tagged      — "Tagging: <n>" + auto badge + ✕
///   • Manual-tagged    — "Tagging: <n>" + manual badge + ✕
///
/// Session 2 wired dwell detection into the classification service, so
/// the auto state is now reachable: stand within 100 m of a station for
/// 60 s and the chip flips to auto-tagged without any user action. The
/// ✕ now calls the generalised `clearStation()` (Session 2, Decision 1),
/// so clearing works identically for auto and manual tags.
/// The chip replaces the "Can't detect a TfL station" corner indicator
/// that was planned for Phase 5 Step 5 — one surface, one state, one
/// action.
///
/// Session 4 (visited-station colouring) adds a third notifier to the
/// paint pipeline: `visitedStationsToday` on the classification service.
/// The view resolves each visited station's [DaqiBand] into an
/// [AppColours] value and hands the resulting `Map<String, Color>` to
/// the painter, which colours non-interchange dots (enlarged) and
/// recolours the interchange ring stroke. Notifier updates happen as
/// new classified readings arrive (per-reading, live) and on day
/// rollover (via a service-side periodic wall-clock check that ticks
/// every 60 s and rehydrates when the local date has advanced).
///
/// Session 5 (station tap → timestamp list → reading detail) wraps the
/// [InteractiveViewer]'s child in a [GestureDetector] so tapping a
/// station dot opens the shared [ReadingFloatingWindow] with today's
/// readings for that station. All stations are tappable, including
/// unvisited ones — an unvisited tap opens the window with the
/// "No readings collected here today." empty state (Session 5,
/// Decision 3). Nearest-dot wins when multiple dots fall inside the
/// tap radius (Decision 7). Static snapshot: the window doesn't
/// live-update while it's open (Decision 5).
class TflMapView extends StatefulWidget {
  const TflMapView({super.key});

  @override
  State<TflMapView> createState() => _TflMapViewState();
}

class _TflMapViewState extends State<TflMapView> {
  late final Future<void> _loadFuture;
  final TransformationController _transformController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    _loadFuture = TflMapData.instance.load();
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  // ── Chip actions ────────────────────────────────────────────────────────

  Future<void> _openPicker() async {
    final pickedId = await showStationPicker(context);
    if (!mounted || pickedId == null) return;
    AppServices.instance.classificationService
        .setStationManually(pickedId);
  }

  void _clearTag() {
    AppServices.instance.classificationService.clearStation();
  }

  // ── Band → colour mapping ───────────────────────────────────────────────
  // Local because it's the only place the map needs it, and keeps the
  // painter decoupled from `DaqiBand` and `AppColours`.
  static Color _bandColour(DaqiBand band) {
    switch (band) {
      case DaqiBand.low:
        return AppColours.daqiLow;
      case DaqiBand.moderate:
        return AppColours.daqiModerate;
      case DaqiBand.high:
        return AppColours.daqiHigh;
      case DaqiBand.veryHigh:
        return AppColours.daqiVeryHigh;
    }
  }

  // ── Tap handling (Session 5) ────────────────────────────────────────────

  /// Fires on a discrete tap-and-release inside the map canvas.
  ///
  /// The [GestureDetector] wraps the [InteractiveViewer]'s *child*
  /// (the [SizedBox]), which is inside the transform. As a result,
  /// [TapUpDetails.localPosition] is in the child's own coordinate
  /// space — i.e. scene (untransformed) coordinates — so no
  /// `_transformController.toScene(...)` conversion is needed. See
  /// the Session 5 handoff, Note 2.
  ///
  /// Pans and pinches never reach this handler: Flutter's tap gesture
  /// recogniser rejects the sequence once the pointer travels beyond
  /// the tap-slop threshold, so those gestures continue to route to
  /// [InteractiveViewer] as before.
  void _onTapUp(TapUpDetails details, Size mapSize) {
    final data = TflMapData.instance;
    if (data.stations.isEmpty) return;

    final scenePoint = details.localPosition;
    final viewScale = _transformController.value.getMaxScaleOnAxis();

    final station = _findStationAtTap(scenePoint, mapSize, viewScale);
    if (station == null) return;

    _openStationReadings(station);
  }

  /// Return the tapped station, or null if no dot falls within the
  /// on-screen tap radius.
  ///
  /// The projector is reconstructed with the same bounds, size and
  /// padding the painter uses inside its `paint()` method, so a
  /// station's projected canvas position here is bit-for-bit identical
  /// to where its dot was drawn. The tap radius is defined in
  /// on-screen pixels ([MapConstants.tflMapTapRadiusPixels]) and
  /// divided by [viewScale] to arrive at a scene-space radius — so the
  /// user perceives the same tap slop at every zoom level.
  ///
  /// When multiple dots fall inside the radius (dense central London,
  /// e.g. King's Cross ↔ Euston at low zoom), the one whose centre is
  /// closest to the tap point wins (Session 5, Decision 7).
  TflStation? _findStationAtTap(
    Offset scenePoint,
    Size mapSize,
    double viewScale,
  ) {
    final data = TflMapData.instance;
    final projector = TflMapProjector(
      bounds: TflMapBounds.forStations(data.stations),
      size: mapSize,
      padding: TflMapPainter.defaultPadding,
    );

    final effectiveScale = viewScale > 0.01 ? viewScale : 1.0;
    final tapRadiusScene =
        MapConstants.tflMapTapRadiusPixels / effectiveScale;
    final tapRadiusSquared = tapRadiusScene * tapRadiusScene;

    TflStation? nearest;
    double nearestDistSquared = double.infinity;

    for (final station in data.stations) {
      final dotCentre = projector.project(station.position);
      final dx = dotCentre.dx - scenePoint.dx;
      final dy = dotCentre.dy - scenePoint.dy;
      final distSquared = dx * dx + dy * dy;
      if (distSquared > tapRadiusSquared) continue;
      if (distSquared < nearestDistSquared) {
        nearestDistSquared = distSquared;
        nearest = station;
      }
    }
    return nearest;
  }

  /// Query today's readings for [station] and open the shared
  /// [ReadingFloatingWindow]. Uses the static-snapshot helper
  /// (Session 5, Decision 5) — new readings that land while the window
  /// is open don't appear until the user closes and reopens it. The
  /// empty case is handled inside the widget via [emptyMessage]
  /// (Session 5, Decision 2).
  Future<void> _openStationReadings(TflStation station) async {
    final readings = await AppServices.instance.readingsRepository
        .getReadingsForStationOnDate(station.id, DateTime.now());
    if (!mounted) return;
    await showReadingFloatingWindow(
      context,
      readings: readings,
      title: station.displayName,
      emptyMessage: 'No readings collected here today.',
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColours.background,
      child: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildLoading();
          }
          if (snapshot.hasError) {
            return _buildError(snapshot.error);
          }
          return _buildMap();
        },
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation(AppColours.accent),
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Loading Tube map…',
            style: TextStyle(
              fontSize: 13,
              color: AppColours.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 40,
              color: AppColours.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              "Couldn't load the Tube map",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColours.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              style: TextStyle(
                fontSize: 12,
                color: AppColours.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    final data = TflMapData.instance;
    final service = AppServices.instance.classificationService;
    final classifiedStationId = service.currentStationId;
    final manualOverride = service.manualOverride;
    final visitedStationsToday = service.visitedStationsToday;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Captured once per layout pass and passed into the tap handler
        // via closure. Matches the size the painter sees when its
        // CustomPaint is laid out by the SizedBox below.
        final mapSize = Size(constraints.maxWidth, constraints.maxHeight);

        return Stack(
          children: [
            // ── Map canvas ──────────────────────────────────────────────
            InteractiveViewer(
              transformationController: _transformController,
              minScale: 0.6,
              maxScale: 200.0,
              boundaryMargin: EdgeInsets.zero,
              // Session 5: GestureDetector wraps the SizedBox (the
              // InteractiveViewer's child), not the InteractiveViewer
              // itself. Pans and pinches continue to route to
              // InteractiveViewer's own recognisers; only discrete
              // taps reach `_onTapUp`.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _onTapUp(details, mapSize),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _transformController,
                      classifiedStationId,
                      visitedStationsToday,
                    ]),
                    builder: (context, _) {
                      final scale =
                          _transformController.value.getMaxScaleOnAxis();
                      final id = classifiedStationId.value;
                      final TflStation? classified =
                          id == null ? null : data.stationById(id);

                      // Session 4: resolve station → band → colour once
                      // per rebuild. Typical daily size is well under 50
                      // entries; nothing to optimise here.
                      final bands = visitedStationsToday.value;
                      final visitedColours = <String, Color>{
                        for (final entry in bands.entries)
                          entry.key: _bandColour(entry.value),
                      };

                      return CustomPaint(
                        painter: TflMapPainter(
                          lines: data.lines,
                          stations: data.stations,
                          viewScale: scale,
                          classifiedStation: classified,
                          visitedStationColours: visitedColours,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            // ── Chip pinned top-centre-floating over the map ────────────
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Center(
                child: AnimatedBuilder(
                  animation: Listenable.merge(
                    [classifiedStationId, manualOverride],
                  ),
                  builder: (context, _) {
                    return _StationTagChip(
                      stationId: classifiedStationId.value,
                      isManual: manualOverride.value,
                      onTapMainArea: _openPicker,
                      onTapClear: _clearTag,
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Chip — the map's single status/action surface.
//
// Layout:
//   [icon] [text] [source badge]  │  [✕]
//   └──── main tap area ─────────┘   └ clear
//
// When no station is tagged the divider + ✕ are hidden and the whole
// chip becomes one tap target that opens the picker.
// ─────────────────────────────────────────────────────────────────────────

class _StationTagChip extends StatelessWidget {
  const _StationTagChip({
    required this.stationId,
    required this.isManual,
    required this.onTapMainArea,
    required this.onTapClear,
  });

  final String? stationId;
  final bool isManual;
  final VoidCallback onTapMainArea;
  final VoidCallback onTapClear;

  bool get _hasStation => stationId != null;

  @override
  Widget build(BuildContext context) {
    final station =
        _hasStation ? TflMapData.instance.stationById(stationId!) : null;
    final displayName = station?.displayName ?? stationId ?? '';

    return Material(
      color: AppColours.surface,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: AppColours.textSecondary.withValues(alpha: 0.15),
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Main area: opens picker on tap ────────────────────────
              Flexible(
                child: InkWell(
                  onTap: onTapMainArea,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(22),
                    bottomLeft: const Radius.circular(22),
                    topRight:
                        _hasStation ? Radius.zero : const Radius.circular(22),
                    bottomRight:
                        _hasStation ? Radius.zero : const Radius.circular(22),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _hasStation
                              ? Icons.place
                              : Icons.place_outlined,
                          size: 18,
                          color: _hasStation
                              ? AppColours.accent
                              : AppColours.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _hasStation
                                ? 'Tagging: $displayName'
                                : 'No station tagged — tap to set',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _hasStation
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: _hasStation
                                  ? AppColours.textPrimary
                                  : AppColours.textSecondary,
                            ),
                          ),
                        ),
                        if (_hasStation) ...[
                          const SizedBox(width: 8),
                          _SourceBadge(isManual: isManual),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // ── Divider + ✕: separate tap target for clearing ─────────
              if (_hasStation) ...[
                Container(
                  width: 1,
                  color: AppColours.textSecondary.withValues(alpha: 0.2),
                  margin: const EdgeInsets.symmetric(vertical: 10),
                ),
                InkWell(
                  onTap: onTapClear,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(22),
                    bottomRight: Radius.circular(22),
                  ),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: AppColours.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small text pill differentiating auto vs manual tags.
///
/// Manual → sage accent (the "user-driven" primary).
/// Auto   → dusty blue-grey accentSecondary (the "computed" secondary).
/// Both colour + text so accessible via either channel alone.
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.isManual});

  final bool isManual;

  @override
  Widget build(BuildContext context) {
    final colour =
        isManual ? AppColours.accent : AppColours.accentSecondary;
    final label = isManual ? 'manual' : 'auto';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: colour,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}