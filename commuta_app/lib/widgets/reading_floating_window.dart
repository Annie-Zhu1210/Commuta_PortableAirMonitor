import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/constants/app_colours.dart';
import '../core/utils/daqi_utils.dart';
import '../data/models/air_quality_reading.dart';

/// Floating window shown when the user taps an air-quality marker.
///
/// Three modes, chosen automatically from `readings.value.length`
/// and [emptyMessage]:
///   - Length 0 → renders [emptyMessage] centred (or a blank body if
///                no message was supplied). No detail path, no back
///                nav. The header title stays whatever [title] is,
///                so the user still sees which station they tapped.
///   - Length 1 → opens straight into the detail view (no back nav).
///   - Length >1 → opens as a scrollable timestamp list; tapping a
///                 timestamp drills into detail with a back arrow.
///
/// The widget listens to [readings] and rebuilds whenever its value
/// changes, so collection windows stay in sync with newly-appended
/// readings while still open.
///
/// Reusable across the Google Map view and the TfL map (Phase 5).
/// Spec §4.5, §4.6, §3.4.
///
/// Session 5 (station tap → timestamp list → reading detail): added
/// the optional [emptyMessage] parameter and the empty-list branch,
/// so the TfL map can tap a station that hasn't collected any
/// readings today and still open the window with a graceful "no
/// readings" body. Prior to this change the widget would have
/// crashed on `_readings.first` if handed an empty list.
class ReadingFloatingWindow extends StatefulWidget {
  /// Live source of readings. The widget rebuilds when this fires.
  final ValueListenable<List<AirQualityReading>> readings;

  /// Optional override for the list-view header. Defaults to
  /// "N readings" when the list is non-empty; when empty and no title
  /// is supplied, falls back to "0 readings". The TfL map passes a
  /// station name here.
  final String? title;

  /// Message shown centred in the body when [readings] is empty.
  /// When null, the body is left blank in the empty case. Used by the
  /// TfL map's station-tap flow (Session 5) to render "No readings
  /// collected here today." for unvisited or dry-tapped stations.
  final String? emptyMessage;

  const ReadingFloatingWindow({
    super.key,
    required this.readings,
    this.title,
    this.emptyMessage,
  });

  @override
  State<ReadingFloatingWindow> createState() => _ReadingFloatingWindowState();
}

class _ReadingFloatingWindowState extends State<ReadingFloatingWindow> {
  /// In collection mode, which reading is being viewed in detail.
  /// `null` means the timestamp-list view is showing.
  AirQualityReading? _selectedReading;

  List<AirQualityReading> get _readings => widget.readings.value;

  bool get _isEmpty => _readings.isEmpty;

  bool get _isCollection => _readings.length > 1;

  /// True when the detail panel should be shown.
  /// Empty mode never shows detail; single-reading mode is always in
  /// detail; collection mode shows detail only after a timestamp
  /// has been selected.
  bool get _showingDetail =>
      !_isEmpty && (!_isCollection || _selectedReading != null);

