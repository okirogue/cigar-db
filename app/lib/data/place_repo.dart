import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/place.dart';
import 'remote_db.dart';

/// 장소 목록 (assets/places.json → 캐시 → 원격). 시가 DB 와 같은 갱신 방식.
class PlaceRepo {
  PlaceRepo._();
  static final PlaceRepo instance = PlaceRepo._();

  List<Place> _places = [];
  String rev = '';
  bool _loaded = false;

  List<Place> get all => _places;
  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    var bundleRev = '';
    try {
      final raw = await rootBundle.loadString('assets/places.json');
      try {
        bundleRev = (jsonDecode(await rootBundle.loadString('assets/places_meta.json')) as Map<String, dynamic>)['rev'] as String? ?? '';
      } catch (_) {}
      _apply(raw, bundleRev);
    } catch (_) {
      _places = [];
    }
    final cached = await RemoteDb.places.readCache();
    if (cached != null) {
      final crev = (cached.$1['rev'] ?? '') as String;
      if (crev.compareTo(bundleRev) > 0) {
        try {
          _apply(cached.$2, crev);
        } catch (_) {
          await RemoteDb.places.clearCache();
        }
      } else {
        await RemoteDb.places.clearCache();
      }
    }
    _loaded = true;
  }

  void _apply(String raw, String newRev) {
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    _places = list.map(Place.fromJson).toList();
    rev = newRev;
  }

  /// 서버에 더 새 목록이 있으면 교체. 바뀌었으면 true.
  Future<bool> refreshRemote() async {
    final got = await RemoteDb.places.fetchIfNewer(rev, _places.length);
    if (got == null) return false;
    try {
      _apply(got.$2, (got.$1['rev'] ?? '') as String);
      return true;
    } catch (_) {
      await RemoteDb.places.clearCache();
      return false;
    }
  }

  /// 국가 → 도시 → 장소. 사용자 언어 국가(ko→KR, en→US)가 먼저, 나머지는 장소 수 많은 순.
  List<(String, List<(String, List<Place>)>)> grouped(String lang) {
    final byCountry = <String, Map<String, List<Place>>>{};
    for (final p in _places) {
      byCountry.putIfAbsent(p.country, () => {}).putIfAbsent(p.city, () => []).add(p);
    }
    final home = lang == 'ko' ? 'KR' : 'US';
    final countries = byCountry.keys.toList()
      ..sort((a, b) {
        if (a == home) return -1;
        if (b == home) return 1;
        final na = byCountry[a]!.values.fold<int>(0, (s, l) => s + l.length);
        final nb = byCountry[b]!.values.fold<int>(0, (s, l) => s + l.length);
        return nb.compareTo(na);
      });
    return [
      for (final c in countries)
        (
          c,
          [
            for (final e in (byCountry[c]!.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length))))
              (e.key, e.value..sort((a, b) => a.name.compareTo(b.name)))
          ]
        ),
    ];
  }

  /// 거리순 (km 와 함께)
  List<(Place, double)> nearest(double lat, double lng, {int limit = 30}) {
    final out = [for (final p in _places) (p, p.distanceKm(lat, lng))]..sort((a, b) => a.$2.compareTo(b.$2));
    return out.take(limit).toList();
  }
}
