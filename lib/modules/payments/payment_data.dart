/// Where a vendor pays (`paymentBankPublic/main`).
class BankDetails {
  const BankDetails({required this.accountName, required this.accountNumber, required this.ifsc, required this.upiId});

  factory BankDetails.fromData(Map<String, dynamic> data) => BankDetails(
    accountName: data['accountName']?.toString() ?? '',
    accountNumber: data['accountNumber']?.toString() ?? '',
    ifsc: data['ifsc']?.toString() ?? '',
    upiId: data['upiId']?.toString() ?? '',
  );

  final String accountName, accountNumber, ifsc, upiId;
}

/// One payment as the vendor and the admin see it (a `paymentRequests` document).
class PaymentRequest {
  const PaymentRequest({required this.id, required this.uid, required this.label, required this.amount, required this.status, this.reviewReason = '', this.screenshotPath = '', this.claimedId = '', this.claimedAmount, this.claimedDate = '', this.claimedTime = ''});

  factory PaymentRequest.fromData(String id, Map<String, dynamic> data) => PaymentRequest(
    id: id,
    uid: data['uid']?.toString() ?? '',
    label: data['label']?.toString() ?? '',
    amount: (data['amount'] as num?) ?? 0,
    status: data['status']?.toString() ?? '',
    reviewReason: data['reviewReason']?.toString() ?? '',
    screenshotPath: data['screenshotPath']?.toString() ?? '',
    claimedId: data['claimedId']?.toString() ?? '',
    claimedAmount: data['claimedAmount'] as num?,
    claimedDate: data['claimedDate']?.toString() ?? '',
    claimedTime: data['claimedTime']?.toString() ?? '',
  );

  final String id, uid, label, status, reviewReason, screenshotPath, claimedId, claimedDate, claimedTime;
  final num amount;
  final num? claimedAmount;
}

/// The bank settings as the admin edits them (`paymentBankConfig/main`). The XX values mark what is not filled in yet.
class BankConfig {
  const BankConfig(this.data);
  final Map<String, dynamic> data;

  String text(String key) => data[key]?.toString() ?? '';
  List<String> get senders => [for (final s in data['smsSenders'] as List? ?? const []) s.toString()];
  List<Map<String, dynamic>> get patterns => [for (final p in data['smsPatterns'] as List? ?? const []) Map<String, dynamic>.from(p as Map)];
  int number(String key, int fallback) => (data[key] as num?)?.toInt() ?? fallback;
}

/// Shown until the admin saves real values. The same placeholders as the server's defaults.
const placeholderBankConfig = BankConfig({
  'accountName': 'XX-ACCOUNT-NAME',
  'accountNumber': 'XX-ACCOUNT-NUMBER',
  'ifsc': 'XX-IFSC',
  'upiId': 'XX-UPI-ID',
  'smsSenders': ['XX-SENDER-ID'],
  'smsPatterns': [
    {'credit': 'XX-CREDIT-WORDS', 'amount': 'XX-AMOUNT-REGEX', 'paymentId': 'XX-PAYMENT-ID-REGEX'},
  ],
  'windowHours': 3,
  'dailyScreenshots': 5,
});

String paymentMoney(num amount) => amount == amount.roundToDouble() ? '₹${amount.round()}' : '₹${amount.toStringAsFixed(2)}';