  /// Only safe to read when `!_isEmpty`. All call sites are already
  /// guarded by [_showingDetail] which folds `!_isEmpty` in.
  AirQualityReading get _detailReading => _selectedReading ?? _readings.first;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    widget.readings.addListener(_onReadingsChanged);
  }

  @override
  void didUpdateWidget(ReadingFloatingWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.readings != widget.readings) {
      oldWidget.readings.removeListener(_onReadingsChanged);
      widget.readings.addListener(_onReadingsChanged);
    }
  }

  @override
  void dispose() {
    widget.readings.removeListener(_onReadingsChanged);
    super.dispose();
  }

  void _onReadingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // In collection-detail mode, the system back button should return
      // to the list rather than dismissing the whole dialog. In empty
      // and single-reading modes there is no list to fall back to, so
      // the system back button dismisses the dialog as normal.
      canPop: !(_isCollection && _selectedReading != null),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() => _selectedReading = null);
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360, maxHeight: 540),
          decoration: BoxDecoration(
            color: AppColours.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              Flexible(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  // ── Body dispatch ─────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_isEmpty) return _buildEmpty();
    if (_showingDetail) return _buildDetail(_detailReading);
    return _buildList();
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final showBack = _isCollection && _selectedReading != null;
    final titleText = _showingDetail
        ? _formatTimestamp(_detailReading.timestamp)
        : (widget.title ?? '${_readings.length} readings');

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          // Back button slot (only in collection detail)
          SizedBox(
            width: 40,
            height: 40,
            child: showBack
                ? IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      size: 20,
                      color: AppColours.textPrimary,
                    ),
                    onPressed: () => setState(() => _selectedReading = null),
                    tooltip: 'Back to list',
                  )
                : null,
          ),
          Expanded(
            child: Center(
              child: Text(
                titleText,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColours.textPrimary,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            height: 40,
            child: IconButton(
              icon: Icon(
                Icons.close,
                size: 20,
                color: AppColours.textSecondary,
              ),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Close',
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty view (no readings) ─────────────────────────────────────────────

  /// Rendered when the readings list is empty. Shows [emptyMessage]
  /// centred; if the caller didn't provide one, the body is blank
  /// so the header + close button still act as a sensible dismiss
  /// surface.
  Widget _buildEmpty() {
    final message = widget.emptyMessage;
    if (message == null) {
      return const SizedBox(height: 80);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: AppColours.textSecondary,
          ),
        ),
      ),
    );
  }

  // ── Detail view ───────────────────────────────────────────────────────────

  Widget _buildDetail(AirQualityReading r) {
    final rows = <_MetricRow>[
      _MetricRow(
        'PM1',
        _fmt1dp(r.pm1),
        'µg/m³',
        DaqiUtils.forPm1(r.pm1).colour,
      ),
      _MetricRow(
        'PM2.5',
        _fmt1dp(r.pm25),
        'µg/m³',
        DaqiUtils.forPm25(r.pm25).colour,
      ),
      _MetricRow(
        'PM10',
        _fmt1dp(r.pm10),
        'µg/m³',
        DaqiUtils.forPm10(r.pm10).colour,
      ),
      _MetricRow('CO₂', _fmtInt(r.co2), 'ppm', DaqiUtils.forCo2(r.co2).colour),
      _MetricRow(
        'Temperature',
        _fmt1dp(r.temperature),
        '°C',
        DaqiUtils.forTemperature(r.temperature).colour,
      ),
      _MetricRow(
        'Humidity',
        _fmt1dp(r.humidity),
        '%',
        DaqiUtils.forHumidity(r.humidity).colour,
      ),
      _MetricRow(
        'Pressure',
        _fmt1dp(r.pressure),
        'hPa',
        DaqiUtils.forPressure(r.pressure).colour,
      ),
    ];

    // Pressure Change — null on the very first reading
    // (no prior pressure to compare to).
    if (r.pressureChangePaPerSec != null) {
      rows.add(
        _MetricRow(
          'Pressure Change',
          _fmt1dp(r.pressureChangePaPerSec!),
          'Pa/s',
          DaqiUtils.forPressureGradient(r.pressureChangePaPerSec!).colour,
        ),
      );
    }

    // Sensor-optional metrics (SGP41 not yet wired).
    final vocInfo = DaqiUtils.forTvoc(r.tvoc);
    if (vocInfo != null) {
      rows.add(_MetricRow('VOC Index', _fmtInt(r.tvoc!), '', vocInfo.colour));
    }
    final noxInfo = DaqiUtils.forNox(r.nox);
    if (noxInfo != null) {
      rows.add(_MetricRow('NOx Index', _fmtInt(r.nox!), '', noxInfo.colour));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows.map(_buildMetricRow).toList(),
      ),
    );
  }

  Widget _buildMetricRow(_MetricRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              row.label,
              style: TextStyle(fontSize: 14, color: AppColours.textPrimary),
            ),
          ),
          Text(
            row.value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: row.colour,
            ),
          ),
          if (row.unit.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              row.unit,
              style: TextStyle(fontSize: 13, color: AppColours.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  // ── List view (collection mode) ───────────────────────────────────────────

  Widget _buildList() {
    final readings = _readings;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
      shrinkWrap: true,
      itemCount: readings.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, thickness: 1, color: AppColours.background),
      itemBuilder: (_, i) {
        final r = readings[i];
        return InkWell(
          onTap: () => setState(() => _selectedReading = r),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _formatTimestamp(r.timestamp),
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColours.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColours.textSecondary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Formatters ────────────────────────────────────────────────────────────

  String _formatTimestamp(DateTime ts) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(ts.hour)}:${two(ts.minute)}:${two(ts.second)}';
  }

  String _fmtInt(double v) => v.round().toString();
  String _fmt1dp(double v) => v.toStringAsFixed(1);
}

class _MetricRow {
  final String label;
  final String value;
  final String unit;
  final Color colour;

  const _MetricRow(this.label, this.value, this.unit, this.colour);
}

/// Convenience helper for a one-off, static reading or list.
/// Wraps the list in a [ValueNotifier] internally and disposes it
/// when the dialog closes — use this for single-marker taps where
/// the data won't change while the window is open.
///
/// [emptyMessage], if provided, is rendered centred in the body when
/// [readings] is empty. Used by the TfL map's station-tap flow
/// (Session 5) to surface "No readings collected here today." for
/// stations that have no data yet.
Future<void> showReadingFloatingWindow(
  BuildContext context, {
  required List<AirQualityReading> readings,
  String? title,
  String? emptyMessage,
}) {
  final notifier = ValueNotifier<List<AirQualityReading>>(readings);
  return showLiveReadingFloatingWindow(
    context,
    readings: notifier,
    title: title,
    emptyMessage: emptyMessage,
  ).whenComplete(notifier.dispose);
}

/// Live variant: the widget rebuilds whenever [readings] changes.
/// Use this for collection-marker taps so newly-appended readings
/// appear while the window is open. The caller owns the notifier
/// and is responsible for disposing it (typically in the screen's
/// dispose method).
///
/// [emptyMessage] behaves as documented on [ReadingFloatingWindow].
Future<void> showLiveReadingFloatingWindow(
  BuildContext context, {
  required ValueListenable<List<AirQualityReading>> readings,
  String? title,
  String? emptyMessage,
}) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => ReadingFloatingWindow(
      readings: readings,
      title: title,
      emptyMessage: emptyMessage,
    ),
  );
}