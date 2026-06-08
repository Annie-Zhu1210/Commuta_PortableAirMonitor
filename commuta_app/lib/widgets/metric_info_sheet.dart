import 'dart:async';
import 'package:flutter/material.dart';
import '../core/constants/app_colours.dart';
import '../core/utils/daqi_utils.dart';
import '../data/datasources/air_quality_datasource.dart';
import '../data/models/air_quality_reading.dart';
import 'band_scale.dart';

/// A snapshot of a single metric's live state — the bits that change as
/// new readings come in. Returned by [MetricExtractor].
typedef MetricLiveState = ({double? numericValue, DaqiInfo? daqiInfo});

/// Pulls a metric's numeric value + DAQI band out of a full reading.
/// Each metric card supplies its own when opening the info sheet so the
/// sheet can update in real time without knowing about every field on
/// [AirQualityReading].
typedef MetricExtractor = MetricLiveState Function(AirQualityReading reading);

/// Bottom sheet shown when the user taps the (i) icon on a metric card.
///
/// When [dataSource] and [extractor] are provided, the sheet subscribes
/// to live readings and updates its displayed value, band, and scale
/// marker as new data arrives. For API-driven cards that have no live
/// device data (UK DAQI, Local Weather), leave both `null` — the sheet
/// will show the placeholders unchanged.
class MetricInfoSheet extends StatefulWidget {
  final String metricLabel;
  final String unit;
  final double? initialNumericValue;
  final DaqiInfo? initialDaqiInfo;
  final BandScaleSpec? scaleSpec;

  // Live update wiring (optional)
  final AirQualityDataSource? dataSource;
  final MetricExtractor? extractor;

  const MetricInfoSheet({
    super.key,
    required this.metricLabel,
    required this.unit,
    this.initialNumericValue,
    this.initialDaqiInfo,
    this.scaleSpec,
    this.dataSource,
    this.extractor,
  });

  /// Convenience method to show this sheet from any widget.
  static void show(
    BuildContext context, {
    required String metricLabel,
    required String unit,
    double? initialNumericValue,
    DaqiInfo? initialDaqiInfo,
    BandScaleSpec? scaleSpec,
    AirQualityDataSource? dataSource,
    MetricExtractor? extractor,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MetricInfoSheet(
        metricLabel:         metricLabel,
        unit:                unit,
        initialNumericValue: initialNumericValue,
        initialDaqiInfo:     initialDaqiInfo,
        scaleSpec:           scaleSpec,
        dataSource:          dataSource,
        extractor:           extractor,
      ),
    );
  }

  @override
  State<MetricInfoSheet> createState() => _MetricInfoSheetState();
}

class _MetricInfoSheetState extends State<MetricInfoSheet> {
  double? _numericValue;
  DaqiInfo? _daqiInfo;
  StreamSubscription<AirQualityReading>? _sub;

  @override
  void initState() {
    super.initState();
    _numericValue = widget.initialNumericValue;
    _daqiInfo     = widget.initialDaqiInfo;

    // If we have a live wire-up, subscribe so the sheet updates as new
    // readings arrive. The data source is owned by HomeScreen and outlives
    // this sheet, so the subscription is safe.
    if (widget.dataSource != null && widget.extractor != null) {
      _sub = widget.dataSource!
          .subscribeToLiveReadings()
          .listen(_onNewReading);
    }
  }

  void _onNewReading(AirQualityReading reading) {
    if (!mounted) return;
    final state = widget.extractor!(reading);
    setState(() {
      _numericValue = state.numericValue;
      _daqiInfo     = state.daqiInfo;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _formatValue(double v) {
    // Match the metric card's formatting: integer for large-magnitude metrics
    // like CO₂/VOC/NOx; one decimal place otherwise.
    if (widget.unit == 'ppm' || widget.scaleSpec?.unit == '' /* dimensionless */) {
      return v.toStringAsFixed(0);
    }
    return v.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize:     0.4,
      maxChildSize:     0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColours.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
            children: [
              // ── Drag handle ──────────────────────────────────────────────
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 20),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColours.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Header: metric name + current value ──────────────────────
              _buildHeader(),

              const SizedBox(height: 24),

              // ── What is this pollutant? ───────────────────────────────────
              _SectionHeader(title: 'What is ${widget.metricLabel}?'),
              const SizedBox(height: 8),
              const _PlaceholderText(
                // TODO: Fill in pollutant / metric explanation (1–2 sentences)
                text: 'Pollutant explanation coming soon.',
              ),

              const SizedBox(height: 24),

              // ── Scale ─────────────────────────────────────────────────────
              const _SectionHeader(title: 'Scale'),
              const SizedBox(height: 16),
              if (widget.scaleSpec != null)
                BandScale(
                  spec:         widget.scaleSpec!,
                  currentValue: _numericValue,
                  currentBand:  _daqiInfo,
                )
              else
                const _PlaceholderText(
                  // TODO: Add a scale spec for this metric in daqi_utils.dart
                  text: 'Scale coming soon.',
                ),

              const SizedBox(height: 24),

              // ── Health recommendation ─────────────────────────────────────
              const _SectionHeader(title: 'Health recommendation'),
              const SizedBox(height: 8),
              const _PlaceholderText(
                // TODO: Fill in health recommendation for the current band
                text: 'Health recommendation coming soon.',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    final hasValue = _numericValue != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            widget.metricLabel,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColours.textPrimary,
            ),
          ),
        ),
        if (hasValue) ...[
          Text(
            _formatValue(_numericValue!),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: _daqiInfo?.colour ?? AppColours.textPrimary,
            ),
          ),
          if (widget.unit.isNotEmpty) ...[
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                widget.unit,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColours.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColours.textPrimary,
        letterSpacing: 0.1,
      ),
    );
  }
}

class _PlaceholderText extends StatelessWidget {
  final String text;
  const _PlaceholderText({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColours.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColours.textSecondary.withValues(alpha: 0.15),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: AppColours.textSecondary,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}