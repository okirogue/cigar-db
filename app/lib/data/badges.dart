import 'package:shared_preferences/shared_preferences.dart';

import '../l10n.dart';
import '../state.dart';

/// 도감·미각 뱃지 정의와 달성 계산.
/// 원칙: 횟수·빈도·연속일 같은 "많이 피우기" 업적은 없음 — 종류(라인·브랜드·래퍼·사이즈·강도·숙성)와 미각만.
class AppBadge {
  final String id;
  final String name;
  final String desc; // 달성 조건 설명
  final String group; // 묶음 이름 (화면 표시용)
  final int cur; // 현재 진행
  final int target; // 목표
  const AppBadge({required this.id, required this.name, required this.desc, required this.group, required this.cur, required this.target});

  bool get earned => cur >= target;
  double get progress => target == 0 ? 0 : (cur / target).clamp(0, 1);
  /// 1단계짜리(첫 경험 등)는 진행 막대 대신 체크로만
  bool get isStep => target <= 1;
}

class BadgeGroup {
  final String name;
  final List<AppBadge> badges;
  const BadgeGroup(this.name, this.badges);
  int get earned => badges.where((b) => b.earned).length;
}

class Badges {
  Badges._();

  static const _earnedKey = 'badges_earned'; // 마지막으로 본 획득 뱃지 id 목록 (새 뱃지 축하용)

