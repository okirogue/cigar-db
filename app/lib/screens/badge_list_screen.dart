import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/badges.dart';
import '../l10n.dart';
import '../state.dart';
import '../theme.dart';

/// 전체 뱃지: 딴 것과 남은 것, 각각 어디까지 왔는지. 다음 목표를 미리 볼 수 있게.
class BadgeListScreen extends StatelessWidget {
  const BadgeListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final groups = Badges.compute(st);
    final all = Badges.flat(groups);
    final earned = all.where((b) => b.earned).length;
    // 다음 목표: 아직 못 딴 것 중 진행률 높은 순 3개 (1단계짜리는 뒤로)
    final next = all.where((b) => !b.earned).toList()
      ..sort((a, b) {
        if (a.isStep != b.isStep) return a.isStep ? 1 : -1;
        return b.progress.compareTo(a.progress);
      });

    return Scaffold(
      appBar: AppBar(title: Text(tr('뱃지', 'Badges'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: C.text, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('획득', 'Earned'), style: const TextStyle(fontSize: 12, color: Colors.white70)),
                Text('$earned / ${all.length}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: C.bg)),
              ]),
              const Spacer(),
              const Text('🏅', style: TextStyle(fontSize: 34)),
            ]),
          ),
          if (next.isNotEmpty) ...[
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('다음 목표', 'Up next'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 8),
                  for (final b in next.take(3)) _BadgeRow(b: b),
                ]),
              ),
            ),
          ],
          for (final g in groups) ...[
            const SizedBox(height: 14),
            Row(children: [
              Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const Spacer(),
              SubText('${g.earned}/${g.badges.length}'),
            ]),
            const SizedBox(height: 6),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(children: [for (final b in g.badges) _BadgeRow(b: b)]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BadgeRow extends StatelessWidget {
  final AppBadge b;
  const _BadgeRow({required this.b});
  @override
  Widget build(BuildContext context) {
    final on = b.earned;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? C.chip : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: on ? null : Border.all(color: C.line),
          ),
          child: Icon(on ? Icons.star : Icons.star_border, size: 18, color: on ? C.accent : C.hint),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(b.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? C.text : C.sub)),
            SubText(b.desc, size: 11),
            if (!on && !b.isStep) ...[
              const SizedBox(height: 5),
              Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(value: b.progress, minHeight: 5, backgroundColor: C.chip, color: C.accent),
                  ),
                ),
                const SizedBox(width: 8),
                SubText('${b.cur}/${b.target}', size: 11),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}
