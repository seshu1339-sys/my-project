import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../domain/catalog.dart';
import '../domain/quick_items.dart';
import 'moderation_dialogs.dart';
import 'quick_add.dart';

String _cleanError(Object e) => '$e'.replaceFirst(RegExp(r'^\[[^\]]*\]\s*'), '').replaceFirst('Bad state: ', '');

/// Admin: every Quick Add Staff and Vendor, with a button to add one.
class QuickAccountsPage extends StatelessWidget {
  const QuickAccountsPage({super.key, required this.store, this.stream, this.call});
  final Store store;
  final Stream<List<Entry>>? stream;
  final QuickCall? call;

  Stream<List<Entry>> _accounts() =>
      stream ?? store.firestore.collection('quickAccounts').snapshots().map((s) => s.docs.map((d) => Entry(d.id, d.data())).toList());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quick Add: Staff and Vendors')),
    floatingActionButton: FloatingActionButton.extended(
      key: const ValueKey('quick-account-add'),
      onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => QuickAccountForm(store: store, call: call))),
      icon: const Icon(Icons.person_add_alt),
      label: const Text('Add Staff / Vendor'),
    ),
    body: StreamBuilder<List<Entry>>(
      stream: _accounts(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Accounts could not load.'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final accounts = [...snapshot.data!]..sort((a, b) => a.text('code').compareTo(b.text('code')));
        if (accounts.isEmpty) return const Center(child: Text('No Staff or Vendor accounts yet. Tap "Add Staff / Vendor".'));
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: [
            for (final a in accounts)
              Card(
                child: ListTile(
                  key: ValueKey('quick-account-${a.id}'),
                  leading: _Avatar(url: a.text('photoUrl')),
                  title: Text('${a.text('name')}  •  ${a.text('code')}'),
                  subtitle: Text([
                    a.text('role') == 'vendor' ? 'Vendor' : 'Staff',
                    if (a.text('locationName').isNotEmpty) a.text('locationName'),
                    if (a.data['active'] != true) 'INACTIVE',
                  ].join(' • ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => QuickAccountDetailPage(store: store, uid: a.id, call: call)),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, this.radius = 24});
  final String url;
  final double radius;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundImage: url.isEmpty ? null : NetworkImage(url),
    onBackgroundImageError: url.isEmpty ? null : (_, _) {},
    child: url.isEmpty ? const Icon(Icons.person) : null,
  );
}

/// Admin: add a Staff or Vendor (name, phone, email, photo, and for a Vendor the one shop location).
class QuickAccountForm extends StatefulWidget {
  const QuickAccountForm({super.key, required this.store, this.call, this.pickPhoto});
  final Store store;
  final QuickCall? call;
  // Test seam: returns the uploaded photo's URL.
  final Future<String?> Function()? pickPhoto;
  @override
  State<QuickAccountForm> createState() => _QuickAccountFormState();
}

class _QuickAccountFormState extends State<QuickAccountForm> {
  String role = 'staff';
  final name = TextEditingController(), phone = TextEditingController(), email = TextEditingController(), shop = TextEditingController();
  String photoUrl = '';
  bool busy = false;
  List<String> errors = const [];

  @override
  void dispose() {
    for (final c in [name, phone, email, shop]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<String?> _defaultPick() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    return file == null ? null : widget.store.upload(file, folder: 'catalog');
  }

  Future<void> _photo() async {
    try {
      final url = await (widget.pickPhoto ?? _defaultPick)();
      if (url != null && mounted) setState(() => photoUrl = url);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(e))));
    }
  }

  List<String> _errors() => [
    if (name.text.trim().length < 2) 'Enter the name.',
    if (!RegExp(r'^\+?[0-9][0-9 -]{6,17}$').hasMatch(phone.text.trim())) 'Enter a valid phone number.',
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.text.trim())) 'Enter a valid email address.',
    if (photoUrl.isEmpty) 'Add the person\'s photo.',
  ];

  Future<void> create() async {
    final problems = _errors();
    setState(() => errors = problems);
    if (problems.isNotEmpty) return;
    setState(() => busy = true);
    try {
      final result = await (widget.call ?? widget.store.call)('createQuickAccount', {
        'role': role,
        'name': name.text.trim(),
        'phone': phone.text.trim(),
        'email': email.text.trim(),
        'photoUrl': photoUrl,
        if (role == 'vendor' && shop.text.trim().isNotEmpty) 'shopName': shop.text.trim(),
      });
      if (!mounted) return;
      setState(() => busy = false);
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text('Created: ${result['code']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${name.text.trim()} can now sign in. Send them this link so they set their own password:'),
                const SizedBox(height: 8),
                SelectableText('${result['resetLink']}', key: const ValueKey('quick-reset-link')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: '${result['resetLink']}')), child: const Text('Copy link')),
            FilledButton(onPressed: () => Navigator.pop(dialog), child: const Text('Done')),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(e))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Staff / Vendor')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            key: const ValueKey('quick-account-role'),
            segments: const [
              ButtonSegment(value: 'staff', label: Text('Staff (ST...)'), icon: Icon(Icons.badge_outlined)),
              ButtonSegment(value: 'vendor', label: Text('Vendor (VN...)'), icon: Icon(Icons.storefront)),
            ],
            selected: {role},
            onSelectionChanged: (s) => setState(() => role = s.first),
          ),
          const SizedBox(height: 16),
          Row(children: [
            _Avatar(url: photoUrl, radius: 40),
            const SizedBox(width: 16),
            OutlinedButton.icon(key: const ValueKey('quick-account-photo'), onPressed: _photo, icon: const Icon(Icons.upload), label: Text(photoUrl.isEmpty ? 'Add photo' : 'Change photo')),
          ]),
          const SizedBox(height: 12),
          TextField(key: const ValueKey('quick-account-name'), controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(key: const ValueKey('quick-account-phone'), controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(key: const ValueKey('quick-account-email'), controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (they sign in with this)', border: OutlineInputBorder())),
          if (role == 'vendor') ...[
            const SizedBox(height: 12),
            TextField(controller: shop, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Shop name (optional)', border: OutlineInputBorder())),
            const Padding(
              key: ValueKey('quick-account-location-note'),
              padding: EdgeInsets.only(top: 8),
              child: Text('No location to type: the vendor takes GPS at the shop on first login, and the nearest town and pincode are set and locked automatically.'),
            ),
          ],
          const SizedBox(height: 16),
          if (errors.isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final e in errors) Text('• $e')]))),
          const SizedBox(height: 8),
          SizedBox(height: 52, child: FilledButton(key: const ValueKey('quick-account-create'), onPressed: busy ? null : create, child: busy ? const CircularProgressIndicator() : const Text('Create account'))),
        ],
      ),
    );
  }
}

