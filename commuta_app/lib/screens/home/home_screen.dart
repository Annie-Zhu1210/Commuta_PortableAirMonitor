import 'package:flutter/material.dart';
import '../../core/constants/app_colours.dart';
import '../../core/utils/daqi_utils.dart';
import '../../services/app_services.dart';
import '../../data/datasources/air_quality_datasource.dart';
import '../../data/models/air_quality_reading.dart';
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
        final fresh = await _dataSource.getLatestReading();
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

                // ── UK DAQI card (from API) ──────────────────────────────
                _UkDaqiCard(
                  onInfoTap: () =>
                      _showApiInfoSheet(label: 'UK DAQI', unit: ''),
                ),

                const SizedBox(height: 12),

                // ── Local Weather card (from API) ────────────────────────
                _LocalWeatherCard(
                  onInfoTap: () =>
                      _showApiInfoSheet(label: 'Local Weather', unit: ''),
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

  void _showApiInfoSheet({required String label, required String unit}) {
    // API-driven cards have no live device data — no dataSource/extractor passed.
    MetricInfoSheet.show(context, metricLabel: label, unit: unit);
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
// UK DAQI card (from API — placeholder until wired up)
// ─────────────────────────────────────────────────────────────────────────────
//
// Visually distinct from device metric cards:
//   - full-width horizontal layout
//   - subtle accent-tinted background
//   - leading icon to signal "external data"

class _UkDaqiCard extends StatelessWidget {
  final VoidCallback onInfoTap;
  const _UkDaqiCard({required this.onInfoTap});

  @override
  Widget build(BuildContext context) {
    return _ApiCardShell(
      icon: Icons.public_outlined,
      iconColour: AppColours.accentSecondary,
      title: 'UK DAQI',
      subtitle: 'Outdoor air quality (DEFRA)',
      // TODO: Wire up DEFRA / outdoor AQI API. When connected, replace this
      //       placeholder with the live DAQI band returned from the API.
      trailing: const _PlaceholderBandPill(),
      onInfoTap: onInfoTap,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Local Weather card (from API — placeholder until wired up)
// ─────────────────────────────────────────────────────────────────────────────

class _LocalWeatherCard extends StatelessWidget {
  final VoidCallback onInfoTap;
  const _LocalWeatherCard({required this.onInfoTap});

  @override
  Widget build(BuildContext context) {
    return _ApiCardShell(
      icon: Icons.wb_cloudy_outlined,
      iconColour: AppColours.accentSecondary,
      title: 'Local Weather',
      subtitle: 'Temperature, conditions',
      // TODO: Wire up weather API (OpenWeather, Met Office, etc.).
      //       No band pill — weather has no DAQI band.
      trailing: const Text(
        '—',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w400,
          color: AppColours.textSecondary,
        ),
      ),
      onInfoTap: onInfoTap,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared shell for API-driven cards — full-width, horizontal, accent tint
// ─────────────────────────────────────────────────────────────────────────────

class _ApiCardShell extends StatelessWidget {
  final IconData icon;
  final Color iconColour;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onInfoTap;

  const _ApiCardShell({
    required this.icon,
    required this.iconColour,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Subtle tint to differentiate from device metric cards
        color: AppColours.accentSecondary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColours.accentSecondary.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // ── Leading icon in a soft circle ────────────────────────────────
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColour.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: iconColour),
          ),

          const SizedBox(width: 14),

          // ── Title + subtitle ──────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColours.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColours.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // ── Trailing value / band pill ────────────────────────────────────
          trailing,

          const SizedBox(width: 6),

          // ── (i) info icon ─────────────────────────────────────────────────
          GestureDetector(
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
        ],
      ),
    );
  }
}

/// Placeholder pill shown on the UK DAQI card before the API is wired up.
/// Once the API returns a value, replace with a real [_BandPill] coloured
/// by [DaqiUtils.forUkDaqiIndex].
class _PlaceholderBandPill extends StatelessWidget {
  const _PlaceholderBandPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColours.textSecondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '—',
            style: TextStyle(
              fontSize: 11,
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