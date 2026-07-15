import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../core/constants/app_colours.dart';
import '../core/constants/map_constants.dart';
import '../core/utils/daqi_utils.dart';

/// Builds AQI marker bitmaps for the Google Map view.
///
/// Each marker is a small coloured circle with the numeric AQI value
/// in the centre. The colour comes from the severity band and the
/// number is the 0–100 score — both supplied by `MapAqiScore`, which
/// delegates to the Home hero's scoring so the two surfaces always
/// agree.
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
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * devicePixelRatio),
    );

    // White outer ring
    canvas.drawCircle(centre, ringRadius, Paint()..color = Colors.white);

    // Coloured fill
    canvas.drawCircle(
      centre,
      fillRadius,
      Paint()..color = _colourForBand(band),
    );

    // Number. The hero score is clamped to 0–100, so the only
    // three-digit value is 100 — shrink the font just for that case
    // so it sits inside the disc with the same visual weight as the
    // one- and two-digit values (which keep the original 0.32 ratio).
    final fontRatio = displayValue >= 100 ? 0.27 : 0.32;
    final tp = TextPainter(
      text: TextSpan(
        text: '$displayValue',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: pixelSize * fontRatio,
          fontFamily: 'Inter',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(
      canvas,
      Offset((pixelSize - tp.width) / 2, (pixelSize - tp.height) / 2),
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

  /// Builds the collection-marker bitmap: three overlapping coloured
  /// discs, no number in the centre, dominant colour = worst band
  /// across the collection's readings (each reading's band coming
  /// from `MapAqiScore`, so single and collection markers agree).
  /// The cache key uses only the band, so appending readings without
  /// a band change is free.
  static Future<BitmapDescriptor> buildCollection({
    required DaqiBand dominantBand,
    double devicePixelRatio = 3.0,
  }) async {
    final key = 'collection_${dominantBand.name}';
    if (_cache.containsKey(key)) return _cache[key]!;

    final base = MapConstants.markerLogicalSize * devicePixelRatio;
    // Slightly larger canvas so the stacked offsets aren't clipped.
    final canvasSize = base * 1.25;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final centre = Offset(canvasSize / 2, canvasSize / 2);
    final discRadius = base * 0.38;
    final ringWidth = base * 0.05;
    final offset = base * 0.10;
    final fill = _colourForBand(dominantBand);

    // Three discs, drawn back-to-front along a top-left diagonal.
    final centres = <Offset>[
      centre + Offset(offset, offset), // bottom-right (back)
      centre, // middle
      centre + Offset(-offset, -offset), // top-left (front)
    ];

    for (final c in centres) {
      // Soft drop shadow
      canvas.drawCircle(
        c + Offset(0, 2 * devicePixelRatio),
        discRadius,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.18)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            4 * devicePixelRatio,
          ),
      );
      // White outer ring
      canvas.drawCircle(c, discRadius, Paint()..color = Colors.white);
      // Coloured inner fill
      canvas.drawCircle(c, discRadius - ringWidth, Paint()..color = fill);
    }

    final image = await recorder.endRecording().toImage(
      canvasSize.toInt(),
      canvasSize.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    final desc = BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      imagePixelRatio: devicePixelRatio,
    );
    _cache[key] = desc;
    return desc;
  }

  static Color _colourForBand(DaqiBand band) {
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
}