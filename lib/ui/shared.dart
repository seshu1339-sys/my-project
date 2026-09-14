import 'package:flutter/material.dart';

import '../domain/catalog.dart';

void message(BuildContext context, Object text) => ScaffoldMessenger.of(context)
    .showSnackBar(
      SnackBar(content: Text(text.toString().replaceFirst('Bad state: ', ''))),
    );

class ProductArt extends StatelessWidget {
  const ProductArt(this.entry, {super.key, this.height = 160});
  final Entry entry;
  final double height;
  @override
  Widget build(BuildContext context) {
    final icons = [
      Icons.eco_outlined,
      Icons.coffee_outlined,
      Icons.headphones_outlined,
      Icons.shopping_basket_outlined,
      Icons.plumbing,
      Icons.electrical_services,
      Icons.foundation,
      Icons.handyman_outlined,
    ];
    final index = int.tryParse(entry.id.replaceAll(RegExp(r'\D'), '')) ?? 0;
    final placeholder = Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: [
          const Color(0xffe8efdc),
          const Color(0xfff2e9dd),
          const Color(0xffe4e9f1),
          const Color(0xfff5e7ce),
        ][index % 4],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        icons[index % icons.length],
        size: height * .42,
        color: const Color(0xff47624f),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: entry.text('imageUrl').isEmpty
          ? placeholder
          : Image.network(
              entry.text('imageUrl'),
              height: height,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, e, s) => placeholder,
            ),
    );
  }
}

String money(num value) =>
    '₹${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)}';
