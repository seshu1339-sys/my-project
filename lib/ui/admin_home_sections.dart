import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/ads.dart';
import '../domain/catalog.dart';
import 'admin_ads.dart';
import 'admin_entry_list.dart';
import 'ads_column.dart';
import 'animation_settings.dart';
import 'color_picker_field.dart';
import 'home_ticker_strip.dart';
import 'layout_editor.dart';
import 'layout_settings.dart';
import 'notice_independence.dart';
import 'section_animations.dart';
import 'shared.dart';

/// The four parts of the home page the admin names the way the customer sees them. Each has its own page in Settings (and the boxes below the
/// right-hand ads are a second block on the Right Side Ads page).
class HomeSectionInfo {
  const HomeSectionInfo(this.part, this.title, this.where, this.icon);
  final String part, title, where;
  final IconData icon;
}

const homeSectionInfos = <String, HomeSectionInfo>{
  'scrollingText': HomeSectionInfo('scrollingText', 'Scrolling Text', 'The moving line across the very top of the home page.', Icons.text_rotation_none),
  'notice': HomeSectionInfo('notice', "Today's Offers", "The banner under it that says \"Today's <your town> Offers\" with the price chips. The town changes with the customer's location.", Icons.campaign_outlined),
  'promo': HomeSectionInfo('promo', "Today's Offers Box", 'The row of coloured boxes below the banner ("Today\'s Offer ...").', Icons.view_carousel_outlined),
  'ads': HomeSectionInfo('ads', 'Right Side Ads', 'The boxes down the right-hand side of the home page.', Icons.ad_units_outlined),
  'boxes': HomeSectionInfo('boxes', 'Boxes below the ads', 'The boxes under the ads on the right ("Curated for you" ...).', Icons.dashboard_outlined),
};

const _sampleOffers = [
  ('Fresh vegetables & fruits — best prices today', Color(0xff16a34a)),
  ('Dairy & Bakery — fresh stock daily', Color(0xff2563eb)),
  ('Grocery & staples combo savings', Color(0xffdc2626)),
];

String _speedLabel(int? s) => s == null ? 'Default speed' : s == 1 ? '1 (slowest)' : s == 10 ? '10 (fastest)' : '$s';

/// One page of Settings > Homepage sections: what the part is, a small live preview that plays the chosen animation, the animation, its
/// speed and the colours, then its items. Everything is written to the records the website already reads, so the older pages
/// (Animations, Layout, Scrolling Text, Promotions) keep working and show the same values.
class AdminHomeSectionPage extends StatelessWidget {
  const AdminHomeSectionPage({super.key, required this.store, required this.part});
  final Store store;
  final String part;

  void _open(BuildContext context, String title, Widget body) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: AppBar(title: Text(title)), body: body)));

  Widget _button(BuildContext context, String key, IconData icon, String label, String title, Widget body) => OutlinedButton.icon(
    key: ValueKey(key),
    onPressed: () => _open(context, title, body),
    icon: Icon(icon),
    label: Text(label),
  );

  Widget _layoutPage(String component) => SingleChildScrollView(padding: const EdgeInsets.all(20), child: LayoutFieldsForm(store: store, component: component));

  @override
  Widget build(BuildContext context) {
    final info = homeSectionInfos[part]!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(info.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('On the website: ${info.where}', key: const ValueKey('home-section-where')),
        const SizedBox(height: 12),
        HomeSectionEditor(key: ValueKey('editor-$part'), store: store, part: part),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            if (part == 'scrollingText') _button(context, 'open-scrolling-all', Icons.tune, 'All Scrolling Text options', 'Scrolling Text', AdminSingleRecord(store: store, section: 'scrollingText')),
            if (part == 'notice') _button(context, 'open-notice-layout', Icons.tune, "Size, fonts and more for Today's Offers", "Today's Offers", _layoutPage('notice')),
            if (part == 'promo') ...[
              _button(context, 'open-promo-items', Icons.list_alt, "The boxes in Today's Offers Box", "Today's Offers Box", AdminEntryList(store: store, section: 'promotions', placement: 'carousel')),
              _button(context, 'open-promo-layout', Icons.tune, 'Size, fonts and more', "Today's Offers Box", _layoutPage('promo')),
            ],
            if (part == 'ads') ...[
              _button(context, 'open-ads-manage', Icons.list_alt, 'Manage ads: add, edit, schedule, reports', 'Right Side Ads', AdminAdsPage(store: store)),
              _button(context, 'open-ads-layout', Icons.tune, 'Older ad boxes: size, fonts and more', 'Right Side Ads', _layoutPage('ads')),
            ],
          ],
        ),
        if (part == 'ads') ...[
          const Divider(height: 40),
          Text(homeSectionInfos['boxes']!.title, style: Theme.of(context).textTheme.titleLarge),
          Text('On the website: ${homeSectionInfos['boxes']!.where}'),
          const SizedBox(height: 12),
          HomeSectionEditor(key: const ValueKey('editor-boxes'), store: store, part: 'boxes'),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 8, children: [
            _button(context, 'open-boxes-items', Icons.list_alt, 'The boxes below the ads', 'Boxes below the ads', AdminEntryList(store: store, section: 'promotions', placement: 'box')),
            _button(context, 'open-boxes-layout', Icons.tune, 'Size, fonts and more', 'Boxes below the ads', _layoutPage('boxes')),
          ]),
        ],
      ],
    );
  }
}

