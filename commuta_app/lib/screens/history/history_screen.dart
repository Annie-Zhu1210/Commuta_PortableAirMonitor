import 'package:flutter/material.dart';

import '../../core/constants/app_colours.dart';
import '../../data/models/air_quality_reading.dart';
import '../../services/app_services.dart';
import '../../services/readings_repository.dart';
import 'daily_chart_view.dart';
import 'weekly_chart_view.dart';

/// History tab (Session 7a).
///
/// Screen shell for historical charts. Owns three pieces of state:
///   * the Daily / Weekly view switcher (Weekly is a Session 7b
///     placeholder for now),
///   * the selected metric group (PM values / CO₂ / comfort metrics /
///     gas indices) shown as a horizontal chip row,
///   * the selected date, changed via a Material [showDatePicker]
///     opened from the date pill in the top-right.
///
/// The selected day's readings are loaded once here (a single
/// [ReadingsRepository.getReadingsForDay] query) and shared across
/// every chart on the page, so switching between metric-group chips
/// never re-queries the database. Pull-to-refresh re-runs the query —
/// useful when readings for today arrive while the tab is open.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ReadingsRepository _repository =
      AppServices.instance.readingsRepository;

  static const List<String> _viewLabels = ['Daily', 'Weekly'];

  static const List<String> _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];
  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// 0 = Daily, 1 = Weekly.
  int _viewIndex = 0;

  /// Index into [historyMetricGroupLabels].
  int _groupIndex = 0;

  DateTime _selectedDate = _dateOnly(DateTime.now());

  List<AirQualityReading> _readings = const [];
  bool _isLoading = true;

  static DateTime _dateOnly(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);

  @override
  void initState() {
    super.initState();
    _loadDay();
  }

  /// Query the selected day's readings. When [showSpinner] is false
  /// (pull-to-refresh) the existing charts stay visible while the
  /// query runs, avoiding a flash to the loading state.
  Future<void> _loadDay({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() => _isLoading = true);
    }
    final readings = await _repository.getReadingsForDay(_selectedDate);
    if (!mounted) return;
    setState(() {
      _readings = readings;
      _isLoading = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024, 1, 1),
      lastDate: _dateOnly(DateTime.now()),
    );
    if (picked == null) return;
    final pickedDay = _dateOnly(picked);
    if (pickedDay == _selectedDate) return;
    setState(() => _selectedDate = pickedDay);
    await _loadDay();
  }

  String _formatDate(DateTime day) {
    final today = _dateOnly(DateTime.now());
    if (day == today) return 'Today';
    final base =
        '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}';
    return day.year == today.year ? base : '$base ${day.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColours.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Row 1: Daily/Weekly switcher + date pill ──────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                for (var i = 0; i < _viewLabels.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _SelectableChip(
                      label: _viewLabels[i],
                      selected: _viewIndex == i,
                      onTap: () => setState(() => _viewIndex = i),
                    ),
                  ),
                const Spacer(),
                if (_viewIndex == 0)
                  _DatePill(
                    label: _formatDate(_selectedDate),
                    onTap: _pickDate,
                  ),
              ],
            ),
          ),

          // ── Row 2: metric-group chips (Daily only) ────────────────
          if (_viewIndex == 0)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (var i = 0;
                      i < historyMetricGroupLabels.length;
                      i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _SelectableChip(
                        label: historyMetricGroupLabels[i],
                        selected: _groupIndex == i,
                        onTap: () => setState(() => _groupIndex = i),
                      ),
                    ),
                ],
              ),
            ),

          // ── Body ──────────────────────────────────────────────────
          Expanded(
            child: _viewIndex == 0
                ? _buildDailyBody()
                : const WeeklyChartView(),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColours.accent,
          strokeWidth: 2,
        ),
      );
    }
    return RefreshIndicator(
      color: AppColours.accent,
      onRefresh: () => _loadDay(showSpinner: false),
      child: _readings.isEmpty
          ? const _EmptyDayState()
          : DailyChartView(
              readings: _readings,
              date: _selectedDate,
              groupIndex: _groupIndex,
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Shared chip — the filled-when-selected tab style (Daily/Weekly
// switcher and the metric-group row both use it).
// ─────────────────────────────────────────────────────────────────

class _SelectableChip extends StatelessWidget {
  const _SelectableChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColours.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : AppColours.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Date pill — opens the Material date picker.
// ─────────────────────────────────────────────────────────────────

class _DatePill extends StatelessWidget {
  const _DatePill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColours.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 15,
              color: AppColours.accent,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColours.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Empty state — a scrollable so pull-to-refresh keeps working on
// days with no readings.
// ─────────────────────────────────────────────────────────────────

class _EmptyDayState extends StatelessWidget {
  const _EmptyDayState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(
          Icons.show_chart,
          size: 44,
          color: AppColours.textSecondary.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'No readings collected on this day',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              color: AppColours.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}