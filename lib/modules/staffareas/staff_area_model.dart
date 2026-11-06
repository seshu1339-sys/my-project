import 'package:cloud_firestore/cloud_firestore.dart';

/// Staff Area System (functions/modules/staff-areas): named areas in a town (a centre + the town's radius), Free / Pending / Booked,
/// one staff member each; a daily target of Today's Offers per area; missed days and automatic deactivation.
// The work rules (owner, 6 Nov 2026), the same as functions/modules/staff-areas/rules.js DEFAULTS.
const defaultMonthlyPhotoTarget = 100;
const defaultMonthlyVendorTarget = 10;
const defaultMonthlyPaidVendorTarget = 2;
const defaultRateDaysPerWeek = 4;
const defaultMaxMissedDays = 7;
// A live photo must be taken within this distance of the shop.
const livePhotoMaxMetres = 100;
const staffAreaRadiusOptions = [1.0, 2.0, 3.0, 5.0];

/// The Terms & Conditions until the admin writes their own (the same as functions/modules/staff-areas/rules.js DEFAULT_TERMS).
/// Shown only in the staff app and the admin panel, never on a public or marketing screen.
const defaultStaffTerms = '''LOCAMARKET staff Terms & Conditions
1. There is no fixed salary. You earn a commission based on your work.
2. One area per staff member. You work only in the area you registered.
3. You add only Today's Offers for the shops in your area. You never change a vendor's profile, photos, items or normal prices.
4. You update the rates of the shops in your area on the minimum number of days every week, each with a live camera photo taken at the shop (within 100 metres, with real GPS). Photos sent from anywhere else never count.
5. You complete the targets for the day, the week and the month: live photos, shops visited, new vendors and new paid vendors. A month counts only when its monthly targets are complete.
6. Days without rate updates beyond the weekly allowance are missed days. When the allowed number of missed days is reached, your staff ID is deactivated automatically and your area is given to another person. You are warned one day before.
7. LOCAMARKET can change these rules at any time.''';

/// One area (a `staffAreas` document): where it is and whether it is taken. Who holds it is admin only (staffAreaHolders).
class StaffArea {
  const StaffArea({required this.id, required this.name, required this.town, required this.latitude, required this.longitude, required this.radiusKm, required this.status});

  factory StaffArea.fromData(String id, Map<String, dynamic> data) => StaffArea(
    id: id,
    name: data['name']?.toString() ?? '',
    town: data['town']?.toString() ?? '',
    latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
    longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
    radiusKm: (data['radiusKm'] as num?)?.toDouble() ?? 1,
    status: data['status']?.toString() ?? 'free',
  );

  final String id, name, town, status;
  final double latitude, longitude, radiusKm;

  bool get free => status == 'free';
}

/// Who holds an area (admin only).
class AreaHolder {
  const AreaHolder({required this.staffUid, required this.staffCode, required this.staffName, required this.staffPhone});
  factory AreaHolder.fromData(Map<String, dynamic> d) => AreaHolder(
    staffUid: d['staffUid']?.toString() ?? '',
    staffCode: d['staffCode']?.toString() ?? '',
    staffName: d['staffName']?.toString() ?? '',
    staffPhone: d['staffPhone']?.toString() ?? '',
  );
  final String staffUid, staffCode, staffName, staffPhone;
}

/// The admin's numbers (staffAreaSettings/main).
/// The target periods and measures (owner, 7 Nov 2026), with the words the admin and the staff read. The settings keys are
/// `<period><Measure>Target`, for example dailyShopTarget (functions/modules/staff-areas/rules.js). 0 = no target.
const staffTargetPeriods = <String, String>{'daily': 'Today', 'weekly': 'This week', 'monthly': 'This month'};
const staffTargetMeasures = <String, String>{'Photo': 'Live photos', 'Shop': 'Shops visited', 'Vendor': 'New vendors', 'PaidVendor': 'New Premium (paid) vendors'};
// The progress name of each measure in myStaffAreaToday's answer.
const _measureNames = <String, String>{'Photo': 'photos', 'Shop': 'shops', 'Vendor': 'vendors', 'PaidVendor': 'paidVendors'};
const _defaultTargets = <String, int>{'monthlyPhoto': defaultMonthlyPhotoTarget, 'monthlyVendor': defaultMonthlyVendorTarget, 'monthlyPaidVendor': defaultMonthlyPaidVendorTarget};

class StaffAreaSettings {
  const StaffAreaSettings({
    this.targets = const {},
    this.rateDaysPerWeek = defaultRateDaysPerWeek,
    this.maxMissedDays = defaultMaxMissedDays,
    this.terms = defaultStaffTerms,
  });
  factory StaffAreaSettings.fromData(Map<String, dynamic>? d) {
    int n(String key, int fallback) => (d?[key] as num?)?.toInt() ?? fallback;
    return StaffAreaSettings(
      targets: {
        for (final p in staffTargetPeriods.keys)
          for (final m in staffTargetMeasures.keys) '$p${m}Target': n('$p${m}Target', _defaultTargets['$p$m'] ?? 0),
      },
      rateDaysPerWeek: n('rateDaysPerWeek', defaultRateDaysPerWeek),
      maxMissedDays: n('maxMissedDays', defaultMaxMissedDays),
      terms: (d?['terms'] as String?)?.trim().isNotEmpty == true ? d!['terms'] as String : defaultStaffTerms,
    );
  }
  // Every target by its settings key ('dailyPhotoTarget' ...); a missing one is its default.
  final Map<String, int> targets;
  final int rateDaysPerWeek, maxMissedDays;
  final String terms;