/// Admin: one person's details (opened by typing their code in the admin search), the
/// Active/Inactive switch, and their pending items with Approve / Reject.
class QuickAccountDetailPage extends StatelessWidget {
  const QuickAccountDetailPage({super.key, required this.store, required this.uid, this.call, this.accountStream, this.itemsStream});
  final Store store;
  final String uid;
  final QuickCall? call;
  final Stream<Entry?>? accountStream;
  final Stream<List<Entry>>? itemsStream;

  Stream<Entry?> _account() =>
      accountStream ?? store.firestore.collection('quickAccounts').doc(uid).snapshots().map((d) => d.exists ? Entry(d.id, d.data()!) : null);
  Stream<List<Entry>> _items() =>
      itemsStream ??
      store.firestore.collection('quickItems').where('ownerUid', isEqualTo: uid).snapshots().map((s) => s.docs.map((d) => Entry(d.id, d.data())).toList());
  QuickCall get _call => call ?? store.call;

  Future<void> _setActive(BuildContext context, bool active) =>
      runModerationAction(context, () => _call('setQuickAccountActive', {'uid': uid, 'active': active}));

  Future<void> _edit(BuildContext context, Entry account) async {
    final name = TextEditingController(text: account.text('name')), phone = TextEditingController(text: account.text('phone'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setState) => AlertDialog(
          title: const Text('Edit details'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await runModerationAction(
      context,
      () => _call('updateQuickAccount', {'uid': uid, 'name': name.text.trim(), 'phone': phone.text.trim()}),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Staff / Vendor details')),
    body: StreamBuilder<Entry?>(
      stream: _account(),
      builder: (context, accountSnap) => StreamBuilder<List<Entry>>(
        stream: _items(),
        builder: (context, itemsSnap) {
          final account = accountSnap.data;
          if (!accountSnap.hasData && accountSnap.connectionState != ConnectionState.active) return const Center(child: CircularProgressIndicator());
          if (account == null) return const Center(child: Text('This account could not be found.'));
          final active = account.data['active'] == true;
          final items = itemsSnap.data ?? const <Entry>[];
          final pending = items.where((i) => i.text('status') == 'pending').toList();
          final others = items.where((i) => i.text('status') != 'pending').toList()..sort((a, b) => b.id.compareTo(a.id));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                _Avatar(url: account.text('photoUrl'), radius: 44),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(account.text('name'), style: Theme.of(context).textTheme.headlineSmall),
                    Text('${account.text('code')} • ${account.text('role') == 'vendor' ? 'Vendor' : 'Staff'}', key: const ValueKey('quick-detail-code')),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.phone), title: Text(account.text('phone'))),
              ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.email_outlined), title: Text(account.text('email'))),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined),
                title: Text(
                  account.text('role') != 'vendor'
                      ? 'Any town (found from GPS)'
                      : account.data['shopLocked'] == true
                      ? '${account.text('locationTown')}, ${account.text('locationDistrict')} • ${account.text('locationPincode')}'
                      : 'Shop location not set yet',
                  key: const ValueKey('quick-detail-location'),
                ),
                subtitle: account.text('role') == 'vendor'
                    ? Text(account.data['shopLocked'] == true ? 'Locked at the shop by GPS. The vendor cannot change it.' : 'The vendor sets it by GPS at the shop.')
                    : null,
                trailing: account.text('role') == 'vendor' && account.data['shopLocked'] == true
                    ? TextButton(
                        key: const ValueKey('quick-unlock-shop'),
                        onPressed: () => runModerationAction(context, () => _call('updateQuickAccount', {'uid': uid, 'resetShopLocation': true})),
                        child: const Text('Unlock'),
                      )
                    : null,
              ),
              SwitchListTile(
                key: const ValueKey('quick-active-switch'),
                contentPadding: EdgeInsets.zero,
                title: Text(active ? 'Active' : 'Inactive', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Only Active accounts can open Quick Add and upload.'),
                value: active,
                onChanged: (v) => _setActive(context, v),
              ),
              Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: () => _edit(context, account), icon: const Icon(Icons.edit_outlined), label: const Text('Edit details'))),
              const Divider(height: 32),
              Row(children: [
                Expanded(child: Text('Pending items (${pending.length})', style: Theme.of(context).textTheme.titleLarge)),
                if (pending.length > 1)
                  FilledButton(
                    key: const ValueKey('quick-approve-all'),
                    onPressed: () => runModerationAction(context, () => _call('reviewQuickItems', {'itemIds': [for (final i in pending) i.id], 'approved': true})),
                    child: const Text('Approve all'),
                  ),
              ]),
              if (pending.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No items waiting.')),
              for (final item in pending) QuickItemReviewTile(store: store, item: item, call: call),
              if (others.isNotEmpty) ...[
                const Divider(height: 32),
                Text('Earlier items', style: Theme.of(context).textTheme.titleLarge),
                for (final item in others) QuickItemReviewTile(store: store, item: item, call: call),
              ],
            ],
          );
        },
      ),
    ),
  );
}

