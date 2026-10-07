import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/cigar.dart';
import '../state.dart';
import 'local_db.dart';

/// JSON 백업 내보내기/가져오기. 형식(version 1):
/// {"version":1,"humidors":["이름"...],"stock":[{humidor,cigar_id,cigar_name,vitola,qty,price_per_stick,added_date}],
///  "logs":[{cigar_id,cigar_name,vitola,date,score,tags[],note_start,note_mid,note_end,place,pairing}]}
class Backup {
  static Future<String> buildJson(AppState st) async {
    final hName = {for (final h in st.humidors) h.id: h.name};
    final out = {
      'version': 1,
      'exported': DateTime.now().toIso8601String().substring(0, 10),
      'source': 'MyHumidor',
      'humidors': st.humidors.map((h) => h.name).toList(),
      // 직접 추가한 시가 (DB에 없는 것) — 가져올 때 먼저 복원
      'custom_cigars': [for (final c in st.repo.customs) c.toJson()],
      'stock': [
        for (final s in st.allStock)
          {
            'humidor': hName[s.humidorId] ?? '내 휴미더',
            'cigar_id': s.cigarId,
            'cigar_name': s.cigarName,
            'vitola': s.vitola,
            'qty': s.qty,
            'price_per_stick': s.pricePerStick,
            'added_date': s.addedDate,
          }
      ],
      'logs': [
        for (final l in st.logs)
          {
            'cigar_id': l.cigarId,
            'cigar_name': l.cigarName,
            'vitola': l.vitola,
            'date': l.date,
            'score': l.score,
            'tags': l.tags,
            'note_start': l.noteStart,
            'note_mid': l.noteMid,
            'note_end': l.noteEnd,
            'summary': l.summary,
            'place': l.place,
            'pairing': l.pairing,
          }
      ],
    };
    return const JsonEncoder.withIndent(' ').convert(out);
  }

  /// 공유 시트로 백업 파일 내보내기
  static Future<void> export(AppState st) async {
    final json = await buildJson(st);
    final dir = await getTemporaryDirectory();
    final name = 'myhumidor_backup_${DateTime.now().toIso8601String().substring(0, 10)}.json';
    final f = File(p.join(dir.path, name));
    await f.writeAsString(json);
    await Share.shareXFiles([XFile(f.path, mimeType: 'application/json')], subject: 'MyHumidor 백업');
  }

  /// 파일 선택 → 가져오기. 반환: (휴미더, 재고 줄, 기록) 추가 개수. 취소하면 null.
  static Future<(int, int, int)?> import(AppState st, {bool replace = false}) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (res == null || res.files.isEmpty) return null;
    final bytes = res.files.single.bytes ?? await File(res.files.single.path!).readAsBytes();
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return importMap(st, data, replace: replace);
  }

  static Future<(int, int, int)> importMap(AppState st, Map<String, dynamic> data, {bool replace = false}) async {
    final db = st.db;
    if (replace) await db.wipeUserData();

    // 직접 추가한 시가 먼저 (재고/기록이 참조하므로)
    for (final j in ((data['custom_cigars'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      if (st.repo.byId(j['id'] as String) != null) continue;
      await db.addCustomCigar(j);
      st.repo.addCustom(Cigar.fromJson(j));
    }

    // 휴미더: 이름으로 매칭, 없으면 생성 (최대 한도 넘으면 첫 휴미더로)
    var humidors = await db.humidors();
    final byName = {for (final h in humidors) h.name: h.id};
    var addedH = 0;
    final names = <String>{
      ...List<String>.from(data['humidors'] ?? const []),
      ...((data['stock'] as List?) ?? const []).map((s) => (s['humidor'] ?? '내 휴미더') as String),
    };
    for (final n in names) {
      if (byName.containsKey(n)) continue;
      if (byName.length >= LocalDb.maxHumidors) break;
      byName[n] = await db.addHumidor(n);
      addedH++;
    }
    humidors = await db.humidors();
    final fallback = humidors.first.id;

    var addedS = 0;
    for (final s in ((data['stock'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      final qty = (s['qty'] as num?)?.toInt() ?? 0;
      if (qty <= 0) continue;
      await db.addStock(
        humidorId: byName[s['humidor']] ?? fallback,
        cigarId: s['cigar_id'] as String,
        cigarName: s['cigar_name'] as String,
        vitola: s['vitola'] as String?,
        qty: qty,
        pricePerStick: (s['price_per_stick'] as num?)?.toInt(),
        addedDate: (s['added_date'] as String?) ?? DateTime.now().toIso8601String().substring(0, 10),
      );
      addedS++;
    }

    var addedL = 0;
    for (final l in ((data['logs'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      await db.addLog(
        cigarId: l['cigar_id'] as String,
        cigarName: l['cigar_name'] as String,
        vitola: l['vitola'] as String?,
        date: (l['date'] as String?) ?? DateTime.now().toIso8601String().substring(0, 10),
        score: (l['score'] as num?)?.toInt() ?? 75,
        tags: List<String>.from(l['tags'] ?? const []),
        noteStart: l['note_start'] as String?,
        noteMid: l['note_mid'] as String?,
        noteEnd: l['note_end'] as String?,
        summary: l['summary'] as String?,
        place: l['place'] as String?,
        pairing: l['pairing'] as String?,
      );
      addedL++;
    }
    await st.reload();
    return (addedH, addedS, addedL);
  }
}
