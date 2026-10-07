import 'package:flutter/material.dart';
import 'package:provider/provider.dart';


import '../l10n.dart';
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
  static List<(String, double)> get _grades => [
        (tr('입문', 'Beginner'), 0.0),
        (tr('애호가', 'Enthusiast'), 0.05),
        (tr('탐험가', 'Explorer'), 0.15),
        (tr('마스터', 'Master'), 0.40),
      ];
  static List<(int, String)> get _tasteBadges => [
        (10, tr('노트 입문', 'Note Novice')),
        (19, tr('구분 좀 함', 'Getting There')),
        (25, tr('맛잘알', 'Palate Pro')),
        (32, tr('시가 소믈리에', 'Cigar Sommelier')),
      ];

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
      (tr('첫 쿠반', 'First Cuban'), cubanCount > 0),
      (tr('첫 논쿠반', 'First Non-Cuban'), smokedCigars.any((c) => !c.cuban)),
      (tr('첫 피구라도', 'First Figurado'), st.logs.any((l) => _isFigurado(l.vitola ?? ''))),
      (tr('쿠반 5라인', '5 Cuban lines'), cubanCount >= 5),
      (tr('브랜드 5곳', '5 brands'), myBrands.length >= 5),
      (tr('래퍼 3종', '3 wrappers'), wrappers.length >= 3),
      for (final b in brandProgress)
        if (b.$3 >= 3 && b.$2 >= b.$3) (tr('${b.$1} 완주', '${b.$1} complete'), true),
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
                SubText(tr('내 휴미더 · 시가 노트', 'My humidor · cigar notes'), size: 12),
              ]),
              const Spacer(),
              if (st.logs.isNotEmpty) SubText(tr('${st.logs.length}회 · 평균 ${st.avgScore.round()}점', '${st.logs.length} smoked · avg ${st.avgScore.round()}'), size: 13),
              const SizedBox(width: 8),
              const _LangToggle(),
            ]),
          ),
          // 도감 등급
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: C.text, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('도감 등급', 'Collection rank'), style: const TextStyle(fontSize: 12, color: Colors.white70)),
              Text(grade, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: C.bg)),
              const SizedBox(height: 4),
              Text(
                smoked.isEmpty
                    ? tr('첫 기록을 남기면 도감이 열려요', 'Log your first cigar to open the collection')
                    : tr('접한 브랜드 ${myBrands.length}곳 라인업 $scopeTotal 중 ${smoked.length} 경험 · ${(ratio * 100).toStringAsFixed(0)}%',
                        '${smoked.length} of $scopeTotal lines across ${myBrands.length} brands · ${(ratio * 100).toStringAsFixed(0)}%'),
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: ratio.clamp(0, 1), minHeight: 8, backgroundColor: Colors.white12, color: C.gold),
              ),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                for (var i = 0; i < _grades.length; i++)
                  Text(i == 0 ? _grades[i].$1 : '${_grades[i].$1} ${(_grades[i].$2 * 100).round()}%', style: const TextStyle(fontSize: 11, color: Colors.white54)),
              ]),
            ]),
          ),
          const SizedBox(height: 14),

          // 도감
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('도감', 'Collection'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 10),
                Row(children: [
                  _Stat(
                    n: smoked.length,
                    label: tr('라인', 'Lines'),
                    title: tr('피워본 라인', 'Lines smoked'),
                    lines: [
                      tr('쿠반 $cubanCount', 'Cuban $cubanCount'),
                      tr('논쿠반 ${smoked.length - cubanCount}', 'Non-Cuban ${smoked.length - cubanCount}'),
                    ],
                  ),
                  const SizedBox(width: 10),
                  _Stat(
                    n: wrappers.length,
                    label: tr('래퍼', 'Wrappers'),
                    title: tr('경험한 래퍼', 'Wrappers tried'),
                    lines: wrappers.isEmpty ? [tr('아직 없음', 'None yet')] : (wrappers.toList()..sort()),
                  ),
                  const SizedBox(width: 10),
                  _Stat(
                    n: myBrands.length,
                    label: tr('브랜드', 'Brands'),
                    title: tr('접한 브랜드', 'Brands tried'),
                    lines: brandProgress.isEmpty ? [tr('아직 없음', 'None yet')] : [for (final b in brandProgress) '${b.$1}  ${b.$2}/${b.$3}'],
                  ),
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
                  SubText(tr('브랜드별 진행', 'Progress by brand'), size: 12),
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
                  Text(tr('미각', 'Palate'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const Spacer(),
                  SubText(tr('${repo.tagCount}개 노트 중 ${tasted.length}개 구분', '${tasted.length} of ${repo.tagCount} notes identified')),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: tasteRatio.clamp(0, 1), minHeight: 8, backgroundColor: C.chip, color: C.accent),
                ),
                const SizedBox(height: 12),
                for (final g in repo.tagGroups) ...[
                  SubText(g.name, size: 11),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final t in g.tags) NoteChip(label: t.name, small: true, selected: tasted.contains(t.id), dashed: !tasted.contains(t.id)),
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
                if (nextTaste != null) SubText(tr('다음 뱃지 "${nextTaste.$2}" — ${nextTaste.$1}개 구분하면 획득', 'Next badge "${nextTaste.$2}" — identify ${nextTaste.$1} notes'), size: 12),
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
                  Text(tr('나와 잘 맞을 시가', 'Cigars you may like'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 4),
                  SubText(
                    st.topRatedNames.isEmpty
                        ? tr('내가 자주 체크한 노트(${st.profile!.topTags(3).map(repo.tagName).join('·')})와 비슷한 시가예요',
                            'Similar to the notes you pick most (${st.profile!.topTags(3).map(repo.tagName).join(' · ')})')
                        : tr('점수 높게 준 ${st.topRatedNames.join(', ')} 와 비슷해요', 'Similar to your top-rated ${st.topRatedNames.join(', ')}'),
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
                  Expanded(child: SubText(tr('기록 ${5 - st.logs.length}개만 더 남기면 취향 기반 추천이 열려요', 'Log ${5 - st.logs.length} more to unlock recommendations'), size: 13)),
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
}

class _Stat extends StatelessWidget {
  final int n;
  final String label;
  final String title;
  final List<String> lines;
  const _Stat({required this.n, required this.label, required this.title, required this.lines});

  void _show(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
        title: Row(children: [
          Text('$n', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: C.accent)),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(l, style: const TextStyle(fontSize: 13.5))),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('닫기', 'Close')))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _show(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            decoration: BoxDecoration(border: Border.all(color: C.lineSoft), borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Text('$n', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: C.accent)),
              SubText(label, size: 11),
            ]),
          ),
        ),
      );
}

/// 홈 우상단 언어 토글 (KO / EN)
class _LangToggle extends StatelessWidget {
  const _LangToggle();
  @override
  Widget build(BuildContext context) {
    final ko = L10n.isKo;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: L10n.toggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('KO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ko ? C.accent : C.hint)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('·', style: TextStyle(fontSize: 11, color: C.hint))),
          Text('EN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ko ? C.hint : C.accent)),
        ]),
      ),
    );
  }
}
