import 'dart:math';

import '../l10n.dart';
import '../models/cigar.dart';
import '../models/local.dart';
import 'cigar_repo.dart';

/// 추천 결과 한 건
class Reco {
  final Cigar cigar;
  final double score; // 0~1
  final List<String> sharedTags; // 겹치는 노트 (한글 변환 전 id)
  final bool smoked;
  final bool inStock; // 지금 휴미더에 있음
  final String? anchorName; // 근거가 된 "내가 좋게 준" 시가 이름
  final double? anchorScore;
  Reco(this.cigar, this.score, this.sharedTags, {this.smoked = false, this.inStock = false, this.anchorName, this.anchorScore});

  /// 추천 근거 문구 — 그릴 때 현재 언어로 생성 (언어 토글 즉시 반영)
  String reason(CigarRepo repo) {
    final strength = cigar.specs['strength'];
    final parts = <String>[
      if (anchorName != null)
        tr('${fmt(anchorScore)}점 준 $anchorName 와 비슷', 'Like $anchorName (${fmt(anchorScore)})'),
      sharedTags.take(3).map(repo.tagName).join('·'),
      if (anchorName == null && strength != null) tr('강도 $strength', 'Strength ${_capFirst(strength.toString())}'),
      if (cigar.cuban) tr('쿠바', 'Cuban'),
      if (smoked && !inStock) tr('피워봄', 'Smoked'),
    ];
    return parts.where((p) => p.isNotEmpty).join(' · ');
  }

  static String fmt(double? v) => v == null ? '' : (v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1));
}

/// 내가 좋게 준 시가 하나 (추천 근거용)
class _Anchor {
  final String cigarId, name;
  final double score;
  final Set<String> tags;
  _Anchor(this.cigarId, this.name, this.score, this.tags);
}

/// 내 기록 기반 취향 프로필 → 노트 태그 가중치 벡터
class TasteProfile {
  final Map<String, double> weights; // tag → 가중치 (양수 선호, 음수 비선호)
  final Map<String, double> strengthPref; // 'light'|'medium'|'full' → 선호도
  final double cubanRatio; // 높은 점수 중 쿠반 비율
  final int logCount;
  final List<_Anchor> _anchors; // 8점 이상 준 시가들 (근거 표시용)

  TasteProfile(this.weights, this.strengthPref, this.cubanRatio, this.logCount, this._anchors);

  bool get ready => logCount >= 5 && weights.isNotEmpty;

  /// 상위 선호 노트 (표시용)
  List<String> topTags([int n = 5]) {
    final e = weights.entries.where((x) => x.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    return e.take(n).map((x) => x.key).toList();
  }

  static TasteProfile build(List<SmokeLog> logs, CigarRepo repo) {
    final w = <String, double>{};
    final sp = <String, double>{'light': 0, 'medium': 0, 'full': 0};
    var cubanHi = 0, hi = 0;
    final now = DateTime.now();
    // 최근 기록 가중 (기록이 10건 이상일 때만): 30일 이내 1.0 → 90일 이후 0.5
    final useRecency = logs.length >= 10;
    final anchorTags = <String, Set<String>>{}, anchorScore = <String, double>{}, anchorName = <String, String>{}, anchorCnt = <String, int>{};
    for (final l in logs) {
      // 점수 → 가중치: 7.5를 중립으로, 8.5면 +1, 6.5면 -1. 싫은 쪽은 1.5배로 더 세게 밀어낸다.
      var k = (l.score - 7.5).clamp(-2.0, 2.5);
      if (k < 0) k *= 1.5;
      if (k == 0) continue;
      if (useRecency) {
        final d = DateTime.tryParse(l.date);
        if (d != null) {
          final days = now.difference(d).inDays;
          final rw = days <= 30 ? 1.0 : days >= 90 ? 0.5 : 1.0 - (days - 30) / 60 * 0.5;
          k *= rw;
        }
      }
      final c = repo.byId(l.cigarId);
      // 내가 체크한 노트가 있으면 그것, 없으면 DB 노트로 대체(절반 가중)
      final tags = l.tags.isNotEmpty ? l.tags : (c?.allTags ?? const <String>[]);
      final f = l.tags.isNotEmpty ? 1.0 : 0.5;
      for (final t in tags) {
        w[t] = (w[t] ?? 0) + k * f;
      }
      if (c != null) {
        final s = strengthBucket(c.specs['strength'] ?? c.specs['strength_felt']);
        if (s != null) sp[s] = (sp[s] ?? 0) + k;
        if (k > 0) {
          hi++;
          if (c.cuban) cubanHi++;
        }
      }
      if (l.score >= 8) {
        anchorTags.putIfAbsent(l.cigarId, () => <String>{}).addAll(tags);
        anchorScore[l.cigarId] = (anchorScore[l.cigarId] ?? 0) + l.score;
        anchorCnt[l.cigarId] = (anchorCnt[l.cigarId] ?? 0) + 1;
        anchorName[l.cigarId] = l.cigarName;
      }
    }
    final anchors = [
      for (final id in anchorTags.keys) _Anchor(id, anchorName[id]!, anchorScore[id]! / anchorCnt[id]!, anchorTags[id]!),
    ];
    return TasteProfile(w, sp, hi == 0 ? 0.5 : cubanHi / hi, logs.length, anchors);
  }
}

/// 강도 문자열 → 3단계. 지도(taste_map)와 같은 기준: mild-medium 은 light 쪽.
String? strengthBucket(String? s) {
  if (s == null) return null;
  final x = s.toLowerCase();
  if (x.contains('full')) return x.contains('medium') ? 'medium' : 'full';
  if (x.contains('medium')) return (x.contains('mild') || x.contains('light')) ? 'light' : 'medium';
  if (x.contains('mild') || x.contains('light')) return 'light';
  return null;
}

class Recommender {
  final CigarRepo repo;
  Recommender(this.repo);

