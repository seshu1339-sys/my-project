import 'package:flutter/material.dart';

/// A large coloured choice: an icon, a title and a line under it, for start screens with a few big options (the vendor app's home,
/// the staff app's Add). A choice that does not apply is shown faded with a "blocked" mark, and still answers a tap (to explain why).
class BigOptionTile extends StatelessWidget {
  const BigOptionTile({super.key, required this.title, required this.subtitle, required this.icon, required this.color, this.enabled = true, required this.onTap});
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: enabled ? color : color.withValues(alpha: .45),
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Row(
          children: [
            Icon(icon, size: 48, color: Colors.white),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.white, fontSize: 15)),
                ],
              ),
            ),
            Icon(enabled ? Icons.chevron_right : Icons.block, color: Colors.white),
          ],
        ),
      ),
    ),
  );
}