/// The preview, the animation dropdown, the speed and the colours of one part, with Save.
class HomeSectionEditor extends StatefulWidget {
  const HomeSectionEditor({super.key, required this.store, required this.part});
  final Store store;
  final String part;
  @override
  State<HomeSectionEditor> createState() => _HomeSectionEditorState();
}

class _HomeSectionEditorState extends State<HomeSectionEditor> {
  Store get store => widget.store;
  String get part => widget.part;
  bool get isAds => part == 'ads';

  late String animation;
  int? speed; // 1..10, null = the original speed (not for Right Side Ads)
  late double scrollSpeed;
  late Map<String, String> colors;
  int replay = 0;
  bool busy = false;

  static const colorKeys = ['backgroundColor', 'textColor', 'borderColor'];
  static const colorNames = {'backgroundColor': 'Background color', 'textColor': 'Text color', 'borderColor': 'Border color'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Entry get _colorRecord {
    final id = isAds ? 'adsConfig' : part == 'scrollingText' ? 'scrollingText' : 'section_$part';
    return store.entries('settings').where((e) => e.id == id).firstOrNull ?? Entry(id, const {});
  }

  Entry get _animationsRecord => animationsDoc(store.entries('settings'));

  /// What the website uses right now (after the section's own start value).
  String get _savedAnimation {
    if (isAds) {
      final a = AdsConfig.from(store.entries('settings')).animation;
      return a;
    }
    final type = effectiveSectionConfig(store.entries('settings'), part).text('animation');
    return type.isEmpty ? 'none' : type;
  }

  int? get _savedSpeed {
    if (isAds) return AdsConfig.from(store.entries('settings')).animationSpeed;
    final v = _animationsRecord.data['${part}_speed'];
    final n = v is num ? v.toInt() : int.tryParse('$v');
    return n != null && n >= 1 && n <= 10 ? n : null;
  }

  void _load() {
    animation = _savedAnimation;
    speed = _savedSpeed;
    scrollSpeed = _colorRecord.number('speed', 70);
    colors = {for (final k in colorKeys) k: _colorRecord.text(k)};
  }

  String _name(String type) => homeAnimations[type] ?? (type == 'mix' ? 'Mix of all' : legacyAnimations[type] ?? type);

  /// Today's Offers only: stop inheriting from the Scrolling Text (the banner keeps its look).
  Future<void> _makeIndependent() async {
    setState(() => busy = true);
    try {
      final copied = await makeNoticeIndependent(store);
      if (mounted) message(context, "Done. Today's Offers now has its own settings ($copied copied from the Scrolling Text); the banner looks the same.");
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      // Saving this banner's colours must not be undone (or leaked) by the Scrolling Text: it gets its own settings first.
      if (part == 'notice') await makeNoticeIndependent(store);
      final record = _colorRecord;
      final changes = <String, dynamic>{for (final k in colorKeys) if (colors[k]!.isNotEmpty) k: colors[k]};
      final remove = {for (final k in colorKeys) if (colors[k]!.isEmpty && record.data.containsKey(k)) k};
      if (part == 'scrollingText') changes['speed'] = scrollSpeed.round();
      if (isAds) {
        changes['animation'] = animation;
        changes['animationSpeed'] = speed ?? 5;
      }
      await store.updateFields('settings', record.id, changes, remove: remove, fallback: Entry(record.id, {if (!isAds && part != 'scrollingText') 'section': part, if (isAds) 'name': 'Ads settings', ...changes}));
      if (!isAds) {
        final doc = _animationsRecord;
        final a = <String, dynamic>{'${part}_type': animation, if (speed != null) '${part}_speed': speed};
        await store.updateFields('settings', 'animations', a, remove: {if (speed == null && doc.data.containsKey('${part}_speed')) '${part}_speed'}, fallback: Entry('animations', {'name': 'Animations', ...a}));
      }
      if (mounted) {
        setState(_load);
        message(context, 'Saved. The website shows it at once.');
      }
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // --- the preview -------------------------------------------------------------------------------------------------

  Entry get _draftEntry => Entry('preview', {'animation': animation, 'entranceMs': entranceMillis(speed ?? 9)});

  Color? _color(String key) => colors[key]!.isEmpty ? null : colorFromHex(colors[key]!, Colors.transparent);

  Widget _play(Widget child) => KeyedSubtree(key: ValueKey('preview-$part-$animation-${speed ?? 0}-$replay'), child: applyEntranceAnimation(_draftEntry, child));

  List<Entry> get _realCarousel => [for (final p in store.entries('promotions')) if (p.text('placement') == (part == 'boxes' ? 'box' : 'carousel') && p.active) p].take(3).toList();

  Widget _preview(BuildContext context) {
    final bg = _color('backgroundColor'), fg = _color('textColor'), border = _color('borderColor');
    final textStyle = TextStyle(color: fg ?? Colors.black87, fontWeight: FontWeight.w700);
    switch (part) {
      case 'scrollingText':
        final real = noticeTickerText(store.entries('settings').where((e) => e.id == 'scrollingText').firstOrNull ?? const Entry('x', {}), store.language);
        final strip = TickerStrip(
          key: ValueKey('preview-strip-${scrollSpeed.round()}'),
          text: real.isEmpty ? 'Fresh offers every day  •  Shop local  •  Free delivery above ₹500' : real,
          textColor: fg ?? Colors.white,
          backgroundColor: bg ?? const Color(0xffd32f2f),
          borderColor: border == null ? null : colors['borderColor'],
          borderWidth: border == null ? 0 : 2,
          speed: scrollSpeed.clamp(10, 300).toDouble(),
          height: 36,
        );
        // "Marquee" is the strip's own scrolling; the others play on it as it appears.
        return animation == 'marquee' ? strip : _play(strip);
      case 'notice':
        final town = store.town.isEmpty ? 'Narsipatnam' : store.town;
        return _play(
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: bg ?? const Color(0xffe8f3fb), borderRadius: BorderRadius.circular(8), border: border == null ? null : Border.all(color: border, width: 2)),
            // one scrollable row, like the real strip, so a narrow screen never overflows
            child: SingleChildScrollView(scrollDirection: Axis.horizontal, physics: const NeverScrollableScrollPhysics(), child: Row(children: [
              Icon(Icons.campaign, size: 18, color: fg ?? const Color(0xff0b5d3b)),
              const SizedBox(width: 8),
              Text("Today's $town Offers", maxLines: 1, style: textStyle),
              const SizedBox(width: 12),
              for (final chip in const ['Apple ₹25/1 kg', 'Tomato ₹25/1 kg'])
                Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), child: Text(chip, style: const TextStyle(fontSize: 11))),
            ])),
          ),
        );
      case 'promo':
      case 'boxes':
        final real = _realCarousel;
        final items = real.isNotEmpty
            ? [for (final p in real) (p.text('name', p.text('title')), colorFromHex(p.text('backgroundColor'), const Color(0xff16a34a)), p.text('description'))]
            : [for (final o in _sampleOffers) (part == 'boxes' ? 'Curated for you' : "Today's Offer", o.$2, o.$1)];
        return _play(
          Row(children: [
            for (final (title, color, body) in items)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(10),
                  height: 96,
                  decoration: BoxDecoration(color: bg ?? color, borderRadius: BorderRadius.circular(12), border: border == null ? null : Border.all(color: border, width: 2)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg ?? Colors.white, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Expanded(child: Text(body, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg ?? Colors.white, fontSize: 11))),
                  ]),
                ),
              ),
          ]),
        );
      default: // ads: the real boxes changing from one ad to the next with the chosen animation
        final config = AdsConfig.from([Entry('adsConfig', {...store.entries('settings').where((e) => e.id == 'adsConfig').firstOrNull?.data ?? const {}, 'animation': animation, 'animationSpeed': speed ?? 5, 'seconds': 2, 'borderColor': colors['borderColor'] ?? '', 'backgroundColor': colors['backgroundColor'] ?? '', 'textColor': colors['textColor'] ?? ''})]);
        final live = liveAds(store.entries('ads'), DateTime.now(), showAll: true);
        final ads = live.length >= 2
            ? live.take(4).toList()
            : const [
                Entry('s1', {'title': 'Big Savings Everyday', 'contentType': 'text', 'backgroundColor': '#16A34A', 'textColor': '#FFFFFF', 'badge': 'New'}),
                Entry('s2', {'title': 'Suma Fresh Mart', 'text': 'Your one-stop supermarket nearby', 'contentType': 'text', 'backgroundColor': '#B45309', 'textColor': '#FFFFFF'}),
                Entry('s3', {'title': 'Farm Fresh Fruits', 'text': 'Up to 40% OFF', 'contentType': 'text', 'backgroundColor': '#15803D', 'textColor': '#FFFFFF'}),
              ];
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(width: 260, height: 150, child: _AdPreview(key: ValueKey('ad-preview-$animation-${speed ?? 0}-$replay-${colors.values.join()}'), ads: ads, config: config)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = _savedAnimation;
    final defaultType = homeSectionDefaults[part];
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (part == 'notice' && !noticeIsIndependent(store.entries('settings')))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    key: const ValueKey('notice-shared'),
                    color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: .4),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('This banner still borrows its label, border and colours from the Scrolling Text, so changing one changes the other.'),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(key: const ValueKey('decouple-notice'), onPressed: busy ? null : _makeIndependent, icon: const Icon(Icons.link_off), label: const Text("Make it independent (it keeps today's look)")),
                      ]),
                    ),
                  ),
                ),
              Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('Preview', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('(${_name(animation)})', key: ValueKey('preview-name-$part')),
                TextButton.icon(key: ValueKey('play-$part'), onPressed: () => setState(() => replay++), icon: const Icon(Icons.play_arrow), label: const Text('Play again')),
              ]),
              Container(
                key: ValueKey('preview-box-$part'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .4), borderRadius: BorderRadius.circular(10)),
                child: ClipRect(child: _preview(context)),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('anim-$part-$animation'),
                      initialValue: homeAnimations.containsKey(animation) || animation == 'mix' || legacyAnimations.containsKey(animation) ? animation : 'none',
                      isExpanded: true,
                      decoration: InputDecoration(labelText: 'Animation (now: ${_name(saved)}${defaultType == saved ? ', the start value' : ''})', isDense: true, border: const OutlineInputBorder()),
                      items: [
                        for (final e in homeAnimations.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                        if (isAds) const DropdownMenuItem(value: 'mix', child: Text('Mix of all')),
                        if (legacyAnimations.containsKey(animation)) DropdownMenuItem(value: animation, child: Text(legacyAnimations[animation]!)),
                      ],
                      onChanged: (v) => setState(() {
                        animation = v ?? 'none';
                        replay++;
                      }),
                    ),
                  ),
                  if (part == 'scrollingText')
                    SizedBox(
                      width: 260,
                      child: TextFormField(
                        key: const ValueKey('scroll-speed'),
                        initialValue: '${scrollSpeed.round()}',
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: 'Scroll speed, pixels per second (now: ${_colorRecord.number('speed', 70).round()})', isDense: true, border: const OutlineInputBorder()),
                        onChanged: (v) => setState(() => scrollSpeed = (double.tryParse(v) ?? scrollSpeed).clamp(10, 300).toDouble()),
                      ),
                    )
                  else
                    SizedBox(
                      width: 260,
                      child: DropdownButtonFormField<int?>(
                        key: ValueKey('speed-$part-${speed ?? 0}'),
                        initialValue: speed,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: 'Animation speed (now: ${_speedLabel(_savedSpeed)})', isDense: true, border: const OutlineInputBorder()),
                        items: [
                          if (!isAds) const DropdownMenuItem<int?>(value: null, child: Text('Default speed')),
                          for (var s = 1; s <= 10; s++) DropdownMenuItem<int?>(value: s, child: Text(_speedLabel(s))),
                        ],
                        onChanged: (v) => setState(() {
                          speed = v;
                          replay++;
                        }),
                      ),
                    ),
                  for (final k in colorKeys)
                    SizedBox(
                      width: 260,
                      child: ColorPickerField(
                        key: ValueKey('color-$part-$k'),
                        label: '${colorNames[k]} (now: ${_colorRecord.text(k).isEmpty ? 'as before' : _colorRecord.text(k)})',
                        value: colors[k]!,
                        onChanged: (v) => setState(() => colors[k] = v),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(key: ValueKey('save-$part'), onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save')),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Right Side Ads preview: the real ad box changing to the next ad with the chosen animation.
class _AdPreview extends StatefulWidget {
  const _AdPreview({super.key, required this.ads, required this.config});
  final List<Entry> ads;
  final AdsConfig config;
  @override
  State<_AdPreview> createState() => _AdPreviewState();
}

class _AdPreviewState extends State<_AdPreview> {
  late final AdsRotation rotation = AdsRotation(adCycle(widget.ads), 1);

  @override
  void dispose() {
    rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => rotation.visibleSlots == 0
      ? const SizedBox.shrink()
      : AdSlot(rotation: rotation, slot: 0, slots: 1, config: widget.config, onTap: (_) {});
}
