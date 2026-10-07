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
  Reco(this.cigar, this.score, this.sharedTags, {this.smoked = false});

  /// 추천 근거 문구 — 그릴 때 현재 언어로 생성 (언어 토글 즉시 반영)
  String reason(CigarRepo repo) {
    final strength = cigar.specs['strength'];
    final parts = <String>[
      sharedTags.take(3).map(repo.tagName).join('·'),
      if (strength != null) tr('강도 $strength', 'Strength ${_capFirst(strength.toString())}'),
      if (cigar.cuban) tr('쿠바', 'Cuban'),
      if (smoked) tr('피워봄', 'Smoked'),
    ];
    return parts.where((p) => p.isNotEmpty).join(' · ');
  }
}

/// 내 기록 기반 취향 프로필 → 노트 태그 가중치 벡터
class TasteProfile {
  final Map<String, double> weights; // tag → 가중치 (양수 선호, 음수 비선호)
  final Map<String, double> strengthPref; // 'light'|'medium'|'full' → 선호도
  final double cubanRatio; // 높은 점수 중 쿠반 비율
  final int logCount;

  TasteProfile(this.weights, this.strengthPref, this.cubanRatio, this.logCount);

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
    for (final l in logs) {
      // 점수 → 가중치: 7.5를 중립으로, 8.5면 +1, 6.5면 -1
      final k = (l.score - 7.5).clamp(-2.0, 2.5);
      if (k == 0) continue;
      final c = repo.byId(l.cigarId);
      // 내가 체크한 노트가 있으면 그것, 없으면 DB 노트로 대체(절반 가중)
      final tags = l.tags.isNotEmpty ? l.tags : (c?.allTags ?? const <String>[]);
      final f = l.tags.isNotEmpty ? 1.0 : 0.5;
      for (final t in tags) {
        w[t] = (w[t] ?? 0) + k * f;
      }
      if (c != null) {
        final s = _strengthBucket(c.specs['strength'] ?? c.specs['strength_felt']);
        if (s != null) sp[s] = (sp[s] ?? 0) + k;
        if (k > 0) {
          hi++;
          if (c.cuban) cubanHi++;
        }
      }
    }
    return TasteProfile(w, sp, hi == 0 ? 0.5 : cubanHi / hi, logs.length);
  }
}

String? _strengthBucket(String? s) {
  if (s == null) return null;
  final x = s.toLowerCase();
  if (x.contains('full')) return x.contains('medium') ? 'medium' : 'full';
  if (x.contains('medium')) return 'medium';
  if (x.contains('mild') || x.contains('light')) return 'light';
  return null;
}

class Recommender {
  final CigarRepo repo;
  Recommender(this.repo);

  /// 내 취향 기반 추천 (홈)
  List<Reco> forMe(TasteProfile p, Set<String> smokedIds, {int limit = 10}) {
    if (!p.ready) return const [];
    final pw = p.weights;
    final pnorm = sqrt(pw.values.fold<double>(0, (a, b) => a + b * b));
    if (pnorm == 0) return const [];
    final out = <Reco>[];
    for (final c in repo.all) {
      if (!c.hasNotes || smokedIds.contains(c.id)) continue;
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
      // 강도 보정 (±10%)
      final sb = _strengthBucket(c.specs['strength'] ?? c.specs['strength_felt']);
      if (sb != null) {
        final total = p.strengthPref.values.fold<double>(0, (a, b) => a + b.abs());
        if (total > 0) score += 0.1 * (p.strengthPref[sb]! / total);
      }
      // 쿠반 성향 보정 (±5%)
      score += 0.05 * ((c.cuban ? 1 : 0) - 0.5) * (p.cubanRatio - 0.5) * 2;
      if (score <= 0) continue;
      shared.sort((a, b) => (pw[b] ?? 0).compareTo(pw[a] ?? 0));
      out.add(Reco(c, score, shared));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return _diversify(out, limit);
  }

  /// 특정 시가와 비슷한 시가 (상세)
  List<Reco> similarTo(Cigar base, Set<String> smokedIds, {int limit = 6}) {
    final bt = base.allTags.toSet();
    if (bt.isEmpty) return const [];
    final bs = _strengthBucket(base.specs['strength'] ?? base.specs['strength_felt']);
    final out = <Reco>[];
    for (final c in repo.all) {
      if (c.id == base.id || !c.hasNotes) continue;
      final ct = c.allTags.toSet();
      final inter = bt.intersection(ct);
      if (inter.length < 2) continue;
      // 자카드 + 강도 일치 보너스
      var score = inter.length / bt.union(ct).length;
      final cs = _strengthBucket(c.specs['strength'] ?? c.specs['strength_felt']);
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
