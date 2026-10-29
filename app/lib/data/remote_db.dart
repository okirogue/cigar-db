import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 시가 DB 원격 갱신.
///
/// 앱에 번들된 assets/cigars.json 은 스토어 업데이트 없이는 못 바꾸므로, GitHub Pages 에 올려 둔
/// 같은 축약본(docs/db/)을 앱 시작 때 조용히 받아 와 더 새것이면 바꿔 끼운다.
///   meta.json   {"rev": "2026-10-30T01:02:03Z", "sha": "...", "count": 2650}
///   cigars.json 번들과 같은 형식
/// rev 는 build_app_assets.py 실행 시각(ISO, UTC) — 문자열 비교로 신구를 가린다.
/// 받은 본은 로컬에 캐시 (모바일: 앱 지원 폴더 파일, 웹: SharedPreferences) 해서 다음 시작부터 바로 쓴다.
class RemoteDb {
  RemoteDb._();
  static final instance = RemoteDb._();

  static const base = 'https://okirogue.github.io/cigar-db/db';
  static const _kMeta = 'db_cache_meta';
  static const _kJson = 'db_cache_json';

  /// 로컬 캐시 (meta, cigars json 원문). 없으면 null.
  Future<(Map<String, dynamic>, String)?> readCache() async {
    try {
      if (kIsWeb) {
        final sp = await SharedPreferences.getInstance();
        final m = sp.getString(_kMeta), j = sp.getString(_kJson);
        if (m == null || j == null) return null;
        return (jsonDecode(m) as Map<String, dynamic>, j);
      }
      final d = await _dir();
      final mf = File(p.join(d.path, 'meta.json')), jf = File(p.join(d.path, 'cigars.json'));
      if (!await mf.exists() || !await jf.exists()) return null;
      return (jsonDecode(await mf.readAsString()) as Map<String, dynamic>, await jf.readAsString());
    } catch (e) {
      debugPrint('RemoteDb.readCache: $e');
      return null;
    }
  }

  Future<void> _writeCache(Map<String, dynamic> meta, String json) async {
    if (kIsWeb) {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kJson, json);
      await sp.setString(_kMeta, jsonEncode(meta));
      return;
    }
    final d = await _dir();
    await File(p.join(d.path, 'cigars.json')).writeAsString(json, flush: true);
    await File(p.join(d.path, 'meta.json')).writeAsString(jsonEncode(meta), flush: true);
  }

  Future<void> clearCache() async {
    try {
      if (kIsWeb) {
        final sp = await SharedPreferences.getInstance();
        await sp.remove(_kJson);
        await sp.remove(_kMeta);
        return;
      }
      final d = await _dir();
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'dbcache'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// 서버 meta 를 보고 [currentRev] 보다 새것이면 받아서 캐시에 저장하고 (meta, json) 반환. 아니면 null.
  /// 네트워크 실패는 모두 삼킨다 (오프라인 정상 동작).
  Future<(Map<String, dynamic>, String)?> fetchIfNewer(String currentRev, int currentCount) async {
    try {
      final r = await http.get(Uri.parse('$base/meta.json?t=${DateTime.now().millisecondsSinceEpoch ~/ 600000}')).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final meta = jsonDecode(r.body) as Map<String, dynamic>;
      final rev = (meta['rev'] ?? '') as String;
      if (rev.isEmpty || rev.compareTo(currentRev) <= 0) return null;
      final count = (meta['count'] as num?)?.toInt() ?? 0;
      // 안전장치: 항목이 크게 줄어든 본은 안 받는다 (배포 사고 방지)
      if (count < currentCount * 0.9) return null;
      final jr = await http.get(Uri.parse('$base/cigars.json?v=${Uri.encodeComponent(rev)}')).timeout(const Duration(seconds: 30));
      if (jr.statusCode != 200) return null;
      final body = utf8.decode(jr.bodyBytes);
      final list = jsonDecode(body);
      if (list is! List || list.length != count) return null;
      await _writeCache(meta, body);
      return (meta, body);
    } catch (e) {
      debugPrint('RemoteDb.fetch: $e');
      return null;
    }
  }
}
