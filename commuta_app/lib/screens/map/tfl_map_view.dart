import 'package:flutter/material.dart';
import '../../core/constants/app_colours.dart';
import '../../data/models/tfl_station.dart';
import '../../services/app_services.dart';
import '../../services/tfl_map_data.dart';
import 'tfl_map_painter.dart';

/// The TfL rail map view.
///
/// Phase 5: the sage halo behind the user's currently classified station
/// is driven by the StationClassificationService, which owns the
/// `currentStationId` notifier. This view just listens to that notifier
/// and repaints — it no longer owns or mutates the classified-station
/// state. The Phase 4 debug cycler chip has been removed now that real
/// auto-classification supplies the value.
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
    final classifiedStationId =
        AppServices.instance.classificationService.currentStationId;

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

            // Step 5 will add the "Can't detect a TfL station" corner
            // indicator here — the slot the debug cycler used to occupy.
          ],
        );
      },
    );
  }
}