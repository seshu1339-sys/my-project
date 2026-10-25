import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/usage.dart';

/// Counts what customers search for (search) and what finds nothing (search_no_result: the items or shops to add), once they stop
/// typing for a moment, once per search. Shows nothing.
class SearchUsageReporter extends StatefulWidget {
  const SearchUsageReporter({super.key, required this.query, required this.results, this.town = '', this.delay = const Duration(milliseconds: 1500)});
  final String query, town;
  final int results;
  final Duration delay;
  @override
  State<SearchUsageReporter> createState() => _SearchUsageReporterState();
}

class _SearchUsageReporterState extends State<SearchUsageReporter> {
  Timer? _timer;
  String _last = '';

  static String _normal(String q) => q.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(SearchUsageReporter old) {
    super.didUpdateWidget(old);
    if (_normal(old.query) != _normal(widget.query) || old.results != widget.results) _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(widget.delay, () {
      final q = _normal(widget.query);
      if (q.length < 2 || q == _last) return;
      _last = q;
      Usage.track('search', key: q, label: q, town: widget.town);
      if (widget.results == 0) Usage.track('search_no_result', key: q, label: q, town: widget.town);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
