import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../core/constants/app_colours.dart';
import '../core/constants/map_constants.dart';
import '../core/utils/daqi_utils.dart';

/// Builds AQI marker bitmaps for the Google Map view.
///
/// Each marker is a small coloured circle with the numeric AQI value
/// in the centre. The colour comes from the DAQI band; the number
/// comes from the placeholder overall AQI computation.
///
/// Bitmaps are cached by "${band}_$displayValue" since the same
/// (band, value) pair always produces the same bitmap.
class AqiMarkerBuilder {
  AqiMarkerBuilder._();

  /// Pure-function of (band, displayValue), so caching is safe.
  static final Map<String, BitmapDescriptor> _cache = {};

  static Future<BitmapDescriptor> build({
    required DaqiBand band,
    required int displayValue,
    double devicePixelRatio = 3.0,
  }) async {
    final key = '${band.name}_$displayValue';
    if (_cache.containsKey(key)) return _cache[key]!;

    final pixelSize = MapConstants.markerLogicalSize * devicePixelRatio;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final centre = Offset(pixelSize / 2, pixelSize / 2);
    final ringRadius = pixelSize * 0.45;
    final fillRadius = pixelSize * 0.40;

    // Soft drop shadow
    canvas.drawCircle(
      centre + Offset(0, 2 * devicePixelRatio),
      ringRadius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          4 * devicePixelRatio,
        ),
    );

    // White outer ring
    canvas.drawCircle(centre, ringRadius, Paint()..color = Colors.white);

    // Coloured fill
    canvas.drawCircle(
      centre,
      fillRadius,
      Paint()..color = _colourForBand(band),
    );

    // Number
    final tp = TextPainter(
      text: TextSpan(
        text: '$displayValue',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: pixelSize * 0.32,
          fontFamily: 'Inter',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(
      canvas,
      Offset(
        (pixelSize - tp.width) / 2,
        (pixelSize - tp.height) / 2,
      ),
    );

    final image = await recorder.endRecording().toImage(
      pixelSize.toInt(),
      pixelSize.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    // Note: if your google_maps_flutter version doesn't expose
    // BitmapDescriptor.bytes, swap this for:
    //   BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List())
    final desc = BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      imagePixelRatio: devicePixelRatio,
    );
    _cache[key] = desc;
    return desc;
  }

  static Color _colourForBand(DaqiBand band) {
    switch (band) {
      case DaqiBand.low:      return AppColours.daqiLow;
      case DaqiBand.moderate: return AppColours.daqiModerate;
      case DaqiBand.high:     return AppColours.daqiHigh;
      case DaqiBand.veryHigh: return AppColours.daqiVeryHigh;
    }
  }
}