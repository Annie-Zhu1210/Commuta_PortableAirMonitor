import 'package:flutter/material.dart';

import '../../core/constants/app_colours.dart';
import '../../data/models/air_quality_reading.dart';
import '../../services/app_services.dart';
import '../../services/readings_repository.dart';
import 'daily_chart_view.dart';
import 'weekly_chart_view.dart';

/// History tab (Sessions 7a & 7b).
///
/// Screen shell for historical charts. Owns:
///   * the Daily / Weekly view switcher,
///   * the selected metric group — shared across both views
///     (PM values / CO₂ / comfort metrics / gas indices),
///   * per-tab date state: Daily remembers a [_selectedDate],
///     Weekly remembers a [_selectedWeekStart] (Monday 00:00 local),
///   * per-tab readings caches.
///
/// Daily loads eagerly on init via
/// [ReadingsRepository.getReadingsForDay]. Weekly loads lazily on
/// first tab switch via [ReadingsRepository.getReadingsBetween],
/// then re-loads only when the user steps to a different week or
/// pulls to refresh. Metric-group selection is preserved across tab
/// switches per Session 7b Decision 7.
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

  /// Index into [historyMetricGroupLabels]. Shared across both tabs
  /// per Session 7b Decision 7.
  int _groupIndex = 0;

  // ── Daily state ──────────────────────────────────────────────────
  DateTime _selectedDate = _dateOnly(DateTime.now());
  List<AirQualityReading> _readings = const [];
  bool _isLoading = true;

  // ── Weekly state ─────────────────────────────────────────────────
  DateTime _selectedWeekStart = _weekStartFor(DateTime.now());
  List<AirQualityReading> _weekReadings = const [];
  bool _isWeekLoading = false;
  bool _weekLoadedOnce = false;

  static DateTime _dateOnly(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);

  /// Monday 00:00 local of the week containing [day]. `weekday` maps
  /// Monday → 1, …, Sunday → 7, so `weekday - 1` is days-since-Monday.
  /// Uses [DateTime]'s day-overflow constructor so DST transitions
  /// (March / October in London) don't drift the midnight boundary
  /// by an hour.
  static DateTime _weekStartFor(DateTime day) {
    final d = _dateOnly(day);
    return DateTime(d.year, d.month, d.day - (d.weekday - 1));
  }

  @override
  void initState() {
    super.initState();
    _loadDay();
  }

  // ── Daily loading ────────────────────────────────────────────────

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

  // ── Weekly loading ───────────────────────────────────────────────

  /// Query the selected week's readings via [getReadingsBetween].
  /// The half-open convention `[weekStart, weekStart + 7 days)` is
  /// enforced by subtracting one microsecond from the upper bound,
  /// since the repository query is inclusive on both ends. A reading
  /// timestamped exactly at next Monday 00:00 belongs to next week,
  /// not this one — matching Session 7a's day-boundary semantics.
  Future<void> _loadWeek({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() => _isWeekLoading = true);
    }
    final from = _selectedWeekStart;
    final to = DateTime(
      _selectedWeekStart.year,
      _selectedWeekStart.month,
      _selectedWeekStart.day + 7,
    ).subtract(const Duration(microseconds: 1));
    final readings = await _repository.getReadingsBetween(from, to);
    if (!mounted) return;
    setState(() {
      _weekReadings = readings;
      _isWeekLoading = false;
      _weekLoadedOnce = true;
    });
  }

  void _handleViewChange(int newIndex) {
    if (newIndex == _viewIndex) return;
    setState(() => _viewIndex = newIndex);
    // Lazy first load of the Weekly tab — spares users who never
    // open Weekly a query on tab-shell mount.
    if (newIndex == 1 && !_weekLoadedOnce) {
      _loadWeek();
    }
  }

  void _previousWeek() {
    final prev = DateTime(
      _selectedWeekStart.year,
      _selectedWeekStart.month,
      _selectedWeekStart.day - 7,
    );
    setState(() => _selectedWeekStart = prev);
    _loadWeek();
  }

  void _nextWeek() {
    if (!_canGoNextWeek) return;
    final next = DateTime(
      _selectedWeekStart.year,
      _selectedWeekStart.month,
      _selectedWeekStart.day + 7,
    );
    setState(() => _selectedWeekStart = next);
    _loadWeek();
  }

  /// True while [_selectedWeekStart] is strictly earlier than this
  /// week — the next step would land on this week or an earlier one.
  /// Disables the forward chevron on the current week (Decision 2).
  bool get _canGoNextWeek {
    final thisWeekStart = _weekStartFor(DateTime.now());
    return _selectedWeekStart.isBefore(thisWeekStart);
  }

  // ── Label formatting ─────────────────────────────────────────────

  String _formatDate(DateTime day) {
    final today = _dateOnly(DateTime.now());
    if (day == today) return 'Today';
    final base =
        '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}';
    return day.year == today.year ? base : '$base ${day.year}';
  }

  /// Renders the selected week's label for the chevron stepper.
  /// Examples:
  ///   * "6 Jul – 12 Jul"       (current year, same or cross month)
  ///   * "6 Jul – 12 Jul 2025"  (past year, same year across the week)
  ///   * "29 Dec 2025 – 4 Jan 2026" (cross-year)
  String _formatWeek(DateTime weekStart) {
    final weekEnd = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day + 6,
    );
    final startPart =
        '${weekStart.day} ${_months[weekStart.month - 1]}';
    final endPart =
        '${weekEnd.day} ${_months[weekEnd.month - 1]}';
    if (weekStart.year != weekEnd.year) {
      return '$startPart ${weekStart.year} – $endPart ${weekEnd.year}';
    }
    final currentYear = DateTime.now().year;
    if (weekStart.year != currentYear) {
      return '$startPart – $endPart ${weekStart.year}';
    }
    return '$startPart – $endPart';
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColours.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Row 1: Daily/Weekly switcher + date pill / week stepper
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
                      onTap: () => _handleViewChange(i),
                    ),
                  ),
                const Spacer(),
                if (_viewIndex == 0)
                  _DatePill(
                    label: _formatDate(_selectedDate),
                    onTap: _pickDate,
                  )
                else
                  _WeekStepper(
                    label: _formatWeek(_selectedWeekStart),
                    canGoNext: _canGoNextWeek,
                    onPrev: _previousWeek,
                    onNext: _nextWeek,
                  ),
              ],
            ),
          ),

          // ── Row 2: metric-group chips (shared across both tabs) ──
          // Rendered regardless of view — the group selection is a
          // shared piece of state (Session 7b Decision 7).
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

          // ── Body ─────────────────────────────────────────────────
          Expanded(
            child: _viewIndex == 0
                ? _buildDailyBody()
                : _buildWeeklyBody(),
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

  Widget _buildWeeklyBody() {
    // First-open spinner: covers the window between `_handleViewChange`
    // kicking off the load and the first `setState` inside `_loadWeek`,
    // as well as any subsequent chevron-triggered reloads.
    if (_isWeekLoading || !_weekLoadedOnce) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColours.accent,
          strokeWidth: 2,
        ),
      );
    }
    return RefreshIndicator(
      color: AppColours.accent,
      onRefresh: () => _loadWeek(showSpinner: false),
      child: _weekReadings.isEmpty
          ? const _EmptyWeekState()
          : WeeklyChartView(
              readings: _weekReadings,
              weekStart: _selectedWeekStart,
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
// Date pill (Daily) — opens the Material date picker.
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
// Week stepper (Weekly) — chevron ‹ label › with disable-forward
// when the current week = this week (Session 7b Decision 2).
// ─────────────────────────────────────────────────────────────────

class _WeekStepper extends StatelessWidget {
  const _WeekStepper({
    required this.label,
    required this.canGoNext,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final bool canGoNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          _ChevronButton(
            icon: Icons.chevron_left,
            enabled: true,
            onTap: onPrev,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColours.textPrimary,
              ),
            ),
          ),
          _ChevronButton(
            icon: Icons.chevron_right,
            enabled: canGoNext,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

class _ChevronButton extends StatelessWidget {
  const _ChevronButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Icon(
          icon,
          size: 20,
          color: enabled
              ? AppColours.accent
              : AppColours.textSecondary.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Empty state (Daily) — a scrollable so pull-to-refresh keeps
// working on days with no readings.
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

// ─────────────────────────────────────────────────────────────────
// Empty state (Weekly) — mirrors [_EmptyDayState] but scoped to the
// whole week. Session 7b Decision B: a single week-level message
// rather than seven per-metric "no data" cards.
// ─────────────────────────────────────────────────────────────────

class _EmptyWeekState extends StatelessWidget {
  const _EmptyWeekState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(
          Icons.calendar_view_week_outlined,
          size: 44,
          color: AppColours.textSecondary.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'No readings collected this week',
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