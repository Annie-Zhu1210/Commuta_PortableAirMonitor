import 'package:flutter/material.dart';
import '../../widgets/map_view_toggle.dart';
import 'google_map_view.dart';
import 'tfl_map_view.dart';

/// The Map tab — hosts the Google Map view, the TfL map view (placeholder
/// until Phase 4), and the toggle that switches between them.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapViewType _selected = MapViewType.google;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // IndexedStack keeps both child views mounted so markers,
        // camera position, etc. survive switching between Tube ↔ Map —
        // mirroring how the outer bottom-nav IndexedStack behaves.
        Positioned.fill(
          child: IndexedStack(
            index: _selected == MapViewType.google ? 0 : 1,
            children: const [
              GoogleMapView(),
              TflMapView(),
            ],
          ),
        ),

        // Toggle pinned to the bottom-right corner.
        Positioned(
          bottom: 100,
          right: 16,
          child: MapViewToggle(
            selected: _selected,
            onChanged: (v) => setState(() => _selected = v),
          ),
        ),
      ],
    );
  }
}