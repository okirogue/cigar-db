import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import '../l10n.dart';
import '../models/local.dart';

/// 사용자 데이터(휴미더·재고·기록) sqflite 저장소.
class LocalDb {
  /// v5 마이그레이션으로 점수 스케일이 바뀌었으면 true — 서버 공유본 재업로드 트리거
  static bool scoresRescaled = false;

  LocalDb._();
  static final LocalDb instance = LocalDb._();

  static const maxHumidors = 3; // 무료 기본 한도 (UI엔 안내 안 띄움)

  Database? _db;
  Future<Database>? _opening; // 동시 호출 시 한 번만 연다

  Future<Database> get db async {
    if (_db != null) return _db!;
    return _opening ??= _open();
  }

  Future<Database> _open() async {
    // 웹: IndexedDB 위에 올라간 sqlite (sqflite_common_ffi_web). API 는 동일.
    if (kIsWeb) databaseFactory = databaseFactoryFfiWeb;
    final path = kIsWeb ? 'cigar_log.db' : p.join(await getDatabasesPath(), 'cigar_log.db');
    _db = await openDatabase(
      path,
      version: 10,
      onUpgrade: (d, oldV, newV) async {
        if (oldV < 2) await d.execute(_customDdl);
        if (oldV < 3) await d.execute('ALTER TABLE logs ADD COLUMN summary TEXT');
        if (oldV < 4) await d.execute("ALTER TABLE stock ADD COLUMN currency TEXT NOT NULL DEFAULT 'KRW'");
        if (oldV < 5) {
          // 100점 → 10점(0.5 단위): 83 → 8.5
          await d.execute('UPDATE logs SET score = ROUND(score / 5.0) / 2.0 WHERE score > 10');
          scoresRescaled = true;
        }
        if (oldV < 6) await d.execute('ALTER TABLE logs ADD COLUMN photos TEXT');
        if (oldV < 7) {
          // 기록 당시의 재고 정보(구매가·통화·입고일) 스냅샷 — 재고가 나중에 지워져도 기록엔 남게
          await d.execute('ALTER TABLE logs ADD COLUMN stock_price INTEGER');
          await d.execute('ALTER TABLE logs ADD COLUMN stock_currency TEXT');
          await d.execute('ALTER TABLE logs ADD COLUMN stock_added TEXT');
          await d.execute('''
            UPDATE logs SET
              stock_price = (SELECT price_per_stick FROM stock WHERE stock.id = logs.stock_item_id),
              stock_currency = (SELECT currency FROM stock WHERE stock.id = logs.stock_item_id),
              stock_added = (SELECT added_date FROM stock WHERE stock.id = logs.stock_item_id)
            WHERE stock_item_id IS NOT NULL''');
        }
        if (oldV < 8) await _migrateV8(d);
        if (oldV < 9) await d.execute(_wishDdl);
        if (oldV < 10) await _createIndexes(d);
      },
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE humidors(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            sid TEXT,
            updated INTEGER NOT NULL DEFAULT 0
          )''');
        await d.execute('''
          CREATE TABLE stock(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            humidor_id INTEGER NOT NULL,
            cigar_id TEXT NOT NULL,
            cigar_name TEXT NOT NULL,
            vitola TEXT,
            qty INTEGER NOT NULL,
            price_per_stick INTEGER,
            currency TEXT NOT NULL DEFAULT 'KRW',
            added_date TEXT NOT NULL,
            memo TEXT,
            sid TEXT,
            updated INTEGER NOT NULL DEFAULT 0
          )''');
        await d.execute('''
          CREATE TABLE logs(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cigar_id TEXT NOT NULL,
            cigar_name TEXT NOT NULL,
            vitola TEXT,
            date TEXT NOT NULL,
            score INTEGER NOT NULL,
            tags TEXT NOT NULL DEFAULT '',
            note_start TEXT,
            note_mid TEXT,
            note_end TEXT,
            summary TEXT,
            place TEXT,
            pairing TEXT,
            photos TEXT,
            stock_item_id INTEGER,
            stock_price INTEGER,
            stock_currency TEXT,
            stock_added TEXT,
            sid TEXT,
            updated INTEGER NOT NULL DEFAULT 0
          )''');
        await d.execute(_customDdl);
        await d.execute(_tombDdl);
        await d.insert('humidors', {'name': tr('내 휴미더', 'My humidor'), 'sort_order': 0, 'sid': newSid(), 'updated': now});
        await d.execute(_wishDdl);
        await _createIndexes(d);
      },
    );
    return _db!;
  }

  /// v10: 자주 쓰는 조회 경로 인덱스 (다이어리 날짜순, 시가별 기록, 휴미더별 재고, 동기화의 sid 조회)
  static Future<void> _createIndexes(Database d) async {
    for (final ddl in [
      'CREATE INDEX IF NOT EXISTS idx_logs_date ON logs(date)',
      'CREATE INDEX IF NOT EXISTS idx_logs_cigar ON logs(cigar_id)',
      'CREATE INDEX IF NOT EXISTS idx_logs_sid ON logs(sid)',
      'CREATE INDEX IF NOT EXISTS idx_stock_humidor ON stock(humidor_id)',
      'CREATE INDEX IF NOT EXISTS idx_stock_sid ON stock(sid)',
      'CREATE INDEX IF NOT EXISTS idx_wish_cigar ON wishlist(cigar_id)',
      'CREATE INDEX IF NOT EXISTS idx_wish_sid ON wishlist(sid)',
      'CREATE INDEX IF NOT EXISTS idx_humidors_sid ON humidors(sid)',
    ]) {
      await d.execute(ddl);
    }
  }

  // 사용자가 직접 추가한 시가(DB에 없는 한정판 등). json = Cigar.fromJson 형식 그대로.
  static const _customDdl = '''
          CREATE TABLE IF NOT EXISTS custom_cigars(
            id TEXT PRIMARY KEY,
            json TEXT NOT NULL,
            created TEXT NOT NULL,
            updated INTEGER NOT NULL DEFAULT 0
          )''';

  // 지운 행의 흔적 (동기화용): 어느 표의 어떤 sid 를 언제 지웠는지
  static const _tombDdl = '''
          CREATE TABLE IF NOT EXISTS tombstones(
            tbl TEXT NOT NULL,
            sid TEXT NOT NULL,
            updated INTEGER NOT NULL,
            PRIMARY KEY (tbl, sid)
          )''';

  /// v9: 위시리스트 (다음에 살 것). sid/updated 로 동기화·백업 대상.
  static const _wishDdl = '''
    CREATE TABLE IF NOT EXISTS wishlist(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      cigar_id TEXT NOT NULL,
      cigar_name TEXT NOT NULL,
      vitola TEXT,
      memo TEXT,
      priority INTEGER NOT NULL DEFAULT 1,
      created TEXT NOT NULL,
      sid TEXT,
      updated INTEGER NOT NULL DEFAULT 0
    )''';

  /// v8: 기기 간 동기화를 위해 전역 id(sid)와 수정 시각(updated) 추가. 기존 행엔 새 sid 를 붙인다.
  static Future<void> _migrateV8(Database d) async {
    for (final t in ['humidors', 'stock', 'logs']) {
      await d.execute('ALTER TABLE $t ADD COLUMN sid TEXT');
      await d.execute('ALTER TABLE $t ADD COLUMN updated INTEGER NOT NULL DEFAULT 0');
      final rows = await d.query(t, columns: ['id']);
      final b = d.batch();
      for (final r in rows) {
        b.update(t, {'sid': newSid(), 'updated': now}, where: 'id=?', whereArgs: [r['id']]);
      }
      await b.commit(noResult: true);
    }
    // v1→ 업그레이드 땐 _customDdl 이 이미 updated 열을 포함해 만들었을 수 있음
    final cols = await d.rawQuery('PRAGMA table_info(custom_cigars)');
    if (!cols.any((c) => c['name'] == 'updated')) {
      await d.execute('ALTER TABLE custom_cigars ADD COLUMN updated INTEGER NOT NULL DEFAULT 0');
    }
    await d.execute('UPDATE custom_cigars SET updated = $now');
    await d.execute(_tombDdl);
  }

  static int get now => DateTime.now().millisecondsSinceEpoch;

  static final _rnd = Random.secure();
  /// 전역 id: 16자리 hex (기기 간 충돌 없음)
  static String newSid() => List.generate(16, (_) => _rnd.nextInt(16).toRadixString(16)).join();

  Future<void> _tomb(DatabaseExecutor d, String tbl, String? sid) async {
    if (sid == null || sid.isEmpty) return;
    await d.insert('tombstones', {'tbl': tbl, 'sid': sid, 'updated': now}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> customCigars() async {
    final d = await db;
    final rows = await d.query('custom_cigars', orderBy: 'created ASC');
    return [for (final r in rows) jsonDecode(r['json'] as String) as Map<String, dynamic>];
  }

  Future<void> addCustomCigar(Map<String, dynamic> j) async {
    final d = await db;
    await d.insert('custom_cigars', {'id': j['id'], 'json': jsonEncode(j), 'created': DateTime.now().toIso8601String(), 'updated': now}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 백업 복원(덮어쓰기)용 — 모든 사용자 데이터 삭제 후 기본 휴미더 하나
  Future<void> wipeUserData() async {
    final d = await db;
    for (final t in ['logs', 'stock', 'humidors', 'wishlist']) {
      for (final r in await d.query(t, columns: ['sid'])) {
        await _tomb(d, t, r['sid'] as String?);
      }
    }
    for (final r in await d.query('custom_cigars', columns: ['id'])) {
      await _tomb(d, 'custom_cigars', r['id'] as String?);
    }
    await d.delete('logs');
    await d.delete('stock');
    await d.delete('humidors');
    await d.delete('wishlist');
    await d.delete('custom_cigars');
    await d.insert('humidors', {'name': tr('내 휴미더', 'My humidor'), 'sort_order': 0, 'sid': newSid(), 'updated': now});
  }

  // ---------- 휴미더 ----------
  Future<List<Humidor>> humidors() async {
    final rows = await (await db).query('humidors', orderBy: 'sort_order, id');
    return rows.map(Humidor.fromMap).toList();
  }

  Future<int> addHumidor(String name) async {
    final d = await db;
    final n = Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM humidors')) ?? 0;
    return d.insert('humidors', {'name': name, 'sort_order': n, 'sid': newSid(), 'updated': now});
  }

  /// 휴미더 순서 저장 (ids 순서대로 0,1,2…). 바뀐 것만 updated 갱신해서 동기화 대상이 되게.
  Future<void> reorderHumidors(List<int> ids) async {
    final d = await db;
    final b = d.batch();
    for (var i = 0; i < ids.length; i++) {
      b.update('humidors', {'sort_order': i, 'updated': now}, where: 'id=? AND sort_order<>?', whereArgs: [ids[i], i]);
    }
    await b.commit(noResult: true);
  }

  Future<void> renameHumidor(int id, String name) async {
    await (await db).update('humidors', {'name': name, 'updated': now}, where: 'id=?', whereArgs: [id]);
  }

  Future<void> deleteHumidor(int id) async {
    final d = await db;
    for (final r in await d.query('stock', columns: ['sid'], where: 'humidor_id=?', whereArgs: [id])) {
      await _tomb(d, 'stock', r['sid'] as String?);
    }
    for (final r in await d.query('humidors', columns: ['sid'], where: 'id=?', whereArgs: [id])) {
      await _tomb(d, 'humidors', r['sid'] as String?);
    }
    await d.delete('stock', where: 'humidor_id=?', whereArgs: [id]);
    await d.delete('humidors', where: 'id=?', whereArgs: [id]);
  }

  // ---------- 위시리스트 ----------
  Future<List<WishItem>> wishlist() async {
    final rows = await (await db).query('wishlist', orderBy: 'priority DESC, created DESC, id DESC');
    return rows.map(WishItem.fromMap).toList();
  }

  Future<bool> inWishlist(String cigarId) async {
    final r = await (await db).query('wishlist', columns: ['id'], where: 'cigar_id=?', whereArgs: [cigarId], limit: 1);
    return r.isNotEmpty;
  }

  Future<int> addWish({required String cigarId, required String cigarName, String? vitola, String? memo, int priority = 1, String? created}) async {
    final d = await db;
    final cur = await d.query('wishlist', columns: ['id'], where: 'cigar_id=?', whereArgs: [cigarId], limit: 1);
    if (cur.isNotEmpty) return cur.first['id'] as int;
    final n = DateTime.now();
    final today = '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    return d.insert('wishlist', {
      'cigar_id': cigarId, 'cigar_name': cigarName, 'vitola': vitola, 'memo': memo, 'priority': priority,
      'created': created ?? today, 'sid': newSid(), 'updated': now,
    });
  }

  Future<void> updateWish(int id, {String? vitola, String? memo, int? priority}) async {
    await (await db).update('wishlist', {
      if (vitola != null) 'vitola': vitola,
      if (memo != null) 'memo': memo,
      if (priority != null) 'priority': priority,
      'updated': now,
    }, where: 'id=?', whereArgs: [id]);
  }

  Future<void> deleteWish(int id) async {
    final d = await db;
    for (final r in await d.query('wishlist', columns: ['sid'], where: 'id=?', whereArgs: [id])) {
      await _tomb(d, 'wishlist', r['sid'] as String?);
    }
    await d.delete('wishlist', where: 'id=?', whereArgs: [id]);
  }

  Future<void> deleteWishByCigar(String cigarId) async {
    final d = await db;
    for (final r in await d.query('wishlist', columns: ['id'], where: 'cigar_id=?', whereArgs: [cigarId])) {
      await deleteWish(r['id'] as int);
    }
  }

  // ---------- 재고 ----------
  Future<List<StockItem>> stock({int? humidorId}) async {
    final rows = await (await db).query(
      'stock',
      where: humidorId == null ? 'qty > 0' : 'humidor_id=? AND qty > 0',
      whereArgs: humidorId == null ? null : [humidorId],
      orderBy: 'added_date DESC, id DESC',
    );
    return rows.map(StockItem.fromMap).toList();
  }

  Future<int> totalQty() async {
    final v = await (await db).rawQuery('SELECT SUM(qty) AS s FROM stock');
    return (v.first['s'] as int?) ?? 0;
  }

  Future<Map<int, int>> qtyByHumidor() async {
    final rows = await (await db).rawQuery('SELECT humidor_id, SUM(qty) AS s FROM stock GROUP BY humidor_id');
    return {for (final r in rows) r['humidor_id'] as int: (r['s'] as int?) ?? 0};
  }

  Future<int> addStock({
    required int humidorId,
    required String cigarId,
    required String cigarName,
    String? vitola,
    required int qty,
    int? pricePerStick,
    String currency = 'KRW',
    required String addedDate,
  }) async {
    return (await db).insert('stock', {
      'humidor_id': humidorId,
      'cigar_id': cigarId,
      'cigar_name': cigarName,
      'vitola': vitola,
      'qty': qty,
      'price_per_stick': pricePerStick,
      'currency': currency,
      'added_date': addedDate,
      'sid': newSid(),
      'updated': now,
    });
  }

  Future<void> changeQty(int stockId, int delta) async {
    final d = await db;
    await d.rawUpdate('UPDATE stock SET qty = MAX(0, qty + ?), updated = ? WHERE id=?', [delta, now, stockId]);
  }

  Future<void> deleteStock(int stockId) async {
    final d = await db;
    for (final r in await d.query('stock', columns: ['sid'], where: 'id=?', whereArgs: [stockId])) {
      await _tomb(d, 'stock', r['sid'] as String?);
    }
    await d.delete('stock', where: 'id=?', whereArgs: [stockId]);
  }

  /// 재고 [qty]개를 다른 휴미더로 옮김. 대상에 같은 시가·비톨라·입고일 줄이 있으면 거기에 합치고,
  /// 없으면 같은 정보(가격·통화·메모)로 새 줄을 만든다. 전부 옮기면 원래 줄은 지워진다.
  Future<void> moveStock(int stockId, int toHumidorId, int qty) async {
    final d = await db;
    await d.transaction((txn) async {
      final rows = await txn.query('stock', where: 'id=?', whereArgs: [stockId]);
      if (rows.isEmpty) return;
      final src = StockItem.fromMap(rows.first);
      if (src.humidorId == toHumidorId || qty <= 0) return;
      final n = qty > src.qty ? src.qty : qty;
      final same = await txn.query(
        'stock',
        where: 'humidor_id=? AND cigar_id=? AND IFNULL(vitola,\'\')=? AND added_date=? AND id<>?',
        whereArgs: [toHumidorId, src.cigarId, src.vitola ?? '', src.addedDate, src.id],
        limit: 1,
      );
      if (same.isNotEmpty) {
        await txn.rawUpdate('UPDATE stock SET qty = qty + ?, updated = ? WHERE id=?', [n, now, same.first['id']]);
      } else if (n >= src.qty) {
        // 전부 옮기고 대상에 합칠 줄이 없으면 줄 자체를 이동 (id 유지 → 기록의 stock_item_id 도 그대로)
        await txn.update('stock', {'humidor_id': toHumidorId, 'updated': now}, where: 'id=?', whereArgs: [src.id]);
        return;
      } else {
        await txn.insert('stock', {
          'humidor_id': toHumidorId,
          'cigar_id': src.cigarId,
          'cigar_name': src.cigarName,
          'vitola': src.vitola,
          'qty': n,
          'price_per_stick': src.pricePerStick,
          'currency': src.currency,
          'added_date': src.addedDate,
          'memo': src.memo,
          'sid': newSid(),
          'updated': now,
        });
      }
      if (n >= src.qty) {
        await _tomb(txn, 'stock', src.sid);
        await txn.delete('stock', where: 'id=?', whereArgs: [src.id]);
      } else {
        await txn.rawUpdate('UPDATE stock SET qty = qty - ?, updated = ? WHERE id=?', [n, now, src.id]);
      }
    });
  }

  /// 해당 시가의 재고 줄(비톨라 무관) — 기록 시 차감 후보
  Future<List<StockItem>> stockOfCigar(String cigarId) async {
    final rows = await (await db).query('stock', where: 'cigar_id=? AND qty>0', whereArgs: [cigarId], orderBy: 'added_date');
    return rows.map(StockItem.fromMap).toList();
  }

  // ---------- 기록 ----------
  Future<List<SmokeLog>> logs({String orderBy = 'date DESC, id DESC'}) async {
    final rows = await (await db).query('logs', orderBy: orderBy);
    return rows.map(SmokeLog.fromMap).toList();
  }

  Future<List<SmokeLog>> logsOfCigar(String cigarId) async {
    final rows = await (await db).query('logs', where: 'cigar_id=?', whereArgs: [cigarId], orderBy: 'date DESC');
    return rows.map(SmokeLog.fromMap).toList();
  }

  Future<int> addLog({
    required String cigarId,
    required String cigarName,
    String? vitola,
    required String date,
    required double score,
    required List<String> tags,
    String? noteStart,
    String? noteMid,
    String? noteEnd,
    String? summary,
    String? place,
    String? pairing,
    List<String> photos = const [],
    int? deductStockId,
    // 백업 복원용: 재고 연결 없이 스냅샷만 직접 넣기
    int? stockPrice,
    String? stockCurrency,
    String? stockAdded,
  }) async {
    final d = await db;
    return d.transaction((txn) async {
      // 재고에서 기록하면 그 재고의 구매가·입고일을 기록에 같이 박아둔다 (표시용 스냅샷)
      Map<String, Object?>? stock;
      if (deductStockId != null) {
        final rows = await txn.query('stock', columns: ['price_per_stick', 'currency', 'added_date'], where: 'id=?', whereArgs: [deductStockId]);
        if (rows.isNotEmpty) stock = rows.first;
      }
      final id = await txn.insert('logs', {
        'cigar_id': cigarId,
        'cigar_name': cigarName,
        'vitola': vitola,
        'date': date,
        'score': score,
        'tags': tags.join(','),
        'note_start': noteStart,
        'note_mid': noteMid,
        'note_end': noteEnd,
        'summary': summary,
        'place': place,
        'pairing': pairing,
        'photos': photos.isEmpty ? null : photos.join(','),
        'stock_item_id': deductStockId,
        'stock_price': stock?['price_per_stick'] ?? stockPrice,
        'stock_currency': stock?['currency'] ?? stockCurrency,
        'stock_added': stock?['added_date'] ?? stockAdded,
        'sid': newSid(),
        'updated': now,
      });
      if (deductStockId != null) {
        await txn.rawUpdate('UPDATE stock SET qty = MAX(0, qty - 1), updated = ? WHERE id=?', [now, deductStockId]);
      }
      return id;
    });
  }

  Future<void> updateLog(int id, Map<String, Object?> fields) async {
    await (await db).update('logs', {...fields, 'updated': now}, where: 'id=?', whereArgs: [id]);
  }

  Future<void> deleteLog(int id) async {
    final d = await db;
    for (final r in await d.query('logs', columns: ['sid'], where: 'id=?', whereArgs: [id])) {
      await _tomb(d, 'logs', r['sid'] as String?);
    }
    await d.delete('logs', where: 'id=?', whereArgs: [id]);
  }

  // ---------- 동기화용 (운영자 전용, data/sync.dart) ----------
  /// 어떤 표든 updated > since 인 행
  Future<List<Map<String, Object?>>> changedSince(String tbl, int since) async {
    return (await db).query(tbl, where: 'updated > ?', whereArgs: [since]);
  }

  Future<List<Map<String, Object?>>> tombstonesSince(int since) async {
    return (await db).query('tombstones', where: 'updated > ?', whereArgs: [since]);
  }

  Future<Map<String, Object?>?> bySid(String tbl, String sid) async {
    final rows = await (await db).query(tbl, where: 'sid=?', whereArgs: [sid], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// 서버에서 받은 행을 sid 기준으로 넣거나 덮어씀. 더 최근 로컬 수정이 있으면 건너뜀.
  /// 반환: (로컬 id, 실제로 바뀌었는지)
  Future<(int, bool)> upsertBySid(String tbl, String sid, Map<String, Object?> fields, int updated) async {
    final d = await db;
    final cur = await bySid(tbl, sid);
    if (cur != null) {
      if (((cur['updated'] as int?) ?? 0) >= updated) return (cur['id'] as int, false);
      await d.update(tbl, {...fields, 'updated': updated}, where: 'sid=?', whereArgs: [sid]);
      return (cur['id'] as int, true);
    }
    return (await d.insert(tbl, {...fields, 'sid': sid, 'updated': updated}), true);
  }

  /// 서버 묘비 반영. 지운 게 있으면 true. 휴미더면 안의 재고도 같이.
  Future<bool> deleteBySid(String tbl, String sid) async {
    final d = await db;
    if (tbl == 'custom_cigars') {
      return await d.delete(tbl, where: 'id=?', whereArgs: [sid]) > 0;
    }
    if (tbl == 'humidors') {
      final r = await bySid('humidors', sid);
      if (r != null) await d.delete('stock', where: 'humidor_id=?', whereArgs: [r['id']]);
    }
    return await d.delete(tbl, where: 'sid=?', whereArgs: [sid]) > 0;
  }

  Future<List<Map<String, Object?>>> customRowsSince(int since) async {
    return (await db).query('custom_cigars', where: 'updated > ?', whereArgs: [since]);
  }

  Future<bool> upsertCustom(String id, String json, String created, int updated) async {
    final d = await db;
    final cur = await d.query('custom_cigars', where: 'id=?', whereArgs: [id], limit: 1);
    if (cur.isNotEmpty && ((cur.first['updated'] as int?) ?? 0) >= updated) return false;
    await d.insert('custom_cigars', {'id': id, 'json': json, 'created': created, 'updated': updated}, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }
}
