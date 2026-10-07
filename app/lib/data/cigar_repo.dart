import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/cigar.dart';

/// assets/cigars.json · tags.json 을 메모리에 올려 두는 중앙 DB.
class CigarRepo {
  CigarRepo._();
  static final CigarRepo instance = CigarRepo._();

  List<Cigar> _cigars = [];
  Map<String, Cigar> _byId = {};
  List<TagGroup> _groups = [];
  Map<String, TagDef> _tagById = {};
  bool _loaded = false;

  bool get loaded => _loaded;
  List<Cigar> get all => _cigars;
  List<TagGroup> get tagGroups => _groups;
  int get tagCount => _tagById.length;

  Future<void> load() async {
    if (_loaded) return;
    final raw = await rootBundle.loadString('assets/cigars.json');
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    _cigars = list.map(Cigar.fromJson).toList();
    _byId = {for (final c in _cigars) c.id: c};

    final traw = await rootBundle.loadString('assets/tags.json');
    final tj = jsonDecode(traw) as Map<String, dynamic>;
    _groups = [];
    _tagById = {};
    for (final g in (tj['groups'] as List).cast<Map<String, dynamic>>()) {
      final defs = <TagDef>[];
      for (final t in (g['tags'] as List).cast<Map<String, dynamic>>()) {
        final d = TagDef(t['id'] as String, t['ko'] as String, (t['hint'] ?? '') as String, g['id'] as String, g['ko'] as String,
            en: (t['en'] ?? t['ko']) as String, hintEn: (t['hint_en'] ?? t['hint'] ?? '') as String, groupEn: (g['en'] ?? g['ko']) as String);
        defs.add(d);
        _tagById[d.id] = d;
      }
      _groups.add(TagGroup(g['id'] as String, g['ko'] as String, defs, en: (g['en'] ?? g['ko']) as String));
    }
    _loaded = true;
  }

  Cigar? byId(String id) => _byId[id];

  /// 사용자가 직접 추가한 시가 (앱 시작 시 로컬 DB에서, 추가 시 즉시)
  List<Cigar> get customs => _cigars.where((c) => c.isCustom).toList();

  void addCustom(Cigar c) {
    if (_byId.containsKey(c.id)) return;
    _cigars.add(c);
    _byId[c.id] = c;
  }

  /// 현재 언어의 노트 이름
  String tagName(String id) => _tagById[id]?.name ?? id;
  TagDef? tag(String id) => _tagById[id];

  /// 단어 단위 AND 검색. 결과는 브랜드 일치 > 이름 일치 순.
  List<Cigar> search(String query, {int limit = 40}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final scored = <(int, Cigar)>[];
    for (final c in _cigars) {
      var ok = true;
      for (final w in words) {
        if (!c.searchText.contains(w)) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      var score = 0;
      final full = c.fullName.toLowerCase();
      if (full.startsWith(q)) score += 100;
      if (c.brand.toLowerCase().startsWith(words.first)) score += 20;
      if (c.hasNotes) score += 5;
      scored.add((score, c));
    }
    scored.sort((a, b) {
      final d = b.$1.compareTo(a.$1);
      return d != 0 ? d : a.$2.fullName.compareTo(b.$2.fullName);
    });
    return scored.take(limit).map((e) => e.$2).toList();
  }

  /// 도감용: 브랜드별 라인 수
  Map<String, int> brandLineCounts() {
    final m = <String, int>{};
    for (final c in _cigars) {
      m[c.brand] = (m[c.brand] ?? 0) + 1;
    }
    return m;
  }
}
