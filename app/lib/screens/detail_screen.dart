import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/share_stats.dart';
import '../l10n.dart';
import '../models/cigar.dart';
import '../state.dart';
import '../theme.dart';
import 'add_stock_screen.dart';
import 'picker_screen.dart';
import 'record_screen.dart';

/// 시가 상세: 스펙 · 노트 · 내 기록. (카페 평점은 서버 붙은 뒤)
class DetailScreen extends StatelessWidget {
  final Cigar cigar;
  const DetailScreen({super.key, required this.cigar});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final repo = st.repo;
    final myLogs = st.logs.where((l) => l.cigarId == cigar.id).toList();
    final myTags = <String, int>{};
    for (final l in myLogs) {
      for (final t in l.tags) {
        myTags[t] = (myTags[t] ?? 0) + 1;
      }
    }
    final specs = cigar.specs;
    final specLine = <String>[
      if (specs['length_in'] != null && specs['ring_gauge'] != null) '${specs['length_in']} × ${specs['ring_gauge']}',
      if (specs['factory_vitola'] != null) specs['factory_vitola']!,
      if (specs['strength'] != null) tr('강도 ${specs['strength']}', 'Strength ${specs['strength']}'),
      if (cigar.tubos) tr('튜보 有', 'Tubos'),
    ];
    final blendLine = <String>[
      if (specs['wrapper'] != null) tr('래퍼 ${specs['wrapper']}', 'Wrapper ${specs['wrapper']}'),
      if (specs['binder'] != null) tr('바인더 ${specs['binder']}', 'Binder ${specs['binder']}'),
      if (specs['filler'] != null) tr('필러 ${specs['filler']}', 'Filler ${specs['filler']}'),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(tr('시가 상세', 'Cigar details'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.paddingOf(context).bottom), // 하단 안전영역
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SubText([cigar.brand, if (cigar.cuban) tr('쿠바', 'Cuban')].join(' · ')),
                const SizedBox(height: 2),
                Text(cigar.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                if (specLine.isNotEmpty) ...[const SizedBox(height: 10), Wrap(spacing: 14, runSpacing: 4, children: [for (final s in specLine) SubText(s, size: 13)])],
                if (blendLine.isNotEmpty) ...[const SizedBox(height: 4), Wrap(spacing: 14, runSpacing: 4, children: [for (final s in blendLine) SubText(s, size: 12)])],
                if (cigar.vitolas.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SubText(
                    tr(
                      '비톨라 ${cigar.vitolas.length}종: ${cigar.vitolas.map((v) => _stripLine(v, cigar.name)).join(', ')}',
                      '${cigar.vitolas.length} vitolas: ${cigar.vitolas.map((v) => _stripLine(v, cigar.name)).join(', ')}',
                    ),
                    size: 12,
                  ),
                ],
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecordScreen(cigarId: cigar.id, cigarName: cigar.fullName))),
                      child: Text(tr('기록하기', 'Log')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: st.humidors.isEmpty
                          ? null
                          : () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => AddStockScreen(initialHumidorId: st.humidors.first.id, preset: PickResult(cigar: cigar))),
                              ),
                      child: Text(tr('휴미더에 추가', 'Add to humidor')),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 14),

          // 노트
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(cigar.official.isNotEmpty ? tr('공식 노트', 'Official notes') : tr('리뷰어 노트', 'Reviewer notes'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const Spacer(),
                  if (cigar.votes.isNotEmpty) SubText(tr('굵은 글씨 = 2곳 이상 합의', 'Bold = agreed by 2+ sources'), size: 11),
                ]),
                const SizedBox(height: 10),
                if (!cigar.hasNotes)
                  SubText(tr('아직 노트 자료가 없어요. 기록을 남기면 내 노트가 여기 쌓여요.', 'No notes yet. Your own notes will build up here as you log.'), size: 13)
                else ...[
                  if (cigar.official.isNotEmpty) ...[
                    Wrap(spacing: 8, runSpacing: 8, children: [for (final t in cigar.official) _Tag(repo.tagName(t), bold: cigar.votes.containsKey(t))]),
                  ],
                  if (cigar.review.isNotEmpty) ...[
                    if (cigar.official.isNotEmpty) ...[const SizedBox(height: 12), SubText(tr('리뷰어 노트', 'Reviewer notes'), size: 12), const SizedBox(height: 6)],
                    Wrap(spacing: 8, runSpacing: 8, children: [for (final t in cigar.review.where((t) => !cigar.official.contains(t))) _Tag(repo.tagName(t), bold: cigar.votes.containsKey(t))]),
                  ],
                ],
                if (cigar.dojoScore != null) ...[
                  const SizedBox(height: 12),
                  SubText(tr('Cigar Dojo 평점 ${cigar.dojoScore}', 'Cigar Dojo rating ${cigar.dojoScore}'), size: 12),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 14),

          // 카페 평점 (익명 공유 기록 집계)
          _CafeCard(cigarId: cigar.id),
          const SizedBox(height: 14),

          // 내 기록
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  myLogs.isEmpty
                      ? tr('내 기록 없음', 'No logs yet')
                      : tr(
                          '내 기록 ${myLogs.length}회 · 평균 ${fmtScore(((myLogs.map((l) => l.score).reduce((a, b) => a + b) / myLogs.length) * 2).round() / 2)}',
                          'My logs ${myLogs.length} · avg ${fmtScore(((myLogs.map((l) => l.score).reduce((a, b) => a + b) / myLogs.length) * 2).round() / 2)}',
                        ),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                if (myLogs.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SubText(myLogs.map((l) => '${fmtShort(l.date)}${l.place != null ? ' ${l.place}' : ''} ${fmtScore(l.score)}').join(' · '), size: 13),
                  if (myTags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    SubText(
                      tr(
                        '내가 체크한 노트: ${(myTags.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => repo.tagName(e.key)).join(' · ')}',
                        'Notes I picked: ${(myTags.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => repo.tagName(e.key)).join(' · ')}',
                      ),
                    ),
                  ],
                ],
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SubText(tr('노트 출처: 제조사 공식 설명 · Cigar Dojo · Cigar Journal · cigarworld', 'Note sources: manufacturer descriptions · Cigar Dojo · Cigar Journal · cigarworld'), size: 11),
          ),
        ],
      ),
    );
  }

  String _stripLine(String vitola, String lineName) {
    final l = lineName.toLowerCase();
    var v = vitola;
    if (v.toLowerCase().startsWith(l)) v = v.substring(l.length).trim();
    return v.isEmpty ? vitola : v;
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final bool bold;
  const _Tag(this.text, {this.bold = false});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
      );
}

class _CafeCard extends StatefulWidget {
  final String cigarId;
  const _CafeCard({required this.cigarId});
  @override
  State<_CafeCard> createState() => _CafeCardState();
}

class _CafeCardState extends State<_CafeCard> {
  late final Future<CafeStats?> _f = ShareStats.instance.fetch(widget.cigarId);

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: FutureBuilder<CafeStats?>(
          future: _f,
          builder: (_, snap) {
            final s = snap.data;
            Widget body;
            if (snap.connectionState != ConnectionState.done) {
              body = SubText(tr('불러오는 중…', 'Loading…'), size: 12);
            } else if (s == null) {
              body = SubText(tr('지금은 서버에 연결되지 않아 커뮤니티 평점을 못 불러왔어요.', 'Could not load the community rating. Check your connection.'), size: 12);
            } else if (s.logs == 0) {
              body = SubText(tr('아직 이 시가를 기록한 커뮤니티 회원이 없어요. 첫 기록을 남겨보세요.', 'Nobody in the community has logged this cigar yet. Be the first.'), size: 12);
            } else {
              final tags = s.topTags(6);
              body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(s.avg.toStringAsFixed(1), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: C.accent, height: 1)),
                  const SizedBox(width: 6),
                  Padding(padding: const EdgeInsets.only(bottom: 3), child: SubText(tr('점 · ${s.people}명 · ${s.logs}회', 'pts · ${s.people} people · ${s.logs} logs'), size: 12)),
                ]),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SubText(tr('많이 느낀 노트', 'Common notes'), size: 11),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final t in tags) NoteChip(label: '${repo.tagName(t)} ${s.tagCount[t]}', small: true)]),
                ],
              ]);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('커뮤니티 평점', 'Community rating'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              body,
            ]);
          },
        ),
      ),
    );
  }
}