  int target(String period, String measure) => targets['$period${measure}Target'] ?? _defaultTargets['$period$measure'] ?? 0;
  int get monthlyPhotoTarget => target('monthly', 'Photo');
  int get monthlyVendorTarget => target('monthly', 'Vendor');
  int get monthlyPaidVendorTarget => target('monthly', 'PaidVendor');
}

/// One target and how far it is: "12 / 20".
class TargetProgress {
  const TargetProgress(this.done, this.target);
  factory TargetProgress.fromData(Object? d, int fallbackTarget) => d is Map ? TargetProgress((d['done'] as num?)?.toInt() ?? 0, (d['target'] as num?)?.toInt() ?? fallbackTarget) : TargetProgress(0, fallbackTarget);
  final int done, target;
  bool get complete => done >= target;
  double get progress => target <= 0 ? 1 : (done / target).clamp(0, 1).toDouble();
}

/// One shop of my area on the dashboard.
class AreaShop {
  const AreaShop({required this.id, required this.name, required this.latitude, required this.longitude, required this.offerToday});
  final String id, name;
  final double latitude, longitude;
  final bool offerToday;
}

/// The staff dashboard (myStaffAreaToday): my area, today's count, missed days, the shops.
class AreaToday {
  const AreaToday({
    required this.area,
    required this.staffCount,
    required this.vendorCount,
    required this.missedThisMonth,
    required this.maxMissedDays,
    this.warning = '',
    this.shops = const [],
    this.day = '',
    this.photos = const TargetProgress(0, defaultMonthlyPhotoTarget),
    this.vendors = const TargetProgress(0, defaultMonthlyVendorTarget),
    this.paidVendors = const TargetProgress(0, defaultMonthlyPaidVendorTarget),
    this.rateDays = const TargetProgress(0, defaultRateDaysPerWeek),
    this.todayUpdates = 0,
    this.targets = const {},
  });

  factory AreaToday.fromData(Map<String, dynamic> d) {
    final a = d['area'];
    return AreaToday(
      area: a is Map ? StaffArea.fromData('${a['id']}', Map<String, dynamic>.from(a)) : null,
      photos: TargetProgress.fromData(d['photos'], defaultMonthlyPhotoTarget),
      vendors: TargetProgress.fromData(d['vendors'], defaultMonthlyVendorTarget),
      paidVendors: TargetProgress.fromData(d['paidVendors'], defaultMonthlyPaidVendorTarget),
      rateDays: TargetProgress.fromData(d['rateDays'], defaultRateDaysPerWeek),
      targets: {
        for (final p in staffTargetPeriods.keys)
          if (d['targets'] is Map && (d['targets'] as Map)[p] is Map)
            p: {for (final m in staffTargetMeasures.keys) m: TargetProgress.fromData(((d['targets'] as Map)[p] as Map)[_measureNames[m]], 0)},
      },
      todayUpdates: (d['todayUpdates'] as num?)?.toInt() ?? 0,
      staffCount: (d['staffCount'] as num?)?.toInt() ?? 0,
      vendorCount: (d['vendorCount'] as num?)?.toInt() ?? 0,
      missedThisMonth: (d['missedThisMonth'] as num?)?.toInt() ?? 0,
      maxMissedDays: (d['maxMissedDays'] as num?)?.toInt() ?? defaultMaxMissedDays,
      warning: d['warning']?.toString() ?? '',
      day: d['day']?.toString() ?? '',
      shops: [
        for (final s in (d['shops'] as List? ?? const []).whereType<Map>())
          AreaShop(
            id: '${s['id']}',
            name: '${s['name'] ?? ''}',
            latitude: (s['latitude'] as num?)?.toDouble() ?? 0,
            longitude: (s['longitude'] as num?)?.toDouble() ?? 0,
            offerToday: s['offerToday'] == true,
          ),
      ],
    );
  }

  final StaffArea? area;
  final int staffCount, vendorCount, missedThisMonth, maxMissedDays, todayUpdates;
  final String warning, day;
  final List<AreaShop> shops;
  // This month's targets and this week's rate days.
  final TargetProgress photos, vendors, paidVendors, rateDays;
  // Every target by period ('daily', 'weekly', 'monthly') and measure ('Photo', 'Shop', 'Vendor', 'PaidVendor').
  final Map<String, Map<String, TargetProgress>> targets;

  bool get monthComplete => targets['monthly']?.values.every((t) => t.complete) ?? (photos.complete && vendors.complete && paidVendors.complete);
}

/// "2026-11-06" in India time.
String istDayOf(DateTime moment) {
  final d = moment.toUtc().add(const Duration(hours: 5, minutes: 30));
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// The India date [days] after [day].
String addIstDays(String day, int days) {
  final d = DateTime.parse('${day}T00:00:00Z').add(Duration(days: days));
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String dayLabel(String day) {
  final p = day.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : day;
}

DateTime? timeOf(Object? v) => v is Timestamp ? v.toDate() : null;
