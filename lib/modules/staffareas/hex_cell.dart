import 'package:latlong2/latlong.dart';

/// The staff hexagon cells (owner, 13 Nov 2026), as the server sends them (functions/modules/staff-areas staffHexNearby). The grid and
/// the cell sizes live only on the server (functions/hex-grid.js); the app never computes a cell and never calls an outside service.

/// The staff member's home must be within this distance of the centre of their cell (the server checks the same).
const hexHomeMaxKm = 5.0;

/// "1 km", "2 km", "5 km" (the real 5 km cell is about 6.4 km across).
String hexSizeLabel(int sizeKm) => '$sizeKm km';

/// The population data credit (CC BY 4.0), shown with the cells and in the Terms.
const worldPopCredit = 'Cell sizes use population data from WorldPop (www.worldpop.org), licensed CC BY 4.0.';

List<LatLng> _points(Object? raw) => [
  if (raw is List)
    for (final p in raw)
      if (p is List && p.length == 2 && p[0] is num && p[1] is num) LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
];

/// One cell near the staff member: free (green), taken (red) or their own.
class HexCell {
  const HexCell({required this.cellId, required this.code, required this.sizeKm, required this.status, required this.outline});

  factory HexCell.fromData(Map<String, dynamic> d) => HexCell(
    cellId: '${d['cellId'] ?? ''}',
    code: '${d['code'] ?? ''}',
    sizeKm: (d['sizeKm'] as num?)?.toInt() ?? 1,
    status: '${d['status'] ?? 'free'}',
    outline: _points(d['outline']),
  );

  final String cellId, code, status;
  final int sizeKm;
  final List<LatLng> outline;

  bool get free => status == 'free';
  bool get mine => status == 'mine';
}

/// The cell where the staff member stands and the cells around it.
class HexNearby {
  const HexNearby({
    required this.cellId,
    required this.code,
    required this.sizeKm,
    required this.center,
    required this.status,
    required this.cells,
    this.homeMaxKm = hexHomeMaxKm,
    this.hasArea = false,
    this.myAreaCode = '',
  });

  factory HexNearby.fromData(Map<String, dynamic> d) {
    final center = _points([d['center']]);
    return HexNearby(
      cellId: '${d['cellId'] ?? ''}',
      code: '${d['code'] ?? ''}',
      sizeKm: (d['sizeKm'] as num?)?.toInt() ?? 1,
      center: center.isEmpty ? const LatLng(0, 0) : center.first,
      status: '${d['status'] ?? 'free'}',
      homeMaxKm: (d['homeMaxKm'] as num?)?.toDouble() ?? hexHomeMaxKm,
      hasArea: d['hasArea'] == true,
      myAreaCode: '${d['myAreaCode'] ?? ''}',
      cells: [
        for (final c in (d['cells'] as List?) ?? const [])
          if (c is Map) HexCell.fromData(Map<String, dynamic>.from(c)),
      ],
    );
  }

  final String cellId, code, status, myAreaCode;
  final int sizeKm;
  final LatLng center;
  final double homeMaxKm;
  final bool hasArea;
  final List<HexCell> cells;

  HexCell? get here => cells.where((c) => c.cellId == cellId).firstOrNull;
  bool get free => status == 'free';
}

/// Km from the cell's centre to a home pin, one decimal.
double homeDistanceKm(LatLng center, LatLng home) => (const Distance().as(LengthUnit.Meter, center, home) / 100).round() / 10;
