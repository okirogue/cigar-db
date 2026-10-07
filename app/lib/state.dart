import 'package:flutter/foundation.dart';

import 'data/cigar_repo.dart';
import 'data/local_db.dart';
import 'data/recommender.dart';
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
    _recompute();
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

  /// 취향 프로필 · 추천 (기록 바뀔 때마다 reload에서 재계산)
  TasteProfile? profile;
  List<Reco> recos = [];

  /// 추천 근거가 된 "점수 높게 준" 시가 이름들 (중복 제거, 점수순 최대 3개)
  List<String> get topRatedNames {
    final seen = <String>{};
    final sorted = [...logs]..sort((a, b) => b.score.compareTo(a.score));
    final out = <String>[];
    for (final l in sorted) {
      if (l.score < 80 || !seen.add(l.cigarId)) continue;
      out.add(l.cigarName);
      if (out.length >= 3) break;
    }
    return out;
  }

  void _recompute() {
    profile = TasteProfile.build(logs, repo);
    recos = Recommender(repo).forMe(profile!, smokedIds, limit: 8);
  }
}
