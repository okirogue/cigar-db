import 'package:flutter/material.dart';
import 'package:provider/provider.dart';


import '../state.dart';
import '../theme.dart';
import 'detail_screen.dart';
import 'taste_map.dart';

/// 홈: 브랜드 헤더 + 내 업적(도감·미각). 횟수·연속 같은 건 없음.
class BadgesScreen extends StatefulWidget {
  const BadgesScreen({super.key});
  @override
  State<BadgesScreen> createState() => _BadgesScreenState();
}

class _BadgesScreenState extends State<BadgesScreen> {
  static const _grades = [('입문', 0.0), ('애호가', 0.05), ('탐험가', 0.15), ('마스터', 0.40)];
  static const _tasteBadges = [(10, '노트 입문'), (19, '구분 좀 함'), (25, '맛잘알'), (32, '시가 소믈리에')];

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final repo = st.repo;
    final smoked = st.smokedIds.where((id) => repo.byId(id) != null).toSet();
    final smokedCigars = smoked.map((id) => repo.byId(id)!).toList();

    // 관심 범위 = 내가 피워본 브랜드들의 전체 라인업
    final myBrands = smokedCigars.map((c) => c.brand).toSet();
    final brandCounts = repo.brandLineCounts();
    final scopeTotal = myBrands.fold<int>(0, (a, b) => a + (brandCounts[b] ?? 0));
    final ratio = scopeTotal == 0 ? 0.0 : smoked.length / scopeTotal;
    var grade = _grades.first.$1;
    for (final g in _grades) {
      if (ratio >= g.$2 && smoked.isNotEmpty) grade = g.$1;
    }

    final cubanCount = smokedCigars.where((c) => c.cuban).length;
    final wrappers = smokedCigars.map((c) => c.specs['wrapper']).whereType<String>().map(_wrapperKey).toSet();
    final brandProgress = [
      for (final b in myBrands) (b, smokedCigars.where((c) => c.brand == b).length, brandCounts[b] ?? 0),
    ]..sort((a, b) => (b.$2 / (b.$3 == 0 ? 1 : b.$3)).compareTo(a.$2 / (a.$3 == 0 ? 1 : a.$3)));

    final marks = <(String, bool)>[
      ('첫 쿠반', cubanCount > 0),
      ('첫 논쿠반', smokedCigars.any((c) => !c.cuban)),
      ('첫 피구라도', st.logs.any((l) => _isFigurado(l.vitola ?? ''))),
      ('쿠반 5라인', cubanCount >= 5),
      ('브랜드 5곳', myBrands.length >= 5),
      ('래퍼 3종', wrappers.length >= 3),
      for (final b in brandProgress)
        if (b.$3 >= 3 && b.$2 >= b.$3) ('${b.$1} 완주', true),
    ];

    final tasted = st.tastedTags.where((t) => repo.tag(t) != null).toSet();
    final tasteRatio = repo.tagCount == 0 ? 0.0 : tasted.length / repo.tagCount;
    final nextTaste = _tasteBadges.where((b) => tasted.length < b.$1).firstOrNull;
    final gotTaste = _tasteBadges.where((b) => tasted.length >= b.$1).map((b) => b.$2).toList();

