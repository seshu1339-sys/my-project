import 'package:flutter/material.dart';

import '../data/store.dart';
import 'account.dart';
import 'shared.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key, required this.store});
  final Store store;
  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final address = TextEditingController();
  bool busy = false;
  String paymentMethod = 'direct_vendor';
  final requestId = DateTime.now().microsecondsSinceEpoch.toString();
  @override
  void initState() {
    super.initState();
    address.text = widget.store.address;
    final configuredDefault = widget.store.business.text('defaultPaymentMethod');
    if (configuredDefault.isNotEmpty) paymentMethod = configuredDefault;
  }

  @override
  void dispose() {
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Your shopping bag')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (widget.store.cart.isEmpty) ...[
                const SizedBox(height: 60),
                const Icon(Icons.shopping_bag_outlined, size: 72),
                const SizedBox(height: 20),
                const Center(
                  child: Text(
                    'Your next local find belongs here.',
                    style: TextStyle(fontSize: 22),
                  ),
                ),
              ] else ...[
                for (final line in widget.store.cart.entries)
                  Builder(
                    builder: (context) {
                      final p = widget.store.product(line.key);
                      if (p == null) {
                        return ListTile(
                          title: const Text('Item no longer available'),
                          trailing: IconButton(
                            onPressed: () {
                              widget.store.cart.remove(line.key);
                              setState(() {});
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        );
                      }
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.text('name'),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      money(
                                        p.price(widget.store.pincode) *
                                            line.value,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove one',
                                    onPressed: busy
                                        ? null
                                        : () => widget.store.add(p, -1),
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                  ),
                                  Text('${line.value}'),
                                  IconButton(
                                    tooltip: 'Add one',
                                    onPressed: busy
                                        ? null
                                        : () => widget.store.add(p),
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 24),
                Builder(
                  builder: (context) {
                    final deliveryConfigured =
                        widget.store.business.number('deliveryFee', 0) > 0;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Subtotal ${money(widget.store.total)}',
                          style: TextStyle(
                            fontSize: deliveryConfigured ? 18 : 26,
                            fontWeight: deliveryConfigured
                                ? FontWeight.normal
                                : FontWeight.bold,
                          ),
                        ),
                        if (deliveryConfigured) ...[
                          Text(
                            widget.store.deliveryFee > 0
                                ? 'Delivery fee ${money(widget.store.deliveryFee)}'
                                : 'Delivery fee Free',
                          ),
                          Text(
                            'Total ${money(widget.store.grandTotal)}',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const Text(
                  'Prices and availability are checked again when you submit. Payment follows the shop payment policy.',
                ),
                Builder(builder: (context) {
                  final business = widget.store.business;
                  final methods = <String, String>{
                    if (business.text('directVendorPaymentEnabled', 'true') != 'false') 'direct_vendor': 'Pay vendor directly',
                    if (business.text('cashOnDeliveryEnabled') == 'true') 'cash_on_delivery': 'Cash on delivery',
                    if (business.text('platformCollectionEnabled') == 'true') 'platform_collected': 'Platform payment (future)',
                  };
                  if (!methods.containsKey(paymentMethod)) paymentMethod = methods.keys.firstOrNull ?? 'direct_vendor';
                  return DropdownButtonFormField<String>(
                    initialValue: paymentMethod,
                    decoration: const InputDecoration(labelText: 'Payment option'),
                    items: methods.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(),
                    onChanged: busy ? null : (value) => setState(() => paymentMethod = value ?? 'direct_vendor'),
                  );
                }),
                const SizedBox(height: 20),
                if (widget.store.pincode.isEmpty)
                  const Text(
                    'Add a delivery pincode on the home page before ordering.',
                  ),
                TextField(
                  controller: address,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Delivery / service address',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (widget.store.pincode.isEmpty ||
                              address.text.trim().length < 10) {
                            message(
                              context,
                              'Set your pincode and enter a complete address (at least 10 characters).',
                            );
                            return;
                          }
                          if (widget.store.live && widget.store.user == null) {
                            await Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    AccountPage(store: widget.store),
                              ),
                            );
                            return;
                          }
                          setState(() => busy = true);
                          try {
                            final id = await widget.store.checkout(
                              address.text.trim(),
                              requestId,
                              paymentMethod: paymentMethod,
                            );
                            if (context.mounted) {
                              message(
                                context,
                                'Order $id submitted. The shop will confirm fulfilment.',
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              message(context, e);
                            }
                          } finally {
                            if (mounted) {
                              setState(() => busy = false);
                            }
                          }
                        },
                  child: Text(
                    busy
                        ? 'Submitting…'
                        : widget.store.live
                        ? 'Submit order request'
                        : 'Preview checkout',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
