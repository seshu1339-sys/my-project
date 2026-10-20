import 'package:flutter/material.dart';

import '../data/store.dart';
import '../services/strings.dart';
import 'account.dart';
import 'design_tokens.dart';
import 'layout_settings.dart';
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
    final configuredDefault = widget.store.business.text(
      'defaultPaymentMethod',
    );
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
      appBar: AppBar(title: Text('Your shopping bag'.tr(context))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (widget.store.cart.isEmpty) ...[
                const SizedBox(height: 60),
                Builder(
                  builder: (context) {
                    final iconLayout = layoutFor(
                      context,
                      widget.store.entries('settings'),
                      'cartEmptyIcon',
                    );
                    if (!iconLayout.visible) return const SizedBox.shrink();
                    final size = iconLayout.entry.number('iconSize') > 0
                        ? clampedNumber(
                            iconLayout.entry,
                            'iconSize',
                            72,
                            16,
                            48,
                          )
                        : 72.0;
                    final color = iconLayout.entry.text('textColor').isEmpty
                        ? null
                        : colorFromHex(
                            iconLayout.entry.text('textColor'),
                            Colors.black87,
                          );
                    return Center(
                      child: iconLayout.entry.text('iconUrl').isEmpty
                          ? Icon(
                              Icons.shopping_bag_outlined,
                              size: size,
                              color: color,
                            )
                          : Image.network(
                              iconLayout.entry.text('iconUrl'),
                              width: size,
                              height: size,
                              errorBuilder: (_, error, stack) => Icon(
                                Icons.shopping_bag_outlined,
                                size: size,
                                color: color,
                              ),
                            ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                Center(
                  child: pageHeadingText(
                    context,
                    layout: layoutFor(
                      context,
                      widget.store.entries('settings'),
                      'cartEmptyMessage',
                    ),
                    defaultText: 'Your next local find belongs here.',
                    fontSize: 22,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ] else ...[
                for (final line in widget.store.cart.entries)
                  Builder(
                    builder: (context) {
                      final p = widget.store.product(line.key);
                      if (p == null) {
                        return ListTile(
                          title: Text('Item no longer available'.tr(context)),
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
                                    tooltip: 'Remove one'.tr(context),
                                    onPressed: busy
                                        ? null
                                        : () => widget.store.add(p, -1),
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                  ),
                                  Text('${line.value}'),
                                  IconButton(
                                    tooltip: 'Add one'.tr(context),
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
                          'Subtotal {amount}'.tr(context, {'amount': money(widget.store.total)}),
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
                                ? 'Delivery fee {amount}'.tr(context, {
                                    'amount': money(widget.store.deliveryFee),
                                  })
                                : 'Delivery fee Free'.tr(context),
                          ),
                          Text(
                            'Total {amount}'.tr(context, {'amount': money(widget.store.grandTotal)}),
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
                Text('Prices and availability are checked again when you submit. Payment follows the shop payment policy.'.tr(context)),
                Builder(
                  builder: (context) {
                    final business = widget.store.business;
                    final methods = <String, String>{
                      if (business.text('directVendorPaymentEnabled', 'true') !=
                          'false')
                        'direct_vendor': 'Pay vendor directly'.tr(context),
                      if (business.text('cashOnDeliveryEnabled') == 'true')
                        'cash_on_delivery': 'Cash on delivery'.tr(context),
                      if (business.text('platformCollectionEnabled') == 'true')
                        'platform_collected': 'Platform payment (future)'.tr(context),
                    };
                    if (!methods.containsKey(paymentMethod))
                      paymentMethod =
                          methods.keys.firstOrNull ?? 'direct_vendor';
                    return DropdownButtonFormField<String>(
                      initialValue: paymentMethod,
                      decoration: InputDecoration(labelText: 'Payment option'.tr(context)),
                      items: methods.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (value) => setState(
                              () => paymentMethod = value ?? 'direct_vendor',
                            ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                if (widget.store.pincode.isEmpty)
                  Text('Add a delivery pincode on the home page before ordering.'.tr(context)),
                TextField(
                  controller: address,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: 'Delivery / service address'.tr(context)),
                ),
                const SizedBox(height: 16),
                Builder(builder: (context) => _buildSubmitButton(context)),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildSubmitButton(BuildContext context) {
    final layout = layoutFor(
      context,
      widget.store.entries('settings'),
      'cartSubmitButton',
    );
    if (!layout.visible) return const SizedBox.shrink();
    final backgroundColor = layout.entry.text('backgroundColor');
    final textColor = layout.entry.text('textColor');
    return FilledButton(
      style: backgroundColor.isEmpty && textColor.isEmpty
          ? null
          : FilledButton.styleFrom(
              backgroundColor: backgroundColor.isEmpty
                  ? null
                  : colorFromHex(backgroundColor, AppTokens.primary),
              foregroundColor: textColor.isEmpty
                  ? null
                  : colorFromHex(textColor, Colors.white),
            ),
      onPressed: busy
          ? null
          : () async {
              if (widget.store.pincode.isEmpty ||
                  address.text.trim().length < 10) {
                message(context, 'Set your pincode and enter a complete address (at least 10 characters).'.tr(context));
                return;
              }
              if (widget.store.live && widget.store.user == null) {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AccountPage(store: widget.store),
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
                    'Order {id} submitted. The shop will confirm fulfilment.'.tr(context, {'id': id}),
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
            ? 'Submitting…'.tr(context)
            : widget.store.live
            ? layout.entry.text('text', 'Submit order request').tr(context)
            : 'Preview checkout'.tr(context),
        style: overrideTextStyle(layout.entry),
      ),
    );
  }
}
