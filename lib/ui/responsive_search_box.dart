import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import '../services/strings.dart';
import 'design_tokens.dart';
import 'layout_settings.dart';
import 'shared.dart';

class ResponsiveSearchBox extends StatelessWidget {
  const ResponsiveSearchBox({
    super.key,
    required this.layout,
    required this.controller,
    required this.onChanged,
    required this.onAssistedSearch,
  });
  final ComponentLayout layout;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final ValueChanged<bool> onAssistedSearch;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final margin = layout.margin.clamp(0, c.maxWidth / 20).toDouble();
      final available = c.maxWidth - margin * 2;
      final width = layout.width(available, floor: math.min(available, 260));
      final padding = layout.padding.clamp(0, width / 24).toDouble();
      final gap = layout.n('gap', 2, 0, math.min(16, width / 32));
      final font = layout.font(
        Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16,
      );
      final height = layout.height(
        56,
        floor:
            math.max(48, MediaQuery.textScalerOf(context).scale(font) * 1.5) +
            padding * 2,
      );
      Color tint(String key, Color fallback) => layout.entry.text(key).isEmpty
          ? fallback
          : colorFromHex(layout.entry.text(key), fallback);
      Widget icon(
        String tooltip,
        IconData icon,
        String field,
        VoidCallback action,
        Color color,
      ) => IconButton(
        tooltip: tooltip,
        onPressed: action,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
        icon: Icon(
          icon,
          size: layout.n(field, 22, 16, width < 360 ? 28 : 48),
          color: color,
        ),
      );
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          key: const ValueKey('responsive-search-box'),
          margin: EdgeInsets.all(margin),
          width: width,
          height: height,
          padding: EdgeInsets.all(padding),
          decoration: entryDecoration(
            Entry(layout.entry.id, {
              'borderColor': '#E6EAE3',
              'borderWidth': 1,
              'radius': AppTokens.radiusLg,
              ...layout.entry.data,
            }),
            fallback: AppTokens.surface,
          ).copyWith(boxShadow: AppTokens.shadowSoft),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Search products'.tr(context),
                onPressed: onChanged,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
                style: IconButton.styleFrom(
                  backgroundColor: AppTokens.primary,
                  foregroundColor: tint('searchIconColor', Colors.white),
                  shape: const CircleBorder(),
                ),
                icon: Icon(Icons.search, size: layout.n('iconSize', 20, 16, width < 360 ? 28 : 48)),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: (_) => onChanged(),
                  onSubmitted: (_) => onChanged(),
                  style: sectionTextStyle(layout.styled(context))
                      .copyWith(fontSize: font),
                  decoration: InputDecoration(
                    hintText: 'Search products'.tr(context),
                    hintStyle: layout.entry.text('placeholderColor').isEmpty
                        ? null
                        : TextStyle(color: tint('placeholderColor', Colors.grey)),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              SizedBox(width: gap),
              icon(
                'Voice search'.tr(context),
                Icons.mic_none,
                'voiceIconSize',
                () => onAssistedSearch(false),
                tint('micIconColor', AppTokens.accentOrange),
              ),
              SizedBox(width: gap),
              icon(
                'Camera search'.tr(context),
                Icons.camera_alt_outlined,
                'imageIconSize',
                () => onAssistedSearch(true),
                tint('cameraIconColor', AppTokens.accentOrange),
              ),
            ],
          ),
        ),
      );
    },
  );
}
