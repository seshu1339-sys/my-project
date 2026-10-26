import 'location.dart';

typedef LatLon = ({double latitude, double longitude});

/// The customer's device position, for how far the shops are and the road to a shop. Asked at most once a visit (the permission
/// prompt); when the customer says no, nothing shows a distance. The place the customer chose in the app is not changed.
class CustomerPosition {
  CustomerPosition._();

  static LatLon? _known;
  static bool _asked = false;

  /// Test seam: how the position is found ([ask] true shows the permission prompt). Returns null when it is not given.
  static Future<LatLon?> Function({required bool ask}) finder = _device;

  static Future<LatLon?> _device({required bool ask}) async {
    try {
      final p = ask ? await currentPosition(action: 'show how far the shops are') : await currentPositionIfPermitted();
      return p == null ? null : (latitude: p.latitude, longitude: p.longitude);
    } catch (_) {
      return null;
    }
  }

  /// The position found so far this visit.
  static LatLon? get known => _known;

  /// The position: the one found already, else the device's without a prompt when allowed, else (once a visit, or when [again])
  /// asking. Null when the customer does not give it.
  static Future<LatLon?> find({bool again = false}) async {
    if (_known != null) return _known;
    _known = await finder(ask: false);
    if (_known != null || (_asked && !again)) return _known;
    _asked = true;
    return _known = await finder(ask: true);
  }

  static void reset() {
    _known = null;
    _asked = false;
    finder = _device;
  }
}
