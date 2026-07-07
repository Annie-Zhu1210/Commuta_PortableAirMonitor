import 'package:flutter/material.dart';

import '../../core/constants/app_colours.dart';
import '../../data/models/tfl_station.dart';
import '../../services/app_services.dart';
import '../../services/tfl_map_data.dart';
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
///   • Auto-tagged      — "Tagging: <name>" + auto badge + ✕
///   • Manual-tagged    — "Tagging: <name>" + manual badge + ✕
///
/// Session 2 wired dwell detection into the classification service, so
/// the auto state is now reachable: stand within 100 m of a station for
/// 60 s and the chip flips to auto-tagged without any user action. The
/// ✕ now calls the generalised `clearStation()` (Session 2, Decision 1),
/// so clearing works identically for auto and manual tags.
/// The chip replaces the "Can't detect a TfL station" corner indicator
/// that was planned for Phase 5 Step 5 — one surface, one state, one
/// action.
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

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // ── Map canvas ──────────────────────────────────────────────
            InteractiveViewer(
              transformationController: _transformController,
              minScale: 0.6,
              maxScale: 200.0,
              boundaryMargin: EdgeInsets.zero,
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: AnimatedBuilder(
                  animation: Listenable.merge(
                    [_transformController, classifiedStationId],
                  ),
                  builder: (context, _) {
                    final scale =
                        _transformController.value.getMaxScaleOnAxis();
                    final id = classifiedStationId.value;
                    final TflStation? classified =
                        id == null ? null : data.stationById(id);
                    return CustomPaint(
                      painter: TflMapPainter(
                        lines: data.lines,
                        stations: data.stations,
                        viewScale: scale,
                        classifiedStation: classified,
                      ),
                    );
                  },
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