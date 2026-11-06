import 'catalog.dart';

// Sample data (functions/samples.js): a record is sample data when it is marked isSample, or when it belongs to a sample account
// (_sampleAccounts/<uid>). The admin panel shows a SAMPLE label on both; "Delete all samples" removes exactly these.

/// The fields that name a record's owner (vendor, staff member, provider, customer).
const sampleOwnerFields = ['vendorId', 'ownerId', 'staffUid', 'providerId', 'ownerUid', 'userId', 'addedByStaffUid'];

/// True when [data] (a record with id [id]) is sample data, given the sample accounts [owners].
bool isSampleData(String id, Map<String, dynamic> data, Set<String> owners) {
  if (data['isSample'] == true) return true;
  if (owners.isEmpty) return false;
  if (owners.contains(id)) return true;
  for (final field in sampleOwnerFields) {
    final v = data[field];
    if (v is String && v.isNotEmpty && owners.contains(v)) return true;
  }
  return false;
}

bool isSampleEntry(Entry e, Set<String> owners) => isSampleData(e.id, e.data, owners);