/// One item for the admin: who added it, where, when it would run, and Approve / Reject.
class QuickItemReviewTile extends StatelessWidget {
  const QuickItemReviewTile({super.key, required this.store, required this.item, this.call, this.now});
  final Store store;
  final Entry item;
  final QuickCall? call;
  final DateTime Function()? now;

  Future<void> _reject(BuildContext context) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(item.text('status') == 'approved' ? 'Take this item down' : 'Reject this item'),
        content: TextField(key: const ValueKey('quick-reject-reason'), controller: reason, decoration: const InputDecoration(labelText: 'Reason (shown to them)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('quick-reject-confirm'), onPressed: () => Navigator.pop(dialog, true), child: const Text('Reject')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runModerationAction(context, () => (call ?? store.call)('reviewQuickItems', {'itemIds': [item.id], 'approved': false, 'reason': reason.text.trim()}));
  }

  String _when(QuickPhase phase) {
    switch (phase) {
      case QuickPhase.pending:
        final start = quickTime(item.data['requestedStartAt']);
        final hours = item.number('durationMs') / 3600000;
        final length = hours >= 24 ? '${(hours / 24).round()}d' : '${hours.round()}h';
        return 'Wants to start ${item.text('startMode') == 'schedule' && start != null ? quickDateTimeLabel(start) : 'as soon as approved'} • shows for $length';
      case QuickPhase.scheduled:
        return 'Starts ${quickDateTimeLabel(quickStartsAt(item)!)}';
      case QuickPhase.live:
        return 'Live until ${quickDateTimeLabel(quickExpiresAt(item)!)}';
      case QuickPhase.expired:
        return 'Ended ${quickDateTimeLabel(quickExpiresAt(item) ?? DateTime.now())}';
      case QuickPhase.rejected:
        return 'Rejected${item.text('decisionReason').isEmpty ? '' : ': ${item.text('decisionReason')}'}';
      case QuickPhase.cancelled:
        return 'Cancelled by the owner';
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = quickPhase(item, (now ?? DateTime.now)());
    return Card(
      key: ValueKey('quick-review-${item.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            QuickItemPhoto(store: store, item: item, size: 72),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.text('name'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                Text('₹${item.number('price')} ${item.text('unit')} • ${item.text('categoryName')}'),
                Text('Location: ${item.text('locationName')}'),
                if (item.text('locationPincode').isNotEmpty) Text('Pincode: ${item.text('locationPincode')}'),
                Text('Added by: ${item.text('ownerName')} (${item.text('ownerCode')})', key: ValueKey('quick-added-by-${item.id}')),
              ]),
            ),
          ]),
          const SizedBox(height: 6),
          Text(_when(phase), style: const TextStyle(fontWeight: FontWeight.w600)),
          if (phase == QuickPhase.pending || phase == QuickPhase.scheduled || phase == QuickPhase.live)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 8, children: [
                if (phase == QuickPhase.pending)
                  FilledButton.icon(
                    key: ValueKey('quick-approve-${item.id}'),
                    onPressed: () => runModerationAction(context, () => (call ?? store.call)('reviewQuickItems', {'itemIds': [item.id], 'approved': true})),
                    icon: const Icon(Icons.check),
                    label: const Text('Approve'),
                  ),
                OutlinedButton.icon(
                  key: ValueKey('quick-reject-${item.id}'),
                  onPressed: () => _reject(context),
                  icon: const Icon(Icons.close),
                  label: Text(phase == QuickPhase.pending ? 'Reject' : 'Take down'),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Admin: all quick items with who added them and where; approve or reject one by one or all.
class QuickItemsAdminPage extends StatefulWidget {
  const QuickItemsAdminPage({super.key, required this.store, this.stream, this.call});
  final Store store;
  final Stream<List<Entry>>? stream;
  final QuickCall? call;
  @override
  State<QuickItemsAdminPage> createState() => _QuickItemsAdminPageState();
}

class _QuickItemsAdminPageState extends State<QuickItemsAdminPage> {
  QuickPhase? filter = QuickPhase.pending;

  Stream<List<Entry>> _items() =>
      widget.stream ?? widget.store.firestore.collection('quickItems').snapshots().map((s) => s.docs.map((d) => Entry(d.id, d.data())).toList());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quick Add items')),
    body: StreamBuilder<List<Entry>>(
      stream: _items(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Items could not load.'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final now = DateTime.now();
        final all = [...snapshot.data!]..sort((a, b) => b.id.compareTo(a.id));
        final shown = all.where((i) => filter == null || quickPhase(i, now) == filter).toList();
        final pending = all.where((i) => quickPhase(i, now) == QuickPhase.pending).toList();
        return Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                for (final entry in <QuickPhase?, String>{
                  QuickPhase.pending: 'Pending',
                  QuickPhase.live: 'Live',
                  QuickPhase.scheduled: 'Scheduled',
                  QuickPhase.expired: 'Expired',
                  QuickPhase.rejected: 'Rejected',
                  null: 'All',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('quick-filter-${entry.key?.name ?? 'all'}'),
                      label: Text(entry.value),
                      selected: filter == entry.key,
                      onSelected: (_) => setState(() => filter = entry.key),
                    ),
                  ),
              ]),
            ),
            if (pending.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  Expanded(child: Text('${pending.length} waiting for approval')),
                  FilledButton(
                    key: const ValueKey('quick-approve-all-pending'),
                    onPressed: () => runModerationAction(
                      context,
                      () => (widget.call ?? widget.store.call)('reviewQuickItems', {'itemIds': [for (final i in pending.take(100)) i.id], 'approved': true}),
                    ),
                    child: const Text('Approve all'),
                  ),
                ]),
              ),
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('Nothing here.'))
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [for (final item in shown) QuickItemReviewTile(store: widget.store, item: item, call: widget.call)],
                    ),
            ),
          ],
        );
      },
    ),
  );
}