  /// 전체 뱃지 (묶음별, 정의 순서 유지)
  static List<BadgeGroup> compute(AppState st) {
    final repo = st.repo;
    final logs = st.logs;
    final smokedIds = st.smokedIds.where((id) => repo.byId(id) != null).toSet();
    final cigars = smokedIds.map((id) => repo.byId(id)!).toList();
    final brands = cigars.map((c) => c.brand).toSet();
    final cuban = cigars.where((c) => c.cuban).length;
    final nonCuban = cigars.length - cuban;
    final wrappers = cigars.map((c) => c.specs['wrapper']).whereType<String>().map(wrapperKey).toSet();
    final strengths = cigars.map((c) => c.specs['strength']).whereType<String>().map(strengthKey).whereType<String>().toSet();
    final sizes = logs.map((l) => sizeKey(l.vitola ?? '')).whereType<String>().toSet();
    final maxAging = logs.map((l) => l.agingDaysAtSmoke ?? 0).fold<int>(0, (a, b) => a > b ? a : b);
    final brandCounts = repo.brandLineCounts();
    final tasted = st.tastedTags.where((t) => repo.tag(t) != null).toSet();

    int b2i(bool v) => v ? 1 : 0;

    final firsts = <AppBadge>[
      AppBadge(id: 'first_cuban', name: tr('첫 쿠반', 'First Cuban'), desc: tr('쿠반 시가 1종', 'Smoke a Cuban'), group: 'firsts', cur: b2i(cuban > 0), target: 1),
      AppBadge(id: 'first_noncuban', name: tr('첫 논쿠반', 'First Non-Cuban'), desc: tr('논쿠반 시가 1종', 'Smoke a non-Cuban'), group: 'firsts', cur: b2i(nonCuban > 0), target: 1),
      AppBadge(id: 'first_figurado', name: tr('첫 피구라도', 'First Figurado'), desc: tr('토르페도·벨리코소·피라미드 등', 'Torpedo, belicoso, pyramid…'), group: 'firsts', cur: b2i(sizes.contains('figurado')), target: 1),
      AppBadge(id: 'first_lancero', name: tr('첫 란세로', 'First Lancero'), desc: tr('란세로·파나텔라 같은 가는 시가', 'Lancero or panatela'), group: 'firsts', cur: b2i(sizes.contains('lancero')), target: 1),
      AppBadge(id: 'first_churchill', name: tr('첫 처칠', 'First Churchill'), desc: tr('처칠·더블 코로나 같은 긴 시가', 'Churchill or double corona'), group: 'firsts', cur: b2i(sizes.contains('churchill')), target: 1),
      AppBadge(id: 'first_maduro', name: tr('첫 마두로', 'First Maduro'), desc: tr('마두로·오스쿠로 래퍼', 'Maduro or oscuro wrapper'), group: 'firsts', cur: b2i(wrappers.contains('Maduro') || wrappers.contains('Oscuro')), target: 1),
      AppBadge(id: 'first_full', name: tr('첫 풀바디', 'First Full-Body'), desc: tr('강도 Full 시가', 'A full-strength cigar'), group: 'firsts', cur: b2i(strengths.contains('full')), target: 1),
    ];

    final collection = <AppBadge>[
      for (final n in [10, 25, 50, 100])
        AppBadge(id: 'lines_$n', name: tr('라인 $n', '$n lines'), desc: tr('서로 다른 라인 $n종', '$n different lines'), group: 'collection', cur: cigars.length, target: n),
      for (final n in [5, 10, 20])
        AppBadge(id: 'brands_$n', name: tr('브랜드 $n곳', '$n brands'), desc: tr('브랜드 $n곳 경험', 'Cigars from $n brands'), group: 'collection', cur: brands.length, target: n),
      for (final n in [5, 10, 15])
        AppBadge(id: 'cuban_$n', name: tr('쿠반 $n라인', '$n Cuban lines'), desc: tr('쿠반 라인 $n종', '$n Cuban lines'), group: 'collection', cur: cuban, target: n),
    ];

    final variety = <AppBadge>[
      for (final n in [3, 5, 7])
        AppBadge(id: 'wrapper_$n', name: tr('래퍼 $n종', '$n wrappers'), desc: tr('래퍼 종류 $n가지', '$n wrapper types'), group: 'variety', cur: wrappers.length, target: n),
      for (final n in [3, 5, 7])
        AppBadge(id: 'size_$n', name: tr('비톨라 $n종', '$n vitolas'), desc: tr('로부스토·토로·처칠… $n가지 사이즈', 'Robusto, toro, churchill… $n sizes'), group: 'variety', cur: sizes.length, target: n),
      AppBadge(id: 'spectrum', name: tr('풀 스펙트럼', 'Full Spectrum'), desc: tr('마일드·미디엄·풀 강도 모두 경험', 'Mild, medium and full strength all tried'), group: 'variety',
          cur: [strengths.contains('mild') || strengths.contains('mild-medium'), strengths.contains('medium') || strengths.contains('medium-full'), strengths.contains('full')].where((v) => v).length, target: 3),
    ];

    final aging = <AppBadge>[
      AppBadge(id: 'aging_90', name: tr('숙성 3개월', 'Aged 3 months'), desc: tr('입고 후 90일 이상 숙성한 시가를 피움', 'Smoke a cigar rested 90+ days'), group: 'aging', cur: maxAging.clamp(0, 90), target: 90),
      AppBadge(id: 'aging_180', name: tr('숙성 반년', 'Aged 6 months'), desc: tr('180일 이상 숙성', 'Rested 180+ days'), group: 'aging', cur: maxAging.clamp(0, 180), target: 180),
      AppBadge(id: 'aging_365', name: tr('숙성 1년', 'Aged 1 year'), desc: tr('365일 이상 숙성', 'Rested 365+ days'), group: 'aging', cur: maxAging.clamp(0, 365), target: 365),
    ];

    // 브랜드 완주: 라인업 3개 이상인 브랜드를 전부 피움 (접한 브랜드만 표시)
    final complete = <AppBadge>[
      for (final b in brands.toList()..sort())
        if ((brandCounts[b] ?? 0) >= 3)
          AppBadge(
            id: 'brand_${b.toLowerCase()}',
            name: tr('$b 완주', '$b complete'),
            desc: tr('$b 라인업 전부', 'Every $b line'),
            group: 'brand',
            cur: cigars.where((c) => c.brand == b).length,
            target: brandCounts[b] ?? 0,
          ),
    ];

    final palate = <AppBadge>[
      for (final e in [(10, tr('노트 입문', 'Note Novice')), (19, tr('구분 좀 함', 'Getting There')), (25, tr('맛잘알', 'Palate Pro')), (32, tr('시가 소믈리에', 'Cigar Sommelier'))])
        AppBadge(id: 'taste_${e.$1}', name: e.$2, desc: tr('노트 ${e.$1}개 구분', 'Identify ${e.$1} notes'), group: 'palate', cur: tasted.length, target: e.$1),
      // 노트 그룹 정복: 한 그룹의 태그를 전부 느껴봄
      for (final g in repo.tagGroups)
        if (g.tags.length >= 3)
          AppBadge(
            id: 'group_${g.id}',
            name: tr('${g.name} 정복', '${g.name} master'),
            desc: tr('${g.name} 노트 전부 구분', 'Every ${g.name} note'),
            group: 'palate',
            cur: g.tags.where((t) => tasted.contains(t.id)).length,
            target: g.tags.length,
          ),
    ];

    return [
      BadgeGroup(tr('첫 경험', 'Firsts'), firsts),
      BadgeGroup(tr('수집', 'Collection'), collection),
      BadgeGroup(tr('다양성', 'Variety'), variety),
      BadgeGroup(tr('숙성', 'Aging'), aging),
      if (complete.isNotEmpty) BadgeGroup(tr('브랜드 완주', 'Brand completion'), complete),
      BadgeGroup(tr('미각', 'Palate'), palate),
    ];
  }

