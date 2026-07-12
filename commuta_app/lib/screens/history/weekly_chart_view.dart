import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colours.dart';
import '../../core/utils/daqi_utils.dart';
import '../../data/models/air_quality_reading.dart';

/// Weekly view of the History tab (Session 7b).
///
/// Renders the selected metric group as a vertical list of chart
/// cards — one card per metric within the group, stacked in the
/// same order as the Daily view (e.g. "PM values" → PM2.5, PM10,
/// PM1). Each card shows seven days of the selected week aggregated
/// to a daily mean line with a min–max shaded envelope, over the
/// DAQI band background stripes.
///
/// Aggregation happens in-Dart (Session 7b Decision 3): the History
/// screen shell fetches the week's readings in a single
/// [ReadingsRepository.getReadingsBetween] call and passes the list
/// in; each card re-groups the same list by local date and computes
/// its own mean / min / max / count against its own extractor.
///
/// Days with no readings for a given metric render as a break in
/// the mean line (via [FlSpot.nullSpot]) with the envelope skipping
/// that day entirely; a small outlined ring at the y-axis midpoint
/// plus a lightened bottom title communicate "no data" without
/// competing with the real data (Session 7b Decision 5).
class WeeklyChartView extends StatelessWidget {
  const WeeklyChartView({
    super.key,
    required this.readings,
    required this.weekStart,
    required this.groupIndex,
  });

  /// All readings in the selected week, ascending by timestamp.
  /// May include readings very slightly outside the week window
  /// due to the repository's inclusive query bounds — the daily
  /// grouping filters those out by weekday index.
  final List<AirQualityReading> readings;

  /// Monday 00:00 local of the selected week.
  final DateTime weekStart;

  /// Index into [historyMetricGroupLabels] (defined in
  /// [daily_chart_view.dart]) — the two views share the same
  /// group indexing so switching tabs preserves the selection
  /// (Session 7b Decision 7).
  final int groupIndex;

