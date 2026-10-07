import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/local.dart';

/// 사용자 데이터(휴미더·재고·기록) sqflite 저장소.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  static const maxHumidors = 3; // 무료 기본 한도 (UI엔 안내 안 띄움)

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'cigar_log.db'),
      version: 3,
      onUpgrade: (d, oldV, newV) async {
        if (oldV < 2) await d.execute(_customDdl);
        if (oldV < 3) await d.execute('ALTER TABLE logs ADD COLUMN summary TEXT');
      },
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE humidors(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0
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
            added_date TEXT NOT NULL,
            memo TEXT
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
            stock_item_id INTEGER
          )''');
        await d.execute(_customDdl);
        await d.insert('humidors', {'name': '내 휴미더', 'sort_order': 0});
      },
    );
    return _db!;
  }

  // 사용자가 직접 추가한 시가(DB에 없는 한정판 등). json = Cigar.fromJson 형식 그대로.
  static const _customDdl = '''
          CREATE TABLE IF NOT EXISTS custom_cigars(
            id TEXT PRIMARY KEY,
            json TEXT NOT NULL,
            created TEXT NOT NULL
          )''';

  Future<List<Map<String, dynamic>>> customCigars() async {
    final d = await db;
    final rows = await d.query('custom_cigars', orderBy: 'created ASC');
    return [for (final r in rows) jsonDecode(r['json'] as String) as Map<String, dynamic>];
  }

  Future<void> addCustomCigar(Map<String, dynamic> j) async {
    final d = await db;
    await d.insert('custom_cigars', {'id': j['id'], 'json': jsonEncode(j), 'created': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 백업 복원(덮어쓰기)용 — 모든 사용자 데이터 삭제 후 기본 휴미더 하나
  Future<void> wipeUserData() async {
    final d = await db;
    await d.delete('logs');
    await d.delete('stock');
    await d.delete('humidors');
    await d.delete('custom_cigars');
    await d.insert('humidors', {'name': '내 휴미더', 'sort_order': 0});
  }

  // ---------- 휴미더 ----------
  Future<List<Humidor>> humidors() async {
    final rows = await (await db).query('humidors', orderBy: 'sort_order, id');
    return rows.map(Humidor.fromMap).toList();
  }

  Future<int> addHumidor(String name) async {
    final d = await db;
    final n = Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM humidors')) ?? 0;
    return d.insert('humidors', {'name': name, 'sort_order': n});
  }

  Future<void> renameHumidor(int id, String name) async {
    await (await db).update('humidors', {'name': name}, where: 'id=?', whereArgs: [id]);
  }

  Future<void> deleteHumidor(int id) async {
    final d = await db;
    await d.delete('stock', where: 'humidor_id=?', whereArgs: [id]);
    await d.delete('humidors', where: 'id=?', whereArgs: [id]);
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
    required String addedDate,
  }) async {
    return (await db).insert('stock', {
      'humidor_id': humidorId,
      'cigar_id': cigarId,
      'cigar_name': cigarName,
      'vitola': vitola,
      'qty': qty,
      'price_per_stick': pricePerStick,
      'added_date': addedDate,
    });
  }

  Future<void> changeQty(int stockId, int delta) async {
    final d = await db;
    await d.rawUpdate('UPDATE stock SET qty = MAX(0, qty + ?) WHERE id=?', [delta, stockId]);
  }

  Future<void> deleteStock(int stockId) async {
    await (await db).delete('stock', where: 'id=?', whereArgs: [stockId]);
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
    required int score,
    required List<String> tags,
    String? noteStart,
    String? noteMid,
    String? noteEnd,
    String? summary,
    String? place,
    String? pairing,
    int? deductStockId,
  }) async {
    final d = await db;
    return d.transaction((txn) async {
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
        'stock_item_id': deductStockId,
      });
      if (deductStockId != null) {
        await txn.rawUpdate('UPDATE stock SET qty = MAX(0, qty - 1) WHERE id=?', [deductStockId]);
      }
      return id;
    });
  }

  Future<void> updateLog(int id, Map<String, Object?> fields) async {
    await (await db).update('logs', fields, where: 'id=?', whereArgs: [id]);
  }

  Future<void> deleteLog(int id) async {
    await (await db).delete('logs', where: 'id=?', whereArgs: [id]);
  }
}
