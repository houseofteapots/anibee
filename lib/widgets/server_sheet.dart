import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reicon_flutter/reicon_flutter.dart';

import '../models.dart';
import '../settings_store.dart';
import '../widgets/reicon_icon.dart';

/// "Server for this episode" bottom sheet — Anilili style
/// (ref anilili-server-sheet-reference.jpg).
///
/// Title + "Finding sources... N so far" status + fast-servers hint +
/// All / Sub / Dub filter pills + "Checking servers for languages..."
/// status + language pills + server cards in a grid (lightning icon,
/// name, download icon, checkmark when selected, SUB/DUB pill at the
/// bottom; selected card = accent-filled) + bottom row ("Retry {server}
/// servers" + "Close").
///
/// M1.1: the server list comes from the store's sources; the SUB/DUB
/// and language filters work over mock per-server language data. Real
/// on-device resolving arrives with milestone 2.
Future<({String server, String subDub})?> showServerSheet({
  required BuildContext context,
  required SettingsStore store,
  required String currentServer,
  required String subDub,
}) {
  return showModalBottomSheet<({String server, String subDub})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF17171F),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext context) {
      return _ServerSheet(
        store: store,
        currentServer: currentServer,
        subDub: subDub,
      );
    },
  );
}

/// Mock M1.1 language availability per server (real data in M2).
const Map<String, List<String>> kServerLanguages = <String, List<String>>{
  'Miruro': <String>['English'],
  'AniKoto': <String>['English', 'Japanese'],
  'AllAnime': <String>['English'],
  'AnimeKai': <String>['English', 'French'],
  'ReAnime': <String>['English', 'German'],
  'AniZone': <String>['English', 'Spanish'],
};

const List<String> kSheetLanguages = <String>[
  'Any',
  'Arabic',
  'English',
  'French',
  'German',
  'Hindi',
  'Italian',
  'Japanese',
  'Portuguese',
  'Russian',
  'Spanish',
];

class _ServerSheet extends StatefulWidget {
  const _ServerSheet({
    required this.store,
    required this.currentServer,
    required this.subDub,
  });

  final SettingsStore store;
  final String currentServer;
  final String subDub;

  @override
  State<_ServerSheet> createState() => _ServerSheetState();
}

class _ServerSheetState extends State<_ServerSheet> {
  late String _filter; // All / Sub / Dub
  String _language = 'Any';
  late String _selectedServer;
  bool _checking = true;
  Timer? _checkTimer;

  @override
  void initState() {
    super.initState();
    _filter = widget.subDub == 'Dub' ? 'Dub' : 'Sub';
    _selectedServer = widget.currentServer;
    _runCheck();
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }

  void _runCheck() {
    _checkTimer?.cancel();
    setState(() => _checking = true);
    _checkTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _checking = false);
    });
  }

  List<({String server, String variant})> get _cards {
    final List<({String server, String variant})> out =
        <({String server, String variant})>[];
    final List<String> variants =
        _filter == 'All' ? <String>['Sub', 'Dub'] : <String>[_filter];
    for (final ProviderSource source in widget.store.sources) {
      if (!source.enabled) continue;
      final List<String> langs =
          kServerLanguages[source.name] ?? const <String>['English'];
      if (_language != 'Any' && !langs.contains(_language)) continue;
      for (final String variant in variants) {
        out.add((server: source.name, variant: variant));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    final List<({String server, String variant})> cards = _cards;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3A48),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Server for this episode',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: <Widget>[
                  Icon(Icons.check_rounded, color: accent, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Finding sources... ${cards.length} so far',
                    style: TextStyle(
                      color: accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: <Widget>[
                  ReiconIcon(
                    Reicon.outline.bolt,
                    size: 16,
                    color: accent,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Fast servers usually start quickest',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // All / Sub / Dub filter pills.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: <Widget>[
                  for (final String f in <String>['All', 'Sub', 'Dub'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Pill(
                        label: f,
                        selected: _filter == f,
                        accent: accent,
                        onTap: () => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: <Widget>[
                  if (_checking)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    )
                  else
                    Icon(Icons.check_rounded, color: accent, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    _checking
                        ? 'Checking servers for languages...'
                        : 'Servers checked',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Language pills (horizontal scroll).
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: kSheetLanguages.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (BuildContext context, int index) {
                  final String lang = kSheetLanguages[index];
                  return _Pill(
                    label: lang,
                    selected: _language == lang,
                    accent: accent,
                    onTap: () => setState(() => _language = lang),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            // Server cards grid.
            Expanded(
              child: cards.isEmpty
                  ? const Center(
                      child: Text(
                        'No servers for this language yet',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.1,
                      ),
                      itemCount: cards.length,
                      itemBuilder: (BuildContext context, int index) {
                        final ({String server, String variant}) card =
                            cards[index];
                        final bool isSelected =
                            card.server == _selectedServer &&
                                ((_filter == 'All' &&
                                        card.variant == widget.subDub) ||
                                    _filter == card.variant);
                        return _ServerCard(
                          server: card.server,
                          variant: card.variant,
                          selected: isSelected,
                          accent: accent,
                          onTap: () => Navigator.of(context).pop(
                            (server: card.server, subDub: card.variant),
                          ),
                        );
                      },
                    ),
            ),
            // Bottom row: Retry + Close.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  TextButton(
                    onPressed: _runCheck,
                    child: Text(
                      'Retry ${widget.currentServer} servers',
                      style: TextStyle(
                        color: accent,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? accent : const Color(0xFF23232F),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.server,
    required this.variant,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String server;
  final String variant;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color iconColor = selected ? Colors.white : accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          color: selected ? accent : const Color(0xFF23232F),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                ReiconIcon(Reicon.outline.bolt, size: 16, color: iconColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    server,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ReiconIcon(
                  Reicon.outline.download,
                  size: 16,
                  color: selected
                      ? Colors.white70
                      : Colors.white54,
                ),
                if (selected) ...<Widget>[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ],
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.22)
                    : Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                variant.toUpperCase(),
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
