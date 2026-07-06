import 'package:flutter/material.dart';

import '../../core/constants/app_colours.dart';
import '../../data/models/tfl_line.dart';
import '../../data/models/tfl_station.dart';
import '../../services/tfl_map_data.dart';

/// Shows the TfL station picker as a draggable modal bottom sheet.
///
/// Returns the id of the station the user picked, or `null` if the sheet
/// was dismissed without a pick.
///
/// Session 1 design (per confirmed decisions):
///   • Decision 2a — bottom sheet with sticky search bar at the top and
///     an alphabetical list underneath (leveraging [TflMapData.stations]
///     which is already alphabetically sorted).
///   • Decision B.1 — no "Nearest stations" section at the top; search
///     by name is the only path. GPS is unreliable underground anyway,
///     and above ground search is fast enough.
///   • Line-colour chips under each entry help disambiguate the true
///     duplicates in the dataset (Paddington, Edgware Road, Hammersmith).
Future<String?> showStationPicker(BuildContext context) {
  return showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => const _StationPickerSheet(),
  );
}

class _StationPickerSheet extends StatefulWidget {
  const _StationPickerSheet();

  @override
  State<_StationPickerSheet> createState() => _StationPickerSheetState();
}

class _StationPickerSheetState extends State<_StationPickerSheet> {
  final TextEditingController _searchController = TextEditingController();

  /// Normalised search query. Kept as its own field so [_filter] doesn't
  /// re-normalise every call, and so `setState` only fires when the
  /// normalised query changes (typing a space after a word doesn't
  /// re-filter).
  String _normalisedQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final normalised = _normalise(_searchController.text);
    if (normalised != _normalisedQuery) {
      setState(() => _normalisedQuery = normalised);
    } else {
      // Rebuild only the suffix icon (to show/hide the clear button)
      // without re-running the filter.
      setState(() {});
    }
  }

  /// Normalise a string for search: lowercase, keep only a–z / 0–9 /
  /// space, collapse whitespace. Lets "kings cross" match "King's Cross
  /// St. Pancras", and "st pancras" match too. Cheap and predictable.
  String _normalise(String s) {
    final buffer = StringBuffer();
    for (final rune in s.toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      if (RegExp(r'[a-z0-9 ]').hasMatch(char)) {
        buffer.write(char);
      } else {
        // Replace punctuation with a space so "st.pancras" still splits
        // into "st pancras" rather than collapsing into "stpancras".
        buffer.write(' ');
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<TflStation> _filter(List<TflStation> all) {
    if (_normalisedQuery.isEmpty) return all;
    return all
        .where((s) => _normalise(s.displayName).contains(_normalisedQuery))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    // Keyboard-aware bottom padding so the sheet lifts above the keyboard
    // when the search field is focused.
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _buildSheet(scrollController),
      ),
    );
  }

  Widget _buildSheet(ScrollController scrollController) {
    final all = TflMapData.instance.stations;
    final filtered = _filter(all);

    return Container(
      decoration: const BoxDecoration(
        color: AppColours.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _buildGrabHandle(),
          _buildTitle(),
          _buildSearchField(),
          Expanded(
            child: filtered.isEmpty
                ? _buildEmpty()
                : ListView.builder(
                    controller: scrollController,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final station = filtered[index];
                      return _StationTile(
                        station: station,
                        onTap: () =>
                            Navigator.of(context).pop<String>(station.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── Sheet sections ──────────────────────────────────────────────────────

  Widget _buildGrabHandle() {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: AppColours.textSecondary.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildTitle() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Tag a station',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColours.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    final hasText = _searchController.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColours.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColours.textSecondary.withValues(alpha: 0.15),
          ),
        ),
        child: TextField(
          controller: _searchController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(
              Icons.search,
              size: 20,
              color: AppColours.textSecondary,
            ),
            hintText: 'Search stations',
            hintStyle: const TextStyle(
              color: AppColours.textSecondary,
              fontSize: 14,
            ),
            suffixIcon: hasText
                ? IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: AppColours.textSecondary,
                    ),
                    onPressed: _searchController.clear,
                    splashRadius: 18,
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 4,
            ),
          ),
          style: const TextStyle(
            fontSize: 14,
            color: AppColours.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No stations match "${_searchController.text}".',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: AppColours.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Individual list item — station name + line-colour chip row.
// ─────────────────────────────────────────────────────────────────────────

class _StationTile extends StatelessWidget {
  const _StationTile({required this.station, required this.onTap});

  final TflStation station;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    station.displayName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColours.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _LineChips(lineIds: station.lineIds),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColours.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact row of small coloured pills, one per line the station serves.
/// Uses the official TfL colour for each line's background at low alpha,
/// with the line name in the same colour at higher weight — matches the
/// DAQI band-pill idiom used elsewhere in the app.
class _LineChips extends StatelessWidget {
  const _LineChips({required this.lineIds});

  final List<String> lineIds;

  @override
  Widget build(BuildContext context) {
    final data = TflMapData.instance;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: lineIds.map((id) {
        final TflLine? line = data.lineById(id);
        final colour = line?.colour ?? AppColours.textSecondary;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            line?.name ?? id,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colour,
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}