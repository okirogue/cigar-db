import 'package:flutter/foundation.dart';

import 'data/cigar_repo.dart';
import 'data/local_db.dart';
import 'models/local.dart';

/// 화면들이 공유하는 사용자 데이터 상태. DB 변경 후 reload() 호출.
class AppState extends ChangeNotifier {
  final repo = CigarRepo.instance;
  final db = LocalDb.instance;

  List<Humidor> humidors = [];
  Map<int, int> qtyByHumidor = {};
  List<StockItem> allStock = [];
  List<SmokeLog> logs = [];
  bool ready = false;

  Future<void> init() async {
    await repo.load();
    await reload();
    ready = true;
    notifyListeners();
  }

  Future<void> reload() async {
    humidors = await db.humidors();
    qtyByHumidor = await db.qtyByHumidor();
    allStock = await db.stock();
    logs = await db.logs();
    notifyListeners();
  }

  int get totalQty => qtyByHumidor.values.fold(0, (a, b) => a + b);
  bool get canAddHumidor => humidors.length < LocalDb.maxHumidors;

  List<StockItem> stockIn(int humidorId) => allStock.where((s) => s.humidorId == humidorId).toList();

  /// 피워본 시가 id 집합 (도감용)
  Set<String> get smokedIds => logs.map((l) => l.cigarId).toSet();

  /// 체크해 본 노트 태그 집합 (미각용)
  Set<String> get tastedTags => {for (final l in logs) ...l.tags};

  double get avgScore => logs.isEmpty ? 0 : logs.map((l) => l.score).reduce((a, b) => a + b) / logs.length;
}