  static List<AppBadge> flat(List<BadgeGroup> groups) => [for (final g in groups) ...g.badges];

  /// 지난번 확인 이후 새로 딴 뱃지. 처음 호출(저장된 목록 없음)엔 축하 없이 현재 상태만 저장
  /// — 업데이트로 뱃지가 늘어났을 때 기존 사용자에게 한꺼번에 폭죽이 터지지 않게.
  static Future<List<AppBadge>> takeNew(AppState st) async {
    final p = await SharedPreferences.getInstance();
    final earned = flat(compute(st)).where((b) => b.earned).toList();
    final ids = earned.map((b) => b.id).toList();
    final seen = p.getStringList(_earnedKey);
    await p.setStringList(_earnedKey, ids);
    if (seen == null) return const [];
    final seenSet = seen.toSet();
    return earned.where((b) => !seenSet.contains(b.id)).toList();
  }

  // ---- 정규화 ----
  static String wrapperKey(String w) {
    final s = w.toLowerCase();
    for (final k in ['connecticut', 'habano', 'maduro', 'sumatra', 'corojo', 'criollo', 'cameroon', 'oscuro', 'san andres', 'candela', 'broadleaf']) {
      if (s.contains(k)) return _cap(k);
    }
    return _cap(s.split(' ').first);
  }

  /// mild / mild-medium / medium / medium-full / full
  static String? strengthKey(String v) {
    final s = v.toLowerCase();
    final mild = s.contains('mild') || s.contains('light');
    final med = s.contains('medium');
    final full = s.contains('full');
    if (mild && med) return 'mild-medium';
    if (med && full) return 'medium-full';
    if (full) return 'full';
    if (med) return 'medium';
    if (mild) return 'mild';
    return null;
  }

  /// 비톨라 이름 → 사이즈 계열 (없으면 null)
  static String? sizeKey(String v) {
    final s = v.toLowerCase();
    if (s.isEmpty) return null;
    if (['figurado', 'torpedo', 'belicoso', 'perfecto', 'piramide', 'pyramid', 'salomon', 'campana', 'diadema'].any(s.contains)) return 'figurado';
    if (['lancero', 'panatela', 'panetela', 'laguito'].any(s.contains)) return 'lancero';
    if (['churchill', 'double corona', 'prominente', 'julieta'].any(s.contains)) return 'churchill';
    if (['gordo', 'gigante', 'grande', '60', '62'].any(s.contains)) return 'gordo';
    if (['petit', 'petite', 'short', 'minuto', 'mareva', 'half corona', 'perla'].any(s.contains)) return 'petit';
    if (s.contains('robusto') || s.contains('rothschild')) return 'robusto';
    if (s.contains('toro')) return 'toro';
    if (s.contains('lonsdale') || s.contains('cervante')) return 'lonsdale';
    if (s.contains('corona')) return 'corona';
    return null;
  }

  static String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
