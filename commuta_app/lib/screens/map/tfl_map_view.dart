import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_colours.dart';
import '../../data/models/tfl_station.dart';
import '../../services/tfl_map_data.dart';
import 'tfl_map_painter.dart';

/// The TfL rail map view.
///
/// Phase 4 — Step 5 (current): base canvas plus a sage halo behind the
/// currently classified station. The classified station ID lives in a
/// `ValueNotifier<String?>` owned by this widget — when Phase 5
/// arrives, the auto-classification service will take ownership and
/// drive the notifier from real device + GPS data, without needing
/// any change to the painter.
///
/// In debug builds a small floating chip in the top-right corner
/// cycles through a handful of well-known station IDs (plus null) so
/// the halo can be verified visually before auto-classification
/// exists. Stripped from release builds via `kDebugMode`.
class TflMapView extends StatefulWidget {
  const TflMapView({super.key});

  @override
  State<TflMapView> createState() => _TflMapViewState();
}

class _TflMapViewState extends State<TflMapView> {
  late final Future<void> _loadFuture;
  final TransformationController _transformController =
      TransformationController();

  /// The ID of the station the user is currently classified to, or
  /// null if no station is detected. Drives the halo.
  ///
  /// Owned here for Step 5; will be lifted out and owned by the
  /// auto-classification service when Phase 5 arrives.
  final ValueNotifier<String?> _classifiedStationId = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    _loadFuture = TflMapData.instance.load();
  }

  @override
  void dispose() {
    _classifiedStationId.dispose();
    _transformController.dispose();
    super.dispose();
  }

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

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
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
                    [_transformController, _classifiedStationId],
                  ),
                  builder: (context, _) {
                    final scale =
                        _transformController.value.getMaxScaleOnAxis();
                    final id = _classifiedStationId.value;
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
            if (kDebugMode)
              Positioned(
                top: 16,
                right: 16,
                child: _DevClassifiedStationCycler(
                  notifier: _classifiedStationId,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Debug-only floating chip that cycles through a few hardcoded
/// station IDs (plus null) so the halo can be visually verified
/// before real auto-classification exists.
///
/// Replace or remove once Phase 5 auto-classification is wired up.
class _DevClassifiedStationCycler extends StatelessWidget {
  const _DevClassifiedStationCycler({required this.notifier});

  final ValueNotifier<String?> notifier;

  /// Naptan IDs for a few well-known stations. If any of these aren't
  /// in your `stations.json`, the chip will show "? <id>" and the
  /// halo simply won't draw for that step.
  static const List<String?> _cycleIds = [
    null,
    '940GZZLUKSX', // King's Cross St Pancras (large interchange)
    '940GZZLURSQ', // Russell Square (Piccadilly only — tests the small 3px dot)
    '940GZZLUOXC', // Oxford Circus (mid interchange, different position)
  ];

  void _cycle() {
    final currentIndex = _cycleIds.indexOf(notifier.value);
    final nextIndex = (currentIndex + 1) % _cycleIds.length;
    notifier.value = _cycleIds[nextIndex];
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColours.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _cycle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: ValueListenableBuilder<String?>(
            valueListenable: notifier,
            builder: (context, id, _) {
              final String label;
              if (id == null) {
                label = 'No station';
              } else {
                final station = TflMapData.instance.stationById(id);
                label = station?.displayName ?? '? $id';
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.sync,
                    size: 14,
                    color: AppColours.accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColours.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'DEV',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColours.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}