  /// 내 취향 기반 추천 (홈). [stockIds] 가 있으면 휴미더에 있는 시가는 피워봤어도 "지금 피울 것" 후보로 넣는다.
  List<Reco> forMe(TasteProfile p, Set<String> smokedIds, {int limit = 10, Set<String> stockIds = const {}}) {
    if (!p.ready) return const [];
    final pw = p.weights;
    final pnorm = sqrt(pw.values.fold<double>(0, (a, b) => a + b * b));
    if (pnorm == 0) return const [];
    final total = p.strengthPref.values.fold<double>(0, (a, b) => a + b.abs());
    final out = <Reco>[];
    for (final c in repo.all) {
      if (!c.hasNotes) continue;
      final inStock = stockIds.contains(c.id);
      if (smokedIds.contains(c.id) && !inStock) continue;
      final tags = c.allTags;
      // 코사인 유사도: 시가는 각 태그 1 (합의 태그 1.5)
      var dot = 0.0, cn = 0.0;
      final shared = <String>[];
      for (final t in tags) {
        final tv = c.votes.containsKey(t) ? 1.5 : 1.0;
        cn += tv * tv;
        final v = pw[t];
        if (v != null) {
          dot += v * tv;
          if (v > 0) shared.add(t);
        }
      }
      if (cn == 0 || shared.isEmpty) continue;
      var score = dot / (pnorm * sqrt(cn));
      // 태그가 적은 시가는 코사인이 과대평가되므로 4개 미만이면 n/4 로 깎는다
      if (tags.length < 4) score *= tags.length / 4;
      // 강도 보정 (±10%)
      final sb = strengthBucket(c.specs['strength'] ?? c.specs['strength_felt']);
      if (sb != null && total > 0) score += 0.1 * (p.strengthPref[sb]! / total);
      // 쿠반 성향 보정 (±5%)
      score += 0.05 * ((c.cuban ? 1 : 0) - 0.5) * (p.cubanRatio - 0.5) * 2;
      if (score <= 0) continue;
      shared.sort((a, b) => (pw[b] ?? 0).compareTo(pw[a] ?? 0));
      // 근거 시가: 내가 8점 이상 준 것 중 태그가 가장 많이 겹치는 것 (자기 자신 제외)
      _Anchor? best;
      var bj = 0.0;
      final ct = tags.toSet();
      for (final a in p._anchors) {
        if (a.cigarId == c.id || a.tags.isEmpty) continue;
        final inter = a.tags.intersection(ct).length;
        if (inter < 2) continue;
        final j = inter / a.tags.union(ct).length;
        if (j > bj) {
          bj = j;
          best = a;
        }
      }
      out.add(Reco(c, score, shared, smoked: smokedIds.contains(c.id), inStock: inStock, anchorName: best?.name, anchorScore: best?.score));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return _diversify(out, limit);
  }

  /// 특정 시가와 비슷한 시가 (상세)
  List<Reco> similarTo(Cigar base, Set<String> smokedIds, {int limit = 6}) {
    final bt = base.allTags.toSet();
    if (bt.isEmpty) return const [];
    final bs = strengthBucket(base.specs['strength'] ?? base.specs['strength_felt']);
    final out = <Reco>[];
    for (final c in repo.all) {
      if (c.id == base.id || !c.hasNotes) continue;
      final ct = c.allTags.toSet();
      final inter = bt.intersection(ct);
      if (inter.length < 2) continue;
      // 자카드 + 강도 일치 보너스
      var score = inter.length / bt.union(ct).length;
      final cs = strengthBucket(c.specs['strength'] ?? c.specs['strength_felt']);
      if (bs != null && cs == bs) score += 0.1;
      if (c.cuban == base.cuban) score += 0.03;
      final shared = inter.toList()..sort();
      out.add(Reco(c, score, shared, smoked: smokedIds.contains(c.id)));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return _diversify(out, limit);
  }

  /// 같은 브랜드가 줄줄이 나오지 않게 브랜드당 최대 2개
  List<Reco> _diversify(List<Reco> sorted, int limit) {
    final per = <String, int>{};
    final out = <Reco>[];
    for (final r in sorted) {
      final n = per[r.cigar.brand] ?? 0;
      if (n >= 2) continue;
      per[r.cigar.brand] = n + 1;
      out.add(r);
      if (out.length >= limit) break;
    }
    return out;
  }
}

String _capFirst(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
