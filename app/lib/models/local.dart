// 로컬(sqflite)에 저장되는 사용자 데이터 모델.

class Humidor {
  final int id;
  final String name;
  final int sortOrder;
  Humidor({required this.id, required this.name, required this.sortOrder});

  factory Humidor.fromMap(Map<String, Object?> m) => Humidor(
        id: m['id'] as int,
        name: m['name'] as String,
        sortOrder: (m['sort_order'] as int?) ?? 0,
      );
}

/// 휴미더 안의 재고 한 줄 (같은 시가·비톨라·입고일이면 한 줄)
class StockItem {
  final int id;
  final int humidorId;
  final String cigarId; // 중앙 DB id, 직접 입력이면 "custom:..." 형태
  final String cigarName; // 표시용 (DB 바뀌어도 유지)
  final String? vitola;
  final int qty;
  final int? pricePerStick; // 개비당 가격. KRW 는 원 단위, 그 외 통화는 센트(×100) 단위. 미입력이면 null
  final String currency; // 'KRW' | 'USD' ...
  final String addedDate; // yyyy-MM-dd
  final String? memo;

  StockItem({
    required this.id,
    required this.humidorId,
    required this.cigarId,
    required this.cigarName,
    required this.vitola,
    required this.qty,
    required this.pricePerStick,
    this.currency = 'KRW',
    required this.addedDate,
    this.memo,
  });

  factory StockItem.fromMap(Map<String, Object?> m) => StockItem(
        id: m['id'] as int,
        humidorId: m['humidor_id'] as int,
        cigarId: m['cigar_id'] as String,
        cigarName: m['cigar_name'] as String,
        vitola: m['vitola'] as String?,
        qty: m['qty'] as int,
        pricePerStick: m['price_per_stick'] as int?,
        currency: (m['currency'] as String?) ?? 'KRW',
        addedDate: m['added_date'] as String,
        memo: m['memo'] as String?,
      );

  /// 입고일로부터 며칠 숙성됐는지
  int get agingDays {
    final d = DateTime.tryParse(addedDate);
    if (d == null) return 0;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  }
}

/// 흡연 기록 한 건
class SmokeLog {
  final int id;
  final String cigarId;
  final String cigarName;
  final String? vitola;
  final String date; // yyyy-MM-dd
  final double score; // 0~10, 0.5 단위 (v5 이전엔 0~100 정수였음)
  final List<String> tags; // 체크한 노트 태그 id
  final String? noteStart;
  final String? noteMid;
  final String? noteEnd;
  final String? summary; // 총평 (한 줄 소감)
  final String? place;
  final String? pairing;
  final int? stockItemId; // 재고 차감했으면 어디서

  SmokeLog({
    required this.id,
    required this.cigarId,
    required this.cigarName,
    required this.vitola,
    required this.date,
    required this.score,
    required this.tags,
    this.noteStart,
    this.noteMid,
    this.noteEnd,
    this.summary,
    this.place,
    this.pairing,
    this.stockItemId,
  });

  factory SmokeLog.fromMap(Map<String, Object?> m) => SmokeLog(
        id: m['id'] as int,
        cigarId: m['cigar_id'] as String,
        cigarName: m['cigar_name'] as String,
        vitola: m['vitola'] as String?,
        date: m['date'] as String,
        score: (m['score'] as num).toDouble(),
        tags: ((m['tags'] as String?) ?? '').split(',').where((e) => e.isNotEmpty).toList(),
        noteStart: m['note_start'] as String?,
        noteMid: m['note_mid'] as String?,
        noteEnd: m['note_end'] as String?,
        summary: m['summary'] as String?,
        place: m['place'] as String?,
        pairing: m['pairing'] as String?,
        stockItemId: m['stock_item_id'] as int?,
      );
}
