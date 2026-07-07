import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_colours.dart';
import '../../../services/app_services.dart';
import '../../../services/csv_export_service.dart';
import '../../../services/readings_repository.dart';

/// Profile → Data → Export data sub-page.
///
/// Two buttons — "All data" and "Today" — generate a CSV covering
/// the corresponding range and hand it off to the iOS share sheet
/// via `share_plus`. Each button carries a live row count preview
/// fetched on screen open, so Annie knows what she's about to
/// export before committing.
///
/// Empty ranges are detected before any file is generated; an
/// inline message replaces the share handoff so an empty CSV
/// isn't accidentally mailed out looking like real data.
class DataExportScreen extends StatefulWidget {
  const DataExportScreen({super.key});

  @override
  State<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends State<DataExportScreen> {
  static const String _emptyRangeMessage =
      'No data to export in this range — pair the device and '
      'collect some readings first.';

  final ReadingsRepository _repo =
      AppServices.instance.readingsRepository;

  /// Row count previews. `null` = still loading (or reload failed);
  /// the buttons show "— readings" until the first load completes.
  int? _allCount;
  int? _todayCount;

  /// Independent busy flags so both buttons can disable together
  /// while either is running.
  bool _busyAll = false;
  bool _busyToday = false;

  /// Inline messages shown directly under each button. Cleared at
  /// the start of every new export attempt.
  String? _messageAll;
  String? _messageToday;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final range = _todayRange();
    try {
      final results = await Future.wait<int>([
        _repo.countAll(),
        _repo.countBetween(range.start, range.end),
      ]);
      if (!mounted) return;
      setState(() {
        _allCount = results[0];
        _todayCount = results[1];
      });
    } catch (_) {
      // Non-fatal: leave counts null so buttons show "— readings",
      // and let the export attempt itself surface any real error.
      if (!mounted) return;
      setState(() {
        _allCount = null;
        _todayCount = null;
      });
    }
  }

  Future<void> _exportAll() async {
    setState(() {
      _busyAll = true;
      _messageAll = null;
    });
    try {
      final rows = await _repo.getAllReadings();
      if (rows.isEmpty) {
        if (!mounted) return;
        setState(() => _messageAll = _emptyRangeMessage);
        return;
      }
      final file = await CsvExportService.instance.exportReadings(
        rows: rows,
        rangeLabel: 'all',
      );
      await _shareFile(file, 'Commuta readings — all data');
    } catch (e) {
      if (!mounted) return;
      setState(() => _messageAll = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _busyAll = false);
    }
  }

  Future<void> _exportToday() async {
    setState(() {
      _busyToday = true;
      _messageToday = null;
    });
    try {
      final range = _todayRange();
      final rows =
          await _repo.getReadingsBetween(range.start, range.end);
      if (rows.isEmpty) {
        if (!mounted) return;
        setState(() => _messageToday = _emptyRangeMessage);
        return;
      }
      final file = await CsvExportService.instance.exportReadings(
        rows: rows,
        rangeLabel: 'today',
      );
      await _shareFile(file, 'Commuta readings — today');
    } catch (e) {
      if (!mounted) return;
      setState(() => _messageToday = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _busyToday = false);
    }
  }

  /// Local midnight (inclusive) → now (inclusive).
  ///
  /// `getReadingsBetween` uses `isBetweenValues`, which is inclusive
  /// on both bounds, so readings landing exactly at 00:00:00.000
  /// today are included.
  _DateRange _todayRange() {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    return _DateRange(startOfToday, now);
  }

  /// Hand [file] off to the iOS share sheet. The `sharePositionOrigin`
  /// keeps `share_plus` happy on iPad, where a null origin would
  /// crash the popover; on iPhone the value is ignored.
  Future<void> _shareFile(File file, String subject) async {
    final box = context.findRenderObject() as RenderBox?;
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: subject,
      sharePositionOrigin: box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null,
    );
    // A successful share means the DB may have grown while the user
    // was in the share sheet (live BLE readings continue). Refresh
    // the previews so returning to this screen shows current numbers.
    if (mounted) await _loadCounts();
  }

  @override
  Widget build(BuildContext context) {
    final bothBusy = _busyAll || _busyToday;

    return Scaffold(
      backgroundColor: AppColours.background,
      appBar: AppBar(
        backgroundColor: AppColours.surface,
        elevation: 0,
        title: const Text(
          'Export data',
          style: TextStyle(
            color: AppColours.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColours.textPrimary),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _ExplainerCard(),
            const SizedBox(height: 16),

            _ExportButton(
              icon: Icons.download_outlined,
              title: 'All data',
              subtitle: _formatCountSubtitle(_allCount),
              busy: _busyAll,
              enabled: !bothBusy,
              onPressed: _exportAll,
            ),
            if (_messageAll != null)
              _InlineMessage(text: _messageAll!),

            const SizedBox(height: 12),

            _ExportButton(
              icon: Icons.today_outlined,
              title: 'Today',
              subtitle: _formatCountSubtitle(_todayCount),
              busy: _busyToday,
              enabled: !bothBusy,
              onPressed: _exportToday,
            ),
            if (_messageToday != null)
              _InlineMessage(text: _messageToday!),

            const SizedBox(height: 20),
            const _FooterNote(),
          ],
        ),
      ),
    );
  }

  String _formatCountSubtitle(int? count) {
    if (count == null) return '— readings';
    if (count == 0) return 'No readings';
    if (count == 1) return '1 reading';
    return '$count readings';
  }
}

// ─────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────

/// Tiny helper class — Dart doesn't have record support in this
/// codebase's style yet, and the range needs to survive across
/// two await points inside `_exportToday`.
class _DateRange {
  const _DateRange(this.start, this.end);
  final DateTime start;
  final DateTime end;
}

class _ExplainerCard extends StatelessWidget {
  const _ExplainerCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColours.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'Save your air quality readings as a CSV file. Open it in '
        'Numbers, Excel, or a data analysis tool, or share it '
        'straight to another app.',
        style: TextStyle(
          fontSize: 13,
          height: 1.4,
          color: AppColours.textPrimary,
        ),
      ),
    );
  }
}

/// Tappable export tile with a live row count and a spinner state.
///
/// Modelled on the same card idiom as `_ProfileTile` in
/// `profile_screen.dart` so the visual language stays consistent.
class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColours.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColours.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: busy
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(
                                AppColours.accent,
                              ),
                            ),
                          ),
                        )
                      : Icon(
                          icon,
                          size: 18,
                          color: AppColours.accent,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: enabled
                              ? AppColours.textPrimary
                              : AppColours.textSecondary,
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
                Icon(
                  Icons.ios_share,
                  color: enabled
                      ? AppColours.textSecondary
                      : AppColours.textSecondary.withValues(alpha: 0.4),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline status or error line that appears directly beneath a
/// button after a tap. Uses `daqiHigh` for the leading dot so
/// errors and empty-state notices read as gently attention-worthy
/// without being alarming.
class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5, right: 8),
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColours.daqiHigh,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppColours.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        'CSV files include every sensor reading, station and line '
        'tags (with resolved names), and GPS positions where '
        'available. Timestamps use ISO 8601 with your local '
        'timezone. Files are encoded as UTF-8.',
        style: TextStyle(
          fontSize: 11,
          height: 1.4,
          color: AppColours.textSecondary,
        ),
      ),
    );
  }
}