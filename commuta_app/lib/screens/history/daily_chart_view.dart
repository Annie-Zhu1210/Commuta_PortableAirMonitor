import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colours.dart';
import '../../core/utils/daqi_utils.dart';
import '../../data/models/air_quality_reading.dart';

/// Chip labels for the four metric groups, in tab order. The History
/// screen shell renders these as its group chip row; the index it
/// keeps in state maps straight onto [DailyChartView.groupIndex].
const List<String> historyMetricGroupLabels = [
  'PM values',
  'CO₂',
  'Temp · Humidity · Pressure',
  'NOx · TVOC',
];

/// Daily view of the History tab (Session 7a).
///
/// Renders the selected metric group as a vertical list of chart
/// cards — one card per metric (e.g. the "PM values" group stacks
/// PM2.5, PM10 and PM1 top to bottom). All cards share the single
/// day-of-readings list loaded by the shell.
class DailyChartView extends StatelessWidget {
  const DailyChartView({
    super.key,
    required this.readings,
    required this.date,
    required this.groupIndex,
  });

  /// The selected day's readings, ascending by timestamp.
  final List<AirQualityReading> readings;

  /// The selected day (date-only, local time). Used to key the cards
  /// so their scroll/selection state resets when the date changes.
  final DateTime date;

  /// Index into [historyMetricGroupLabels].
  final int groupIndex;

