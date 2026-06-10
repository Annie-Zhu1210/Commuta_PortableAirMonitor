import 'package:flutter/material.dart';
import '../../core/constants/app_colours.dart';
import '../../services/tfl_map_data.dart';
import 'tfl_map_painter.dart';

/// The TfL rail map view.
///
/// Phase 4 — Step 3 (current): base canvas. Loads bundled line + station
/// data via [TflMapData], renders the lines fitted to the screen's
/// bounding box, and wraps everything in an [InteractiveViewer] for pan
/// and zoom. The painter is told the current view scale so strokes stay
/// a constant thickness on screen regardless of zoom.
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

    return LayoutBuilder(
      builder: (context, constraints) {
        return InteractiveViewer(
          transformationController: _transformController,
          minScale: 0.6,
          maxScale: 200.0,
          boundaryMargin: EdgeInsets.zero,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: AnimatedBuilder(
              animation: _transformController,
              builder: (context, _) {
                final scale =
                    _transformController.value.getMaxScaleOnAxis();
                return CustomPaint(
                  painter: TflMapPainter(
                    lines: data.lines,
                    stations: data.stations,
                    viewScale: scale,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}