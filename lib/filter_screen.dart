import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Filter Result returned to caller ────────────────────────────────────────
class FilterResult {
  final int? floor;          // null = all floors
  final String? type;        // null = all types
  final String displayLabel; // e.g. "1st Floor › Labs"

  const FilterResult({
    this.floor,
    this.type,
    required this.displayLabel,
  });
}

// ─── Floor definitions ───────────────────────────────────────────────────────
const List<Map<String, dynamic>> _kFloors = [
  {'label': 'Ground Floor', 'value': 0},
  {'label': '1st Floor',    'value': 1},
  {'label': '2nd Floor',    'value': 2},
  {'label': '3rd Floor',    'value': 3},
  {'label': '4th Floor',    'value': 4},
];

// Room types per floor (display name → GeoJSON type strings that match)
const Map<int, List<Map<String, String>>> _kFloorRoomTypes = {
  0: [
    {'label': 'Labs',              'type': 'lab'},
    {'label': 'Offices',           'type': 'office'},
    {'label': 'Washrooms',         'type': 'washroom'},
    {'label': 'Cafeteria',         'type': 'cafeteria'},
    {'label': 'Auditorium / Hall', 'type': 'auditorium'},
  ],
  1: [
    {'label': 'Offices',    'type': 'office'},
    {'label': 'Labs',       'type': 'lab'},
    {'label': 'Classrooms', 'type': 'classroom'},
    {'label': 'Staff-room', 'type': 'cabin'},
    {'label': 'Washrooms',  'type': 'washroom'},
  ],
  2: [
    {'label': 'Classrooms', 'type': 'classroom'},
    {'label': 'Labs',       'type': 'lab'},
    {'label': 'Offices',    'type': 'office'},
    {'label': 'Washrooms',  'type': 'washroom'},
  ],
  3: [
    {'label': 'Classrooms', 'type': 'classroom'},
    {'label': 'Labs',       'type': 'lab'},
    {'label': 'Offices',    'type': 'office'},
    {'label': 'Washrooms',  'type': 'washroom'},
  ],
  4: [
    {'label': 'Classrooms', 'type': 'classroom'},
    {'label': 'Labs',       'type': 'lab'},
    {'label': 'Washrooms',  'type': 'washroom'},
  ],
};

// Refreshment area items
const List<Map<String, String>> _kRefreshmentTypes = [
  {'label': 'Cafeteria',     'type': 'cafeteria'},
];

// ─── Colours (matching the beige palette in the designs) ─────────────────────
const _kBg          = Color(0xFFF5F5F0);   // page background
const _kPillNormal  = Color(0xFFDAD9CC);   // collapsed pill
const _kPillExpanded= Color(0xFFD0CFC3);   // expanded section header
const _kPillChild   = Color(0xFFDCDBCE);   // child row (floor sub-item)
const _kPillLeaf    = Color(0xFFE2E1D6);   // deepest leaf (room type)

// ─── Filter Screen ────────────────────────────────────────────────────────────
class FilterScreen extends StatefulWidget {
  final Function(FilterResult)? onResult;
  const FilterScreen({super.key, this.onResult});

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  // Which top-level sections are expanded (Floor / Refreshment)
  bool _floorExpanded       = false;
  bool _refreshExpanded     = false;

  // Which floor sub-item is expanded (null = none)
  int? _expandedFloorIndex; // index into _kFloors

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    return Scaffold(
      backgroundColor: _kBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header bar ───────────────────────────────────────────────────────
          Container(
            color: _kBg,
            padding: EdgeInsets.only(top: statusBarHeight + 4, bottom: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87, size: 22),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Text(
                  'Filter',
                  style: TextStyle(
                    fontFamily: 'googlesans',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),

          // ── Accordion list ───────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                _buildTopSection(
                  label: 'Floor',
                  expanded: _floorExpanded,
                  onTap: () => setState(() {
                    _floorExpanded = !_floorExpanded;
                    if (!_floorExpanded) _expandedFloorIndex = null;
                  }),
                  children: _floorExpanded ? _buildFloorChildren() : [],
                ),

                const SizedBox(height: 10),

                _buildTopSection(
                  label: 'Refreshement Area',
                  expanded: _refreshExpanded,
                  onTap: () => setState(() => _refreshExpanded = !_refreshExpanded),
                  children: _refreshExpanded ? _buildRefreshmentChildren() : [],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top-level accordion section ─────────────────────────────────────────────
  Widget _buildTopSection({
    required String label,
    required bool expanded,
    required VoidCallback onTap,
    required List<Widget> children,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row
          GestureDetector(
            onTap: onTap,
            child: Container(
              color: expanded ? _kPillExpanded : _kPillNormal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
                    size: 20,
                    color: Colors.black87,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'googlesans',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Children (already inside same rounded container)
          ...children,
        ],
      ),
    );
  }

  // ── Floor children ──────────────────────────────────────────────────────────
  List<Widget> _buildFloorChildren() {
    final List<Widget> rows = [];

    for (int i = 0; i < _kFloors.length; i++) {
      final floor = _kFloors[i];
      final floorValue = floor['value'] as int;
      final isExpanded = _expandedFloorIndex == i;

      // Thin divider
      rows.add(const Divider(height: 1, color: Colors.white38, thickness: 1));

      // Floor row
      rows.add(
        GestureDetector(
          onTap: () {
            setState(() {
              _expandedFloorIndex = isExpanded ? null : i;
            });
          },
          child: Container(
            color: isExpanded ? _kPillExpanded : _kPillChild,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
                  size: 18,
                  color: Colors.black87,
                ),
                const SizedBox(width: 10),
                Text(
                  floor['label'] as String,
                  style: const TextStyle(
                    fontFamily: 'googlesans',
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Room types for this floor (if expanded)
      if (isExpanded) {
        final types = _kFloorRoomTypes[floorValue] ?? [];
        for (final t in types) {
          rows.add(const Divider(height: 1, color: Colors.white38, thickness: 1));
          rows.add(_buildLeafRow(
            label: t['label']!,
            onTap: () => _returnResult(FilterResult(
              floor: floorValue,
              type: t['type'],
              displayLabel: '${floor['label']} › ${t['label']}',
            )),
          ));
        }
      }
    }

    return rows;
  }



  // ── Refreshment area children ────────────────────────────────────────────────
  List<Widget> _buildRefreshmentChildren() {
    return [
      for (final t in _kRefreshmentTypes) ...[
        const Divider(height: 1, color: Colors.white38, thickness: 1),
        _buildLeafRow(
          label: t['label']!,
          onTap: () => _returnResult(FilterResult(
            floor: null,
            type: t['type'],
            displayLabel: t['label']!,
          )),
        ),
      ]
    ];
  }

  // ── Leaf row (deepest level) ─────────────────────────────────────────────────
  Widget _buildLeafRow({
    required String label,
    required VoidCallback onTap,
    bool isAllRow = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: _kPillLeaf,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 15),
        child: Row(
          children: [
            const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.black54),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'googlesans',
                fontSize: 14,
                color: isAllRow ? Colors.black54 : Colors.black87,
                fontStyle: isAllRow ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _returnResult(FilterResult result) {
    if (widget.onResult != null) {
      widget.onResult!(result);
    } else {
      Navigator.of(context).pop(result);
    }
  }
}