  // ── Metric group definitions ────────────────────────────────────
  // Band boundaries, colours and units all come from the existing
  // MetricScales specs in daqi_utils.dart, so the chart backgrounds
  // stay automatically consistent with the Home screen's cards.
  //
  // zeroBasedAxis:
  //   true  → y-axis spans 0 → data max + 10 % (pollutant metrics)
  //   false → y-axis spans a padded data range (comfort metrics —
  //           a 0-based axis would flatten pressure at ~1000 hPa
  //           into a line pinned to the top of the chart).
  static final List<List<_MetricChartSpec>> _groups = [
    // Group 0 — PM values (order per Session 7a decisions).
    [
      _MetricChartSpec(
        label: 'PM2.5',
        unit: 'µg/m³',
        scale: MetricScales.pm25,
        zeroBasedAxis: true,
        extract: (r) => r.pm25,
        bander: (v) => DaqiUtils.forPm25(v),
      ),
      _MetricChartSpec(
        label: 'PM10',
        unit: 'µg/m³',
        scale: MetricScales.pm10,
        zeroBasedAxis: true,
        extract: (r) => r.pm10,
        bander: (v) => DaqiUtils.forPm10(v),
      ),
      _MetricChartSpec(
        label: 'PM1',
        unit: 'µg/m³',
        scale: MetricScales.pm1,
        zeroBasedAxis: true,
        extract: (r) => r.pm1,
        bander: (v) => DaqiUtils.forPm1(v),
      ),
    ],
    // Group 1 — CO₂.
    [
      _MetricChartSpec(
        label: 'CO₂',
        unit: 'ppm',
        scale: MetricScales.co2,
        zeroBasedAxis: true,
        extract: (r) => r.co2,
        bander: (v) => DaqiUtils.forCo2(v),
      ),
    ],
    // Group 2 — comfort metrics.
    [
      _MetricChartSpec(
        label: 'Temperature',
        unit: '°C',
        scale: MetricScales.temperature,
        zeroBasedAxis: false,
        extract: (r) => r.temperature,
        bander: (v) => DaqiUtils.forTemperature(v),
      ),
      _MetricChartSpec(
        label: 'Humidity',
        unit: '%',
        scale: MetricScales.humidity,
        zeroBasedAxis: false,
        extract: (r) => r.humidity,
        bander: (v) => DaqiUtils.forHumidity(v),
      ),
      _MetricChartSpec(
        label: 'Air Pressure',
        unit: 'hPa',
        scale: MetricScales.pressure,
        zeroBasedAxis: false,
        extract: (r) => r.pressure,
        bander: (v) => DaqiUtils.forPressure(v),
      ),
    ],
    // Group 3 — SGP41 gas indices. Values are null during sensor
    // conditioning, which renders as gaps in the line (or the
    // per-chart empty message when the whole day is null).
    [
      _MetricChartSpec(
        label: 'NOx Index',
        unit: '',
        scale: MetricScales.noxIndex,
        zeroBasedAxis: true,
        extract: (r) => r.nox,
        bander: (v) => DaqiUtils.forNox(v),
      ),
      _MetricChartSpec(
        label: 'TVOC Index',
        unit: '',
        scale: MetricScales.vocIndex,
        zeroBasedAxis: true,
        extract: (r) => r.tvoc,
        bander: (v) => DaqiUtils.forTvoc(v),
      ),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final group = _groups[groupIndex];
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: group.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final spec = group[i];
        return _MetricChartCard(
          // Keyed by metric + date so scroll position and crosshair
          // selection reset when the user picks a different day, but
          // survive tooltip rebuilds within the same day.
          key: ValueKey('${spec.label}-${date.toIso8601String()}'),
          spec: spec,
          readings: readings,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Metric chart specification — everything one card needs to render
// and label a single metric's daily line.
// ─────────────────────────────────────────────────────────────────

class _MetricChartSpec {
  const _MetricChartSpec({
    required this.label,
    required this.unit,
    required this.scale,
    required this.zeroBasedAxis,
    required this.extract,
    required this.bander,
  });

  final String label;
  final String unit;

  /// Band boundaries + colours from daqi_utils.dart, reused for the
  /// tinted background stripes and the y-axis boundary labels.
  final BandScaleSpec scale;

  /// See the note on [DailyChartView._groups].
  final bool zeroBasedAxis;

  /// Pulls this metric's value out of a reading. Nullable — NOx/TVOC
  /// are null during SGP41 conditioning.
  final double? Function(AirQualityReading) extract;

  /// Classifies a value into its band (colour + label) for the
  /// crosshair tooltip. Nullable to match forNox/forTvoc signatures.
  final DaqiInfo? Function(double) bander;
}

// ─────────────────────────────────────────────────────────────────
// Chart card — one metric's daily line chart.
// ─────────────────────────────────────────────────────────────────

class _MetricChartCard extends StatefulWidget {
  const _MetricChartCard({
    super.key,
    required this.spec,
    required this.readings,
  });

  final _MetricChartSpec spec;
  final List<AirQualityReading> readings;

  @override
  State<_MetricChartCard> createState() => _MetricChartCardState();
}

class _MetricChartCardState extends State<_MetricChartCard> {
  static const double _chartHeight = 200;
  static const double _bottomReserved = 26;
  static const double _yLabelWidth = 40;

  /// ~6 hours visible at once → chart is 24/6 = 4× the viewport wide.
  static const double _visibleHours = 6;

  /// Neutral dark grey line — the band background does the colour work.
  static const Color _lineColour = Color(0xFF2E2E2E);

  /// Consecutive plotted points further apart than this break the
  /// line into separate segments (device samples every 10 s, so
  /// 2 minutes comfortably distinguishes "device off" from jitter).
  static const double _gapThresholdMinutes = 2;

  final ScrollController _scrollController = ScrollController();
  bool _didInitialScroll = false;

  /// Index into [_spots] of the crosshair-selected point, or null
  /// when no point is selected. Persist-until-cleared: tapping a
  /// blank part of the chart clears it.
  int? _touchedSpotIndex;

  // Prepared once per readings list (not per build — scrubbing
  // rebuilds every frame and must not re-iterate thousands of rows).
  late List<FlSpot> _spots;
  late List<AirQualityReading?> _spotReadings;
  late double _minY;
  late double _maxY;
  late bool _hasData;
  late double _firstMinute;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(_MetricChartCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.readings != widget.readings ||
        oldWidget.spec != widget.spec) {
      _prepare();
      _didInitialScroll = false;
      _touchedSpotIndex = null;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ── Data preparation ────────────────────────────────────────────

  /// Builds the spot list (x = minutes since local midnight), keeping
  /// a parallel list of source readings so the tooltip can recover
  /// the reading behind any spot index. Gaps — either time gaps
  /// longer than [_gapThresholdMinutes] or null values (SGP41
  /// conditioning) — are encoded as [FlSpot.nullSpot], which fl_chart
  /// renders as a break in the line.
  void _prepare() {
    final spots = <FlSpot>[];
    final spotReadings = <AirQualityReading?>[];
    double? dataMin;
    double? dataMax;
    double? prevMinute;

    for (final reading in widget.readings) {
      final value = widget.spec.extract(reading);
      if (value == null) {
        if (spots.isNotEmpty && !spots.last.isNull()) {
          spots.add(FlSpot.nullSpot);
          spotReadings.add(null);
        }
        prevMinute = null;
        continue;
      }
      final minute = _minuteOfDay(reading.timestamp);
      if (prevMinute != null &&
          minute - prevMinute > _gapThresholdMinutes) {
        spots.add(FlSpot.nullSpot);
        spotReadings.add(null);
      }
      spots.add(FlSpot(minute, value));
      spotReadings.add(reading);
      prevMinute = minute;
      dataMin = dataMin == null ? value : math.min(dataMin, value);
      dataMax = dataMax == null ? value : math.max(dataMax, value);
    }

    _spots = spots;
    _spotReadings = spotReadings;
    _hasData = dataMax != null;
    _firstMinute =
        _hasData ? spots.firstWhere((s) => !s.isNull()).x : 0;

    if (!_hasData) {
      _minY = 0;
      _maxY = 1;
      return;
    }

    if (widget.spec.zeroBasedAxis) {
      // Hybrid rule (Decision 5): floor at 0, ceiling at data + 10 %.
      _minY = 0;
      final ceiling = dataMax! * 1.1;
      _maxY = ceiling > 0
          ? ceiling
          : widget.spec.scale.innerBoundaries.first;
    } else {
      // Comfort metrics: padded data range so small variations stay
      // legible (pressure especially).
      final span = dataMax! - dataMin!;
      final pad = span > 0 ? span * 0.1 : 1.0;
      _minY = dataMin - pad;
      _maxY = dataMax + pad;
    }
    if (_maxY <= _minY) _maxY = _minY + 1;
  }

  double _minuteOfDay(DateTime t) =>
      t.hour * 60 + t.minute + t.second / 60.0;

  // ── Band background stripes ─────────────────────────────────────

  /// One tinted horizontal stripe per band, clipped to the visible
  /// y-range. The first band extends down from the first boundary and
  /// the last band up from the last, so the whole plot area is always
  /// covered whatever the axis range is.
  List<HorizontalRangeAnnotation> _bandAnnotations() {
    final scale = widget.spec.scale;
    final edges = <double>[
      double.negativeInfinity,
      ...scale.innerBoundaries,
      double.infinity,
    ];
    final annotations = <HorizontalRangeAnnotation>[];
    for (var i = 0; i < scale.segmentCount; i++) {
      final y1 = math.max(edges[i], _minY);
      final y2 = math.min(edges[i + 1], _maxY);
      if (y2 <= y1) continue;
      annotations.add(
        HorizontalRangeAnnotation(
          y1: y1,
          y2: y2,
          color: scale.bandColours[i].withValues(alpha: 0.16),
        ),
      );
    }
    return annotations;
  }

  /// Values labelled on the fixed y-axis column: the axis floor, any
  /// band boundaries inside the visible range, and the axis ceiling.
  List<double> _yLabelValues() {
    final values = <double>[_minY];
    for (final boundary in widget.spec.scale.innerBoundaries) {
      if (boundary > _minY && boundary < _maxY) values.add(boundary);
    }
    values.add(_maxY);
    return values;
  }

  // ── Touch handling ──────────────────────────────────────────────

  void _handleTouch(FlTouchEvent event, LineTouchResponse? response) {
    // Only events that represent the finger selecting/moving over the
    // chart. Tap-up and cancels are ignored so the crosshair persists
    // after the finger lifts.
    final isSelecting = event is FlTapDownEvent ||
        event is FlPanDownEvent ||
        event is FlPanUpdateEvent ||
        event is FlLongPressStart ||
        event is FlLongPressMoveUpdate;
    if (!isSelecting) return;

    final spots = response?.lineBarSpots;
    if (spots == null || spots.isEmpty) {
      // Touched a blank part of the chart → clear the crosshair.
      if (_touchedSpotIndex != null) {
        setState(() => _touchedSpotIndex = null);
      }
      return;
    }
    final spotIndex = spots.first.spotIndex;
    if (spotIndex != _touchedSpotIndex) {
      setState(() => _touchedSpotIndex = spotIndex);
    }
  }

  AirQualityReading? _readingForSpotIndex(int index) {
    if (index < 0 || index >= _spotReadings.length) return null;
    return _spotReadings[index];
  }

  Color _bandColourForSpotIndex(int index) {
    final reading = _readingForSpotIndex(index);
    if (reading == null) return AppColours.textPrimary;
    final value = widget.spec.extract(reading);
    if (value == null) return AppColours.textPrimary;
    return widget.spec.bander(value)?.colour ?? AppColours.textPrimary;
  }

  List<LineTooltipItem?> _tooltipItems(List<LineBarSpot> touchedSpots) {
    return touchedSpots.map((barSpot) {
      final reading = _readingForSpotIndex(barSpot.spotIndex);
      if (reading == null) return null;
      final value = widget.spec.extract(reading);
      if (value == null) return null;

      final info = widget.spec.bander(value);
      final colour = info?.colour ?? AppColours.textPrimary;
      final unit = widget.spec.unit;
      final valueText =
          unit.isEmpty ? _formatValue(value) : '${_formatValue(value)} $unit';

      return LineTooltipItem(
        _formatTime(reading.timestamp),
        const TextStyle(
          color: AppColours.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        children: [
          TextSpan(
            text: '\n$valueText',
            style: TextStyle(
              color: colour,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.6,
            ),
          ),
          if (info != null)
            TextSpan(
              text: '\n${info.label}',
              style: TextStyle(
                color: colour,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
        ],
      );
    }).toList();
  }

  static String _formatValue(double value) =>
      value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

  static String _formatTime(DateTime t) {
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${pad2(t.hour)}:${pad2(t.minute)}:${pad2(t.second)}';
  }

  // ── Initial scroll ──────────────────────────────────────────────

  /// Scrolls the viewport so the day's first reading sits at the left
  /// edge (opening at 00:00 would usually show six empty hours for
  /// commute data). Runs once per data load, after first layout.
  void _scheduleInitialScroll(double chartWidth) {
    if (_didInitialScroll) return;
    _didInitialScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = (chartWidth * (_firstMinute / (24 * 60)) - 12)
          .clamp(0.0, _scrollController.position.maxScrollExtent)
          .toDouble();
      _scrollController.jumpTo(target);
    });
  }

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: AppColours.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                spec.label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColours.textPrimary,
                ),
              ),
              if (spec.unit.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  spec.unit,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColours.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (!_hasData)
            SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  'No ${spec.label} data on this day',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColours.textSecondary,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: _chartHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Fixed y-axis label column — stays put while the
                  // chart scrolls horizontally. Bottom padding mirrors
                  // the chart's reserved hour-label strip so label
                  // heights map onto the plot area exactly.
                  SizedBox(
                    width: _yLabelWidth,
                    child: Column(
                      children: [
                        Expanded(
                          child: _YAxisLabels(
                            values: _yLabelValues(),
                            minY: _minY,
                            maxY: _maxY,
                          ),
                        ),
                        const SizedBox(height: _bottomReserved),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final chartWidth =
                            constraints.maxWidth * (24 / _visibleHours);
                        _scheduleInitialScroll(chartWidth);
                        return SingleChildScrollView(
                          controller: _scrollController,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: chartWidth,
                            child: _buildChart(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final plottedCount =
        _spotReadings.whereType<AirQualityReading>().length;

    final bar = LineChartBarData(
      spots: _spots,
      isCurved: false,
      color: _lineColour,
      barWidth: 2,
      isStrokeCapRound: true,
      dotData: FlDotData(
        // Individual dots only when sparse enough to be tappable
        // targets; dense days read better as a pure line.
        show: plottedCount < 150,
        getDotPainter: (spot, percent, barData, index) =>
            FlDotCirclePainter(
          radius: 2.2,
          color: _lineColour,
          strokeWidth: 0,
        ),
      ),
    );

    return LineChart(
      duration: Duration.zero, // no lerp animation while scrubbing
      LineChartData(
        minX: 0,
        maxX: 24 * 60,
        minY: _minY,
        maxY: _maxY,
        lineBarsData: [bar],
        rangeAnnotations: RangeAnnotations(
          horizontalRangeAnnotations: _bandAnnotations(),
        ),
        gridData: FlGridData(
          show: true,
          drawHorizontalLine: false,
          drawVerticalLine: true,
          verticalInterval: 60,
          getDrawingVerticalLine: (_) => FlLine(
            color: Colors.black.withValues(alpha: 0.06),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: _bottomReserved,
              interval: 60,
              getTitlesWidget: (value, meta) {
                final minutes = value.round();
                if (minutes % 60 != 0) return const SizedBox.shrink();
                final hour = minutes ~/ 60;
                return SideTitleWidget(
                  meta: meta,
                  space: 6,
                  child: Text(
                    '$hour:00',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColours.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(
              color: Colors.black.withValues(alpha: 0.15),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          enabled: true,
          // Managed manually so the crosshair persists after the
          // finger lifts (built-in touches hide it on tap-up).
          handleBuiltInTouches: false,
          touchSpotThreshold: 24,
          touchCallback: _handleTouch,
          getTouchedSpotIndicator: (barData, spotIndexes) {
            return spotIndexes.map((index) {
              final colour = _bandColourForSpotIndex(index);
              return TouchedSpotIndicatorData(
                FlLine(
                  color:
                      AppColours.textPrimary.withValues(alpha: 0.45),
                  strokeWidth: 1,
                ),
                FlDotData(
                  getDotPainter: (spot, percent, bar, i) =>
                      FlDotCirclePainter(
                    radius: 4,
                    color: Colors.white,
                    strokeWidth: 2.5,
                    strokeColor: colour,
                  ),
                ),
              );
            }).toList();
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.white,
            tooltipBorder: BorderSide(
              color: Colors.black.withValues(alpha: 0.08),
            ),
            tooltipBorderRadius: BorderRadius.circular(12),
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: _tooltipItems,
          ),
        ),
        showingTooltipIndicators: _showingIndicators(bar),
      ),
    );
  }

  List<ShowingTooltipIndicators> _showingIndicators(
    LineChartBarData bar,
  ) {
    final index = _touchedSpotIndex;
    if (index == null || index < 0 || index >= _spots.length) {
      return const [];
    }
    final spot = _spots[index];
    if (spot.isNull()) return const [];
    return [
      ShowingTooltipIndicators([LineBarSpot(bar, 0, spot)]),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────
// Fixed y-axis labels — positioned at the axis floor/ceiling and any
// band boundaries inside the visible range, matching the sketch's
// "labels at band edges, no horizontal gridlines" style.
// ─────────────────────────────────────────────────────────────────

class _YAxisLabels extends StatelessWidget {
  const _YAxisLabels({
    required this.values,
    required this.minY,
    required this.maxY,
  });

  final List<double> values;
  final double minY;
  final double maxY;

  static const double _labelHeight = 14;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final span = maxY - minY;
        final sorted = [...values]..sort();
        final children = <Widget>[];
        double? lastTop;
        for (final value in sorted) {
          final fraction = span <= 0
              ? 0.0
              : ((value - minY) / span).clamp(0.0, 1.0).toDouble();
          final top = ((1 - fraction) * height - _labelHeight / 2)
              .clamp(0.0, math.max(0.0, height - _labelHeight))
              .toDouble();
          // De-crowd: skip a label that would overlap the previous one.
          if (lastTop != null && (lastTop - top).abs() < _labelHeight) {
            continue;
          }
          lastTop = top;
          children.add(
            Positioned(
              top: top,
              right: 0,
              child: Text(
                value % 1 == 0
                    ? value.toStringAsFixed(0)
                    : value.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColours.textSecondary,
                ),
              ),
            ),
          );
        }
        return Stack(clipBehavior: Clip.none, children: children);
      },
    );
  }
}