    return Scaffold(
      body: SafeArea(
        child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          // 브랜드 헤더
          Padding(
            padding: const EdgeInsets.only(bottom: 18, top: 4),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset('assets/brand/play_icon_512.png', width: 44, height: 44),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('MyHumidor', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: C.text, fontFamily: 'serif')),
                const SubText('내 휴미더 · 시가 노트', size: 12),
              ]),
              const Spacer(),
              if (st.logs.isNotEmpty) SubText('${st.logs.length}회 · 평균 ${st.avgScore.round()}점', size: 13),
            ]),
          ),
          // 도감 등급
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: C.text, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('도감 등급', style: TextStyle(fontSize: 12, color: Colors.white70)),
              Text(grade, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: C.bg)),
              const SizedBox(height: 4),
              Text(
                smoked.isEmpty ? '첫 기록을 남기면 도감이 열려요' : '접한 브랜드 ${myBrands.length}곳 라인업 $scopeTotal 중 ${smoked.length} 경험 · ${(ratio * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: ratio.clamp(0, 1), minHeight: 8, backgroundColor: Colors.white12, color: C.gold),
              ),
              const SizedBox(height: 6),
              const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('입문', style: TextStyle(fontSize: 11, color: Colors.white54)),
                Text('애호가 5%', style: TextStyle(fontSize: 11, color: Colors.white54)),
                Text('탐험가 15%', style: TextStyle(fontSize: 11, color: Colors.white54)),
                Text('마스터 40%', style: TextStyle(fontSize: 11, color: Colors.white54)),
              ]),
            ]),
          ),
          const SizedBox(height: 14),

          // 도감
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('도감', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 10),
                Row(children: [
                  _Stat(n: smoked.length, label: '라인', sub: '쿠반 $cubanCount · 논쿠반 ${smoked.length - cubanCount}'),
                  const SizedBox(width: 10),
                  _Stat(n: wrappers.length, label: '래퍼', sub: wrappers.isEmpty ? '-' : wrappers.take(4).join('·')),
                  const SizedBox(width: 10),
                  _Stat(n: myBrands.length, label: '브랜드', sub: brandProgress.isEmpty ? '-' : brandProgress.take(2).map((b) => '${_short(b.$1)} ${b.$2}/${b.$3}').join(' · ')),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final m in marks)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: m.$2 ? C.chip : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: m.$2 ? null : Border.all(color: C.line),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (m.$2) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.star, size: 14, color: C.accent)),
                        Text(m.$1, style: TextStyle(fontSize: 12, color: m.$2 ? C.text : C.hint)),
                      ]),
                    ),
                ]),
                if (brandProgress.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const SubText('브랜드별 진행', size: 12),
                  const SizedBox(height: 6),
                  for (final b in brandProgress.take(8))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        SizedBox(width: 120, child: Text(b.$1, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(value: b.$3 == 0 ? 0 : (b.$2 / b.$3).clamp(0, 1), minHeight: 8, backgroundColor: C.chip, color: C.accent),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(width: 44, child: Text('${b.$2}/${b.$3}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: C.sub))),
                      ]),
                    ),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 14),

          // 미각
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('미각', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const Spacer(),
                  SubText('${repo.tagCount}개 노트 중 ${tasted.length}개 구분'),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: tasteRatio.clamp(0, 1), minHeight: 8, backgroundColor: C.chip, color: C.accent),
                ),
                const SizedBox(height: 12),
                for (final g in repo.tagGroups) ...[
                  SubText(g.ko, size: 11),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final t in g.tags) NoteChip(label: t.ko, small: true, selected: tasted.contains(t.id), dashed: !tasted.contains(t.id)),
                  ]),
                  const SizedBox(height: 8),
                ],
                if (gotTaste.isNotEmpty) ...[
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final b in gotTaste)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(8)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.star, size: 14, color: C.accent),
                          const SizedBox(width: 6),
                          Text(b, style: const TextStyle(fontSize: 12)),
                        ]),
                      ),
                  ]),
                  const SizedBox(height: 8),
                ],
                if (nextTaste != null) SubText('다음 뱃지 "${nextTaste.$2}" — ${nextTaste.$1}개 구분하면 획득', size: 12),
              ]),
            ),
          ),
          // 취향 지도 (도감·미각 아래)
          const SizedBox(height: 14),
          const TasteMap(),
          // 추천 (맨 아래)
          const SizedBox(height: 14),
          if (st.profile != null && st.profile!.ready && st.recos.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('나와 잘 맞을 시가', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 4),
                  SubText(
                    st.topRatedNames.isEmpty
                        ? '내가 자주 체크한 노트(${st.profile!.topTags(3).map(repo.tagKo).join('·')})와 비슷한 시가예요'
                        : '점수 높게 준 ${st.topRatedNames.join(', ')} 와 비슷해요',
                    size: 12,
                  ),
                  const SizedBox(height: 12),
                  for (final r in st.recos)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(cigar: r.cigar))),
                        child: Row(children: [
                          const CigarThumb(size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(r.cigar.fullName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                              SubText(r.reason, size: 11),
                            ]),
                          ),
                          const Icon(Icons.chevron_right, size: 18, color: C.hint),
                        ]),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 14),
          ] else if (st.logs.isNotEmpty && st.logs.length < 5) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  const Icon(Icons.auto_awesome_outlined, color: C.accent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: SubText('기록 ${5 - st.logs.length}개만 더 남기면 취향 기반 추천이 열려요', size: 13)),
                ]),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
      ),
    );
  }

  static bool _isFigurado(String v) {
    final s = v.toLowerCase();
    return ['figurado', 'torpedo', 'belicoso', 'perfecto', 'piramide', 'pyramid', 'salomon', 'campana'].any(s.contains);
  }

  static String _wrapperKey(String w) {
    final s = w.toLowerCase();
    for (final k in ['connecticut', 'habano', 'maduro', 'sumatra', 'corojo', 'criollo', 'cameroon', 'oscuro', 'san andres', 'candela', 'broadleaf']) {
      if (s.contains(k)) return _cap(k);
    }
    return _cap(s.split(' ').first);
  }

  static String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
  static String _short(String s) => s.length > 10 ? '${s.substring(0, 9)}…' : s;
}

class _Stat extends StatelessWidget {
  final int n;
  final String label;
  final String sub;
  const _Stat({required this.n, required this.label, required this.sub});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(border: Border.all(color: C.lineSoft), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text('$n', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: C.accent)),
            SubText(label, size: 11),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(fontSize: 10, color: C.hint), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
      );
}