  // ── Metric group definitions ────────────────────────────────────
  // Duplicated from [DailyChartView._groups] per Session 7b Decision
  // A: keeping daily untouched at the cost of ~60 lines of data
  // duplication. Post-exhibition cleanup: factor into a shared file.
  static final List<List<_WeeklyMetricSpec>> _groups = [
    // Group 0 — PM values.
    [
      _WeeklyMetricSpec(
        label: 'PM2.5',
        unit: 'µg/m³',
        scale: MetricScales.pm25,
        zeroBasedAxis: true,
        extract: (r) => r.pm25,
        bander: (v) => DaqiUtils.forPm25(v),
      ),
      _WeeklyMetricSpec(
        label: 'PM10',
        unit: 'µg/m³',
        scale: MetricScales.pm10,
        zeroBasedAxis: true,
        extract: (r) => r.pm10,
        bander: (v) => DaqiUtils.forPm10(v),
      ),
      _WeeklyMetricSpec(
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
      _WeeklyMetricSpec(
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
      _WeeklyMetricSpec(
        label: 'Temperature',
        unit: '°C',
        scale: MetricScales.temperature,
        zeroBasedAxis: false,
        extract: (r) => r.temperature,
        bander: (v) => DaqiUtils.forTemperature(v),
      ),
      _WeeklyMetricSpec(
        label: 'Humidity',
        unit: '%',
        scale: MetricScales.humidity,
        zeroBasedAxis: false,
        extract: (r) => r.humidity,
        bander: (v) => DaqiUtils.forHumidity(v),
      ),
      _WeeklyMetricSpec(
        label: 'Air Pressure',
        unit: 'hPa',
        scale: MetricScales.pressure,
        zeroBasedAxis: false,
        extract: (r) => r.pressure,
        bander: (v) => DaqiUtils.forPressure(v),
      ),
    ],
    // Group 3 — SGP41 gas indices. Values are null during sensor
    // conditioning, which renders as gaps in the mean line (or the
    // per-card empty message when the whole week is null).
    [
      _WeeklyMetricSpec(
        label: 'NOx Index',
        unit: '',
        scale: MetricScales.noxIndex,
        zeroBasedAxis: true,
        extract: (r) => r.nox,
        bander: (v) => DaqiUtils.forNox(v),
      ),
      _WeeklyMetricSpec(
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
        return _WeeklyMetricChartCard(
          // Keyed by metric + week so tooltip selection resets when
          // the user steps to a different week, but survives rebuilds
          // within the same week (e.g. pull-to-refresh).
          key: ValueKey('${spec.label}-${weekStart.toIso8601String()}'),
          spec: spec,
          readings: readings,
          weekStart: weekStart,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Metric chart specification — same shape as daily's private spec.
// Duplicated deliberately per Session 7b Decision A.
// ─────────────────────────────────────────────────────────────────

class _WeeklyMetricSpec {
  const _WeeklyMetricSpec({
    required this.label,
    required this.unit,
    required this.scale,
    required this.zeroBasedAxis,
    required this.extract,
    required this.bander,
  });

  final String label;
  final String unit;

  /// DAQI band boundaries + colours, reused for the tinted background
  /// stripes and the y-axis boundary labels.
  final BandScaleSpec scale;

  /// true  → y-axis floor is 0 (pollutant metrics);
  /// false → y-axis is a padded range around the week's data
  ///         (comfort metrics — a 0-based axis would flatten pressure
  ///         at ~1000 hPa into a line pinned to the top).
  final bool zeroBasedAxis;

  /// Pulls this metric's value out of a reading. Nullable — NOx/TVOC
  /// are null during SGP41 conditioning.
  final double? Function(AirQualityReading) extract;

  /// Classifies a value into its DAQI band. Nullable to match
  /// forNox/forTvoc signatures.
  final DaqiInfo? Function(double) bander;
}

// ─────────────────────────────────────────────────────────────────
// Per-day aggregate over a metric — the seven-day summary the chart
// consumes.
// ─────────────────────────────────────────────────────────────────

class _DailyAggregate {
  const _DailyAggregate({
    required this.date,
    required this.mean,
    required this.min,
    required this.max,
    required this.count,
  });

  final DateTime date;
  final double? mean;
  final double? min;
  final double? max;

  /// Number of readings whose value for this metric was non-null.
  /// A day with 800 readings but all-null NOx (SGP41 conditioning)
  /// has count = 0 for the NOx card.
  final int count;

  bool get hasData => count > 0 && mean != null;
}

// ─────────────────────────────────────────────────────────────────
// One card = one metric's weekly chart.
// ─────────────────────────────────────────────────────────────────

class _WeeklyMetricChartCard extends StatefulWidget {
  const _WeeklyMetricChartCard({
    super.key,
    required this.spec,
    required this.readings,
    required this.weekStart,
  });

  final _WeeklyMetricSpec spec;
  final List<AirQualityReading> readings;
  final DateTime weekStart;

  @override
  State<_WeeklyMetricChartCard> createState() =>
      _WeeklyMetricChartCardState();
}

class _WeeklyMetricChartCardState extends State<_WeeklyMetricChartCard> {
  static const double _chartHeight = 200;
  static const double _bottomReserved = 44;
  static const double _yLabelWidth = 40;

  /// Neutral dark grey — matches Daily. Band background does the DAQI
  /// colour work.
  static const Color _lineColour = Color(0xFF2E2E2E);

  /// Small padding on the x-axis so the leftmost (Mon) and rightmost
  /// (Sun) day markers aren't clipped against the axis edges.
  static const double _xPadding = 0.35;

  /// Weekday labels for x-axis titles and tooltip headers.
  static const List<String> _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  /// Month abbreviations for tooltip headers.
  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Bar-index constants inside [LineChartData.lineBarsData]. The
  /// three envelope bars (min, max, mean) always exist; the
  /// empty-day marker bar is only added when there's at least one
  /// empty day, and gets index 3 in that case.
  static const int _minBarIndex = 0;
  static const int _maxBarIndex = 1;
  static const int _meanBarIndex = 2;

  /// Day index (0 = Monday, 6 = Sunday) of the tooltip-selected day,
  /// or null when no day is selected. Persists after finger lift;
  /// tapping a blank part of the chart or an empty day clears it.
  int? _selectedDayIndex;

  // Prepared once per (readings, weekStart, spec) triple.
  late List<_DailyAggregate> _aggregates;
  late double _minY;
  late double _maxY;
  late bool _anyDayHasData;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(_WeeklyMetricChartCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.readings != widget.readings ||
        oldWidget.spec != widget.spec ||
        oldWidget.weekStart != widget.weekStart) {
      _prepare();
      _selectedDayIndex = null;
    }
  }

  // ── Data preparation ────────────────────────────────────────────

  /// Groups readings into seven daily buckets keyed off the local
  /// calendar-day offset from [weekStart], then computes mean / min /
  /// max / count per bucket. Runs once per data set; the chart's
  /// build method never re-iterates the raw readings.
  ///
  /// The day-index calculation uses [DateTime.utc] on the year /
  /// month / day components rather than [Duration.inDays] on local
  /// [DateTime]s, so DST transitions (March / October in London)
  /// don't shift the day boundaries by an hour and shove readings
  /// into the wrong bucket.
  void _prepare() {
    final wsUtc = DateTime.utc(
      widget.weekStart.year,
      widget.weekStart.month,
      widget.weekStart.day,
    );
    final buckets = List<List<double>>.generate(7, (_) => <double>[]);

    for (final reading in widget.readings) {
      final ts = reading.timestamp;
      final tsUtc = DateTime.utc(ts.year, ts.month, ts.day);
      final dayIdx = tsUtc.difference(wsUtc).inDays;
      if (dayIdx < 0 || dayIdx > 6) continue;
      final value = widget.spec.extract(reading);
      if (value == null) continue;
      buckets[dayIdx].add(value);
    }

    _aggregates = List<_DailyAggregate>.generate(7, (i) {
      final vals = buckets[i];
      final date = DateTime(
        widget.weekStart.year,
        widget.weekStart.month,
        widget.weekStart.day + i,
      );
      if (vals.isEmpty) {
        return _DailyAggregate(
          date: date,
          mean: null,
          min: null,
          max: null,
          count: 0,
        );
      }
      final sum = vals.fold<double>(0, (a, b) => a + b);
      final mean = sum / vals.length;
      final minV = vals.reduce(math.min);
      final maxV = vals.reduce(math.max);
      return _DailyAggregate(
        date: date,
        mean: mean,
        min: minV,
        max: maxV,
        count: vals.length,
      );
    });

    _anyDayHasData = _aggregates.any((a) => a.hasData);

    if (!_anyDayHasData) {
      _minY = 0;
      _maxY = 1;
      return;
    }

    if (widget.spec.zeroBasedAxis) {
      // Pollutant metrics: floor at 0, ceiling at week-max × 1.1.
      // Mirrors Daily's y-axis rule (Session 7b Decision C).
      _minY = 0;
      final dataMax = _aggregates
          .where((a) => a.hasData)
          .map((a) => a.max!)
          .reduce(math.max);
      final ceiling = dataMax * 1.1;
      _maxY = ceiling > 0
          ? ceiling
          : widget.spec.scale.innerBoundaries.first;
    } else {
      // Comfort metrics: padded data range so small variations stay
      // legible (pressure especially).
      final validAggs = _aggregates.where((a) => a.hasData);
      final dataMin =
          validAggs.map((a) => a.min!).reduce(math.min);
      final dataMax =
          validAggs.map((a) => a.max!).reduce(math.max);
      final span = dataMax - dataMin;
      final pad = span > 0 ? span * 0.1 : 1.0;
      _minY = dataMin - pad;
      _maxY = dataMax + pad;
    }
    if (_maxY <= _minY) _maxY = _minY + 1;
  }

  // ── Band background stripes ─────────────────────────────────────

  /// One tinted horizontal stripe per band, clipped to the visible
  /// y-range. Mirrors Daily's implementation.
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

  /// Values labelled on the fixed y-axis column: axis floor, any
  /// band boundaries inside the visible range, and axis ceiling.
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
    // Only events that represent the finger selecting/moving over
    // the chart. Tap-up and cancels are ignored so the tooltip
    // persists after the finger lifts (mirrors Daily's crosshair
    // behaviour from Session 7a).
    final isSelecting = event is FlTapDownEvent ||
        event is FlPanDownEvent ||
        event is FlPanUpdateEvent ||
        event is FlLongPressStart ||
        event is FlLongPressMoveUpdate;
    if (!isSelecting) return;

    final spots = response?.lineBarSpots;
    if (spots == null || spots.isEmpty) {
      // Blank part of the chart → clear the tooltip.
      if (_selectedDayIndex != null) {
        setState(() => _selectedDayIndex = null);
      }
      return;
    }

    // Every bar (min / max / mean / empty-marker) plots at integer
    // x positions matching the day index, so any hit's x-value maps
    // directly to a day regardless of which bar was closest.
    final dayIdx = spots.first.x.round();
    if (dayIdx < 0 || dayIdx > 6) return;

    // Tapping an empty day clears the tooltip: no numbers to show,
    // and the visible ring plus lightened label on that column
    // already communicate "no data here".
    if (!_aggregates[dayIdx].hasData) {
      if (_selectedDayIndex != null) {
        setState(() => _selectedDayIndex = null);
      }
      return;
    }

    if (dayIdx != _selectedDayIndex) {
      setState(() => _selectedDayIndex = dayIdx);
    }
  }

  Color _bandColourForDayIndex(int dayIdx) {
    if (dayIdx < 0 || dayIdx >= _aggregates.length) {
      return AppColours.textPrimary;
    }
    final agg = _aggregates[dayIdx];
    if (agg.mean == null) return AppColours.textPrimary;
    return widget.spec.bander(agg.mean!)?.colour ??
        AppColours.textPrimary;
  }

  // ── Tooltip content ─────────────────────────────────────────────

  List<LineTooltipItem?> _tooltipItems(List<LineBarSpot> touchedSpots) {
    return touchedSpots.map((barSpot) {
      if (barSpot.barIndex != _meanBarIndex) return null;
      final dayIdx = barSpot.spotIndex;
      if (dayIdx < 0 || dayIdx >= _aggregates.length) return null;
      final agg = _aggregates[dayIdx];
      if (!agg.hasData) return null;

      final info = widget.spec.bander(agg.mean!);
      final colour = info?.colour ?? AppColours.textPrimary;
      final unit = widget.spec.unit;
      final unitSuffix = unit.isEmpty ? '' : ' $unit';
      final countLabel = agg.count == 1 ? 'reading' : 'readings';

      final header = '${_weekdays[agg.date.weekday - 1]} '
          '${agg.date.day} ${_months[agg.date.month - 1]}';

      return LineTooltipItem(
        '$header\n',
        const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColours.textSecondary,
        ),
        children: [
          TextSpan(
            text: '${_formatValue(agg.mean!)}$unitSuffix\n',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colour,
            ),
          ),
          TextSpan(
            text: 'range ${_formatValue(agg.min!)}'
                '–${_formatValue(agg.max!)}\n',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColours.textPrimary,
            ),
          ),
          TextSpan(
            text: '${agg.count} $countLabel',
            style: const TextStyle(
              fontSize: 11,
              color: AppColours.textSecondary,
            ),
          ),
        ],
        textAlign: TextAlign.left,
      );
    }).toList();
  }

  /// Same rule as Daily: integer format for dimensionless indices,
  /// one decimal place otherwise.
  String _formatValue(double v) {
    return widget.spec.unit.isEmpty
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(1);
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
          if (!_anyDayHasData)
            SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  'No ${spec.label} data this week',
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
                  // Fixed y-axis label column. Bottom padding mirrors
                  // the chart's reserved day-label strip so label
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
                  Expanded(child: _buildChart()),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    // Build the three envelope bars and the optional empty-day
    // marker bar.
    final minSpots = <FlSpot>[];
    final maxSpots = <FlSpot>[];
    final meanSpots = <FlSpot>[];
    final emptySpots = <FlSpot>[];
    final midY = (_minY + _maxY) / 2;

    for (var i = 0; i < 7; i++) {
      final agg = _aggregates[i];
      final x = i.toDouble();
      if (agg.hasData) {
        minSpots.add(FlSpot(x, agg.min!));
        maxSpots.add(FlSpot(x, agg.max!));
        meanSpots.add(FlSpot(x, agg.mean!));
      } else {
        minSpots.add(FlSpot.nullSpot);
        maxSpots.add(FlSpot.nullSpot);
        meanSpots.add(FlSpot.nullSpot);
        emptySpots.add(FlSpot(x, midY));
      }
    }

    final minBar = LineChartBarData(
      spots: minSpots,
      isCurved: false,
      color: Colors.transparent,
      barWidth: 0,
      dotData: const FlDotData(show: false),
    );
    final maxBar = LineChartBarData(
      spots: maxSpots,
      isCurved: false,
      color: Colors.transparent,
      barWidth: 0,
      dotData: const FlDotData(show: false),
    );
    final meanBar = LineChartBarData(
      spots: meanSpots,
      isCurved: false,
      color: _lineColour,
      barWidth: 2,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, bar, i) => FlDotCirclePainter(
          radius: 3.2,
          color: _lineColour,
          strokeWidth: 0,
        ),
      ),
    );

    final bars = <LineChartBarData>[minBar, maxBar, meanBar];
    if (emptySpots.isNotEmpty) {
      bars.add(
        LineChartBarData(
          spots: emptySpots,
          isCurved: false,
          color: Colors.transparent,
          barWidth: 0,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, i) => FlDotCirclePainter(
              radius: 3.2,
              color: Colors.white,
              strokeWidth: 1.2,
              strokeColor:
                  AppColours.textSecondary.withValues(alpha: 0.55),
            ),
          ),
        ),
      );
    }

    return LineChart(
      duration: Duration.zero,
      LineChartData(
        minX: -_xPadding,
        maxX: 6 + _xPadding,
        minY: _minY,
        maxY: _maxY,
        lineBarsData: bars,
        betweenBarsData: [
          BetweenBarsData(
            fromIndex: _minBarIndex,
            toIndex: _maxBarIndex,
            color: _lineColour.withValues(alpha: 0.15),
          ),
        ],
        rangeAnnotations: RangeAnnotations(
          horizontalRangeAnnotations: _bandAnnotations(),
        ),
        gridData: const FlGridData(show: false),
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
              interval: 1,
              getTitlesWidget: _buildBottomTitle,
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
          handleBuiltInTouches: false,
          // Generous threshold so any tap inside a day's ~50 px
          // column lands on that day's spot, whatever the tap's
          // vertical position.
          touchSpotThreshold: 40,
          touchCallback: _handleTouch,
          getTouchedSpotIndicator: (barData, spotIndexes) {
            return spotIndexes.map((index) {
              final colour = _bandColourForDayIndex(index);
              return TouchedSpotIndicatorData(
                FlLine(
                  color:
                      AppColours.textPrimary.withValues(alpha: 0.45),
                  strokeWidth: 1,
                ),
                FlDotData(
                  getDotPainter: (spot, percent, bar, i) =>
                      FlDotCirclePainter(
                    radius: 4.5,
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
        showingTooltipIndicators: _showingIndicators(meanBar),
      ),
    );
  }

  Widget _buildBottomTitle(double value, TitleMeta meta) {
    final dayIdx = value.round();
    if (dayIdx < 0 || dayIdx > 6) return const SizedBox.shrink();
    // Rendered exactly at each integer x; filter out any interior
    // fractional ticks fl_chart might emit.
    if ((value - dayIdx).abs() > 0.01) return const SizedBox.shrink();

    final date = _aggregates[dayIdx].date;
    final dayName = _weekdays[date.weekday - 1];
    final hasData = _aggregates[dayIdx].hasData;

    // Empty days get lightened labels — combined with the outlined
    // ring dot at midY, that reads clearly as "no data on this day"
    // (Session 7b Decision 5).
    final nameColour = hasData
        ? AppColours.textSecondary
        : AppColours.textSecondary.withValues(alpha: 0.5);
    final dateColour = hasData
        ? AppColours.textPrimary
        : AppColours.textPrimary.withValues(alpha: 0.4);

    return SideTitleWidget(
      meta: meta,
      space: 6,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            dayName,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.1,
              color: nameColour,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 11,
              height: 1.1,
              fontWeight: FontWeight.w600,
              color: dateColour,
            ),
          ),
        ],
      ),
    );
  }

  List<ShowingTooltipIndicators> _showingIndicators(
    LineChartBarData meanBar,
  ) {
    final idx = _selectedDayIndex;
    if (idx == null || idx < 0 || idx > 6) return const [];
    if (!_aggregates[idx].hasData) return const [];
    final spot = meanBar.spots[idx];
    if (spot.isNull()) return const [];
    return [
      ShowingTooltipIndicators(
        [LineBarSpot(meanBar, _meanBarIndex, spot)],
      ),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────
// Fixed y-axis labels — positioned at the axis floor/ceiling and any
// band boundaries inside the visible range. Duplicated from Daily
// per Session 7b Decision A.
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