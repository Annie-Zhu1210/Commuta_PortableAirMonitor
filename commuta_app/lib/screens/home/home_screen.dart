import 'package:flutter/material.dart';
import '../../core/constants/app_colours.dart';
import '../../core/utils/daqi_utils.dart';
import '../../services/app_services.dart';
import '../../data/datasources/air_quality_datasource.dart';
import '../../data/models/air_quality_reading.dart';
import '../../data/models/local_context.dart';
import '../../widgets/hero_aqi_card.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/metric_info_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // The single mock/live swap lives in AppServices.init() — Home just
  // reads whichever manager is active.
  final AirQualityDataSource _dataSource = AppServices.instance.dataSource;

  AirQualityReading? _latestReading;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _subscribeToReadings();
  }

  void _subscribeToReadings() {
    _dataSource.subscribeToLiveReadings().listen((reading) {
      if (mounted) {
        setState(() {
          _latestReading = reading;
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    // _dataSource lifecycle is owned by AppServices — don't dispose here.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Note: the debug FAB that opened the BLE dev harness has been
    // removed in Step 7b. The harness now lives at
    // Profile → Developer → Diagnostics (kDebugMode only).
    return Scaffold(
      backgroundColor: AppColours.background,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColours.accent,
                strokeWidth: 2,
              ),
            )
          : _buildDashboard(),
    );
  }

  Widget _buildDashboard() {
    final reading = _latestReading!;

    return RefreshIndicator(
      color: AppColours.accent,
      onRefresh: () async {
        // Latest device reading and Local context (weather + DAQI)
        // refresh together on one pull. refresh() never throws and
        // is a no-op if a fetch is already in flight.
        final results = await Future.wait([
          _dataSource.getLatestReading(),
          AppServices.instance.localContextService.refresh(),
        ]);
        final fresh = results[0] as AirQualityReading?;
        if (mounted && fresh != null) {
          setState(() => _latestReading = fresh);
        }
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Hero card: Overall Air Quality (Plan 2 score) ────────
                HeroAqiCard(reading: reading),

                const SizedBox(height: 20),

                // ── Section label ────────────────────────────────────────
                const _SectionLabel(text: 'Readings'),

                const SizedBox(height: 12),

                // ── Metric cards grid (from device) ──────────────────────
                _MetricGrid(reading: reading, onInfoTap: _showInfoSheet),

                const SizedBox(height: 24),

                // ── Section label for API cards ──────────────────────────
                const _SectionLabel(text: 'Local context'),

                const SizedBox(height: 12),

                // ── Local context row (DAQI left, Weather right) ─────────
                // IntrinsicHeight so both cards stretch to the taller one;
                // Expanded halves the row width evenly with a 12 px gap
                // (matches the metric grid's crossAxisSpacing above).
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _UkDaqiCard(onInfoTap: _showDaqiInfoSheet),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(child: _LocalWeatherCard()),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _showInfoSheet({
    required String infoSheetLabel,
    required String unit,
    required double? numericValue,
    required DaqiInfo? daqiInfo,
    required BandScaleSpec? scaleSpec,
    required MetricExtractor extractor,
  }) {
    MetricInfoSheet.show(
      context,
      metricLabel: infoSheetLabel,
      unit: unit,
      initialNumericValue: numericValue,
      initialDaqiInfo: daqiInfo,
      scaleSpec: scaleSpec,
      dataSource: _dataSource,
      extractor: extractor,
    );
  }

  /// Opens the UK DAQI info sheet — description, 1–10 band scale with
  /// the current index marked, and band-aware health advice. Weather
  /// has no sheet (Session decision: its card carries no (i) icon).
  void _showDaqiInfoSheet(DaqiData data) {
    MetricInfoSheet.show(
      context,
      metricLabel: 'UK DAQI',
      unit: '',
      initialNumericValue: data.index.toDouble(),
      initialDaqiInfo: DaqiUtils.forUkDaqiIndex(data.index),
      scaleSpec: MetricScales.ukDaqi,
      description: DaqiData.description(data.siteName),
      healthAdvice: DaqiData.healthAdviceForBand(data.band),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Metric cards grid (device-sourced)
// ─────────────────────────────────────────────────────────────────────────────

class _MetricGrid extends StatelessWidget {
  final AirQualityReading reading;
  final void Function({
    required String infoSheetLabel,
    required String unit,
    required double? numericValue,
    required DaqiInfo? daqiInfo,
    required BandScaleSpec? scaleSpec,
    required MetricExtractor extractor,
  })
  onInfoTap;

  const _MetricGrid({required this.reading, required this.onInfoTap});

  @override
  Widget build(BuildContext context) {
    final metrics = _buildMetrics(reading);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.35,
      ),
      itemCount: metrics.length,
      itemBuilder: (context, index) {
        final m = metrics[index];
        return MetricCard(
          label: m.label,
          unit: m.unit,
          value: m.value,
          daqiInfo: m.daqiInfo,
          onInfoTap: () => onInfoTap(
            infoSheetLabel: m.infoSheetLabel,
            unit: m.unit,
            numericValue: m.numericValue,
            daqiInfo: m.daqiInfo,
            scaleSpec: m.scaleSpec,
            extractor: m.extractor,
          ),
        );
      },
    );
  }

  List<_MetricSpec> _buildMetrics(AirQualityReading r) {
    return [
      _MetricSpec(
        label: 'PM2.5',
        unit: 'µg/m³',
        value: r.pm25.toStringAsFixed(1),
        numericValue: r.pm25,
        daqiInfo: DaqiUtils.forPm25(r.pm25),
        scaleSpec: MetricScales.pm25,
        extractor: (rr) =>
            (numericValue: rr.pm25, daqiInfo: DaqiUtils.forPm25(rr.pm25)),
      ),
      _MetricSpec(
        label: 'PM10',
        unit: 'µg/m³',
        value: r.pm10.toStringAsFixed(1),
        numericValue: r.pm10,
        daqiInfo: DaqiUtils.forPm10(r.pm10),
        scaleSpec: MetricScales.pm10,
        extractor: (rr) =>
            (numericValue: rr.pm10, daqiInfo: DaqiUtils.forPm10(rr.pm10)),
      ),
      _MetricSpec(
        label: 'PM1',
        unit: 'µg/m³',
        value: r.pm1.toStringAsFixed(1),
        numericValue: r.pm1,
        daqiInfo: DaqiUtils.forPm1(r.pm1),
        scaleSpec: MetricScales.pm1,
        extractor: (rr) =>
            (numericValue: rr.pm1, daqiInfo: DaqiUtils.forPm1(rr.pm1)),
      ),
      _MetricSpec(
        label: 'CO₂',
        unit: 'ppm',
        value: r.co2.toStringAsFixed(0),
        numericValue: r.co2,
        daqiInfo: DaqiUtils.forCo2(r.co2),
        scaleSpec: MetricScales.co2,
        extractor: (rr) =>
            (numericValue: rr.co2, daqiInfo: DaqiUtils.forCo2(rr.co2)),
      ),
      _MetricSpec(
        label: 'Temperature',
        unit: '°C',
        value: r.temperature.toStringAsFixed(1),
        numericValue: r.temperature,
        daqiInfo: DaqiUtils.forTemperature(r.temperature),
        scaleSpec: MetricScales.temperature,
        extractor: (rr) => (
          numericValue: rr.temperature,
          daqiInfo: DaqiUtils.forTemperature(rr.temperature),
        ),
      ),
      _MetricSpec(
        label: 'Humidity',
        unit: '%',
        value: r.humidity.toStringAsFixed(1),
        numericValue: r.humidity,
        daqiInfo: DaqiUtils.forHumidity(r.humidity),
        scaleSpec: MetricScales.humidity,
        extractor: (rr) => (
          numericValue: rr.humidity,
          daqiInfo: DaqiUtils.forHumidity(rr.humidity),
        ),
      ),
      _MetricSpec(
        label: 'Air Pressure',
        unit: 'hPa',
        value: r.pressure.toStringAsFixed(1),
        numericValue: r.pressure,
        daqiInfo: DaqiUtils.forPressure(r.pressure),
        scaleSpec: MetricScales.pressure,
        extractor: (rr) => (
          numericValue: rr.pressure,
          daqiInfo: DaqiUtils.forPressure(rr.pressure),
        ),
      ),
      // Card title kept short for the grid; the info sheet uses the full name.
      _MetricSpec(
        label: 'Pressure Change',
        infoSheetLabel: 'Absolute Air Pressure Change',
        unit: 'Pa/s',
        value: r.pressureChangePaPerSec != null
            ? r.pressureChangePaPerSec!.toStringAsFixed(1)
            : '—',
        numericValue: r.pressureChangePaPerSec,
        daqiInfo: r.pressureChangePaPerSec != null
            ? DaqiUtils.forPressureGradient(r.pressureChangePaPerSec!)
            : null,
        scaleSpec: MetricScales.pressureChange,
        extractor: (rr) => (
          numericValue: rr.pressureChangePaPerSec,
          daqiInfo: rr.pressureChangePaPerSec != null
              ? DaqiUtils.forPressureGradient(rr.pressureChangePaPerSec!)
              : null,
        ),
      ),
      // VOC Index and NOx Index are dimensionless (Sensirion SGP41 scaled 1–500),
      // so unit is empty. Values are null until SGP41 is integrated.
      _MetricSpec(
        label: 'VOC Index',
        unit: '',
        value: r.tvoc != null ? r.tvoc!.toStringAsFixed(0) : '—',
        numericValue: r.tvoc,
        daqiInfo: DaqiUtils.forTvoc(r.tvoc),
        scaleSpec: MetricScales.vocIndex,
        extractor: (rr) =>
            (numericValue: rr.tvoc, daqiInfo: DaqiUtils.forTvoc(rr.tvoc)),
      ),
      _MetricSpec(
        label: 'NOx Index',
        unit: '',
        value: r.nox != null ? r.nox!.toStringAsFixed(0) : '—',
        numericValue: r.nox,
        daqiInfo: DaqiUtils.forNox(r.nox),
        scaleSpec: MetricScales.noxIndex,
        extractor: (rr) =>
            (numericValue: rr.nox, daqiInfo: DaqiUtils.forNox(rr.nox)),
      ),
    ];
  }
}

class _MetricSpec {
  final String label; // shown on the metric card
  final String infoSheetLabel; // shown on the bottom sheet (defaults to label)
  final String unit;
  final String? value;
  final double? numericValue;
  final DaqiInfo? daqiInfo;
  final BandScaleSpec? scaleSpec;
  final MetricExtractor extractor;

  const _MetricSpec({
    required this.label,
    String? infoSheetLabel,
    required this.unit,
    required this.value,
    required this.numericValue,
    required this.daqiInfo,
    required this.scaleSpec,
    required this.extractor,
  }) : infoSheetLabel = infoSheetLabel ?? label;
}

// ─────────────────────────────────────────────────────────────────────────────
// UK DAQI card (live — nearest LAQN monitoring site)
// ─────────────────────────────────────────────────────────────────────────────
//
// Visually distinct from device metric cards:
//   - full-width horizontal layout
//   - subtle accent-tinted background
//   - leading icon to signal "external data"
//
// Rebuilds whenever LocalContextService publishes a new DaqiData.
// Null (never fetched on this device, no cache) shows the "—"
// placeholder pill and no (i) icon — there is nothing to explain yet.
// With data: coloured band pill ("Low · 2"), the source site's name as
// a meta line, and an (i) icon opening the DAQI info sheet.

class _UkDaqiCard extends StatelessWidget {
  final void Function(DaqiData data) onInfoTap;
  const _UkDaqiCard({required this.onInfoTap});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DaqiData?>(
      valueListenable: AppServices.instance.localContextService.daqi,
      builder: (context, data, _) {
        return _ApiCardShell(
          icon: Icons.public_outlined,
          iconColour: AppColours.accentSecondary,
          title: 'UK DAQI',
          // Site name is intentionally omitted from the card — the info
          // sheet's description carries the site name in bold instead.
          caption: null,
          trailing: data == null
              ? const _PlaceholderBandPill()
              : _DaqiBandPill(data: data),
          onInfoTap: data == null ? null : () => onInfoTap(data),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Local Weather card (live — OpenWeather current conditions)
// ─────────────────────────────────────────────────────────────────────────────
//
// Rebuilds whenever LocalContextService publishes a new WeatherData.
// Null (never fetched on this device, no cache) shows "—"; otherwise
// "12° · Clouds" with a fetched-at meta line. No band pill — weather
// has no DAQI band — and no (i) icon: weather needs no explanation
// (Session decision 1).

class _LocalWeatherCard extends StatelessWidget {
  const _LocalWeatherCard();

  static String _formatUpdatedAt(DateTime t) {
    final local = t.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return 'Updated $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WeatherData?>(
      valueListenable: AppServices.instance.localContextService.weather,
      builder: (context, data, _) {
        return _ApiCardShell(
          icon: Icons.wb_cloudy_outlined,
          iconColour: AppColours.accentSecondary,
          title: 'Local Weather',
          caption: data == null ? null : _formatUpdatedAt(data.fetchedAt),
          trailing: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              data == null
                  ? '—'
                  : '${data.tempCelsius}° · ${data.condition}',
              maxLines: 1,
              style: TextStyle(
                fontSize: 24,
                fontWeight: data == null ? FontWeight.w400 : FontWeight.w600,
                color: data == null
                    ? AppColours.textSecondary
                    : AppColours.textPrimary,
              ),
            ),
          ),
          onInfoTap: null,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared shell for API-driven cards — fully symmetric, accent tint
// ─────────────────────────────────────────────────────────────────────────────
//
// Composition ("Alt A" symmetric medallion, sized for a half-width grid):
//   • Icon (44 px circle)  — top, centred
//   • Title                — 15 pt semi-bold, centred
//   • Trailing (hero)      — the focal value: DAQI band pill, or the big
//                             weather text. Both use FittedBox internally
//                             so extreme values ("Very High · 10",
//                             "22° · Thunderstorm") scale down instead of
//                             clipping the ~133 px content width.
//   • Caption              — small centred supporting line (currently used
//                             by the weather card for "Updated hh:mm").
//                             Omitted when null.
//   • (i) info icon        — absolutely positioned top-right so it doesn't
//                             disturb the vertical centre-line. Omitted
//                             when [onInfoTap] is null.
//
// The content column is wrapped in [Center] so, when the parent
// [IntrinsicHeight] Row stretches the shorter card to match the taller
// one, the shorter card's content sits vertically centred in the extra
// space rather than clinging to the top.

class _ApiCardShell extends StatelessWidget {
  final IconData icon;
  final Color iconColour;
  final String title;
  final String? caption;
  final Widget trailing;
  final VoidCallback? onInfoTap;

  const _ApiCardShell({
    required this.icon,
    required this.iconColour,
    required this.title,
    this.caption,
    required this.trailing,
    required this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Icon ───────────────────────────────────────────────────────────
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: iconColour.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 22, color: iconColour),
        ),

        const SizedBox(height: 12),

        // ── Title ──────────────────────────────────────────────────────────
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColours.textPrimary,
            letterSpacing: 0.1,
          ),
        ),

        const SizedBox(height: 14),

        // ── Hero value ─────────────────────────────────────────────────────
        trailing,

        // ── Caption (optional) ─────────────────────────────────────────────
        if (caption != null) ...[
          const SizedBox(height: 10),
          Text(
            caption!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColours.accentSecondary.withValues(alpha: 0.9),
            ),
          ),
        ],
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // Subtle tint to differentiate from device metric cards
        color: AppColours.accentSecondary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColours.accentSecondary.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          // Center wrapper: when the sibling card in the Row is taller,
          // IntrinsicHeight stretches this Container to match, and Center
          // pushes the (naturally-sized) Column into the vertical middle
          // instead of leaving it stuck at the top.
          Center(child: content),
          if (onInfoTap != null)
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: onInfoTap,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.info_outline,
                    size: 18,
                    color: AppColours.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Live band pill on the UK DAQI card — coloured by severity band,
/// showing "{band} · {index}" (e.g. "Low · 2"). Band label and colour
/// come from [DaqiUtils.forUkDaqiIndex], the same source the info
/// sheet uses, so pill and sheet can never disagree.
class _DaqiBandPill extends StatelessWidget {
  final DaqiData data;
  const _DaqiBandPill({required this.data});

  @override
  Widget build(BuildContext context) {
    final info = DaqiUtils.forUkDaqiIndex(data.index);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: info.colour.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          '${info.label} · ${data.index}',
          maxLines: 1,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: info.colour,
          ),
        ),
      ),
    );
  }
}

/// Placeholder pill shown on the UK DAQI card while no DAQI value has
/// ever been fetched on this device (no live fetch yet and no cache).
class _PlaceholderBandPill extends StatelessWidget {
  const _PlaceholderBandPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColours.textSecondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '—',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColours.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared section label
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColours.textPrimary,
        letterSpacing: 0.1,
      ),
    );
  }
}