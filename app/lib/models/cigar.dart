import '../l10n.dart';
// 중앙 DB(assets/cigars.json)의 시가 한 라인.
class Cigar {
  final String id;
  final String brand;
  final String name;
  final bool cuban;
  final List<String> vitolas;
  final List<String> official; // 공식 노트 태그 id
  final List<String> review; // 리뷰 노트 태그 id
  final Map<String, int> votes; // 2곳 이상 합의된 태그 → 출처 수
  final Map<String, String> specs;
  final int? dojoScore;
  final List<String> aliases;
  final bool tubos;

  Cigar({
    required this.id,
    required this.brand,
    required this.name,
    required this.cuban,
    required this.vitolas,
    required this.official,
    required this.review,
    required this.votes,
    required this.specs,
    required this.dojoScore,
    required this.aliases,
    required this.tubos,
  });

  factory Cigar.fromJson(Map<String, dynamic> j) {
    final specs = <String, String>{};
    (j['specs'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
      specs[k] = v.toString();
    });
    final votes = <String, int>{};
    (j['votes'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
      votes[k] = (v as num).toInt();
    });
    return Cigar(
      id: j['id'] as String,
      brand: j['brand'] as String,
      name: j['name'] as String,
      cuban: j['cuban'] == true,
      vitolas: List<String>.from(j['vitolas'] ?? const []),
      official: List<String>.from(j['official'] ?? const []),
      review: List<String>.from(j['review'] ?? const []),
      votes: votes,
      specs: specs,
      dojoScore: (j['rating'] as Map<String, dynamic>?)?['dojo'] as int?,
      aliases: List<String>.from(j['aliases'] ?? const []),
      tubos: j['tubos'] == true,
    );
  }

  /// 표시용 이름: "Romeo y Julieta Romeo No.1"
  String get fullName => '$brand $name';

  /// 모든 노트 태그 (공식 우선, 중복 제거)
  List<String> get allTags {
    final seen = <String>{};
    final out = <String>[];
    for (final t in [...official, ...review]) {
      if (seen.add(t)) out.add(t);
    }
    return out;
  }

  bool get hasNotes => official.isNotEmpty || review.isNotEmpty;

  /// 사용자가 직접 추가한 시가 (중앙 DB에 없음)
  bool get isCustom => id.startsWith('custom:');

  Map<String, dynamic> toJson() => {
        'id': id,
        'brand': brand,
        'name': name,
        'cuban': cuban,
        'vitolas': vitolas,
        'official': official,
        'review': review,
        'votes': votes,
        'specs': specs,
        if (dojoScore != null) 'rating': {'dojo': dojoScore},
        'aliases': aliases,
        'tubos': tubos,
      };

  String get country => cuban ? '쿠바' : '';

  /// 검색용 소문자 문자열
  late final String searchText = [
    brand,
    name,
    ...aliases,
    if (cuban) 'cuba cuban 쿠바 쿠반',
  ].join(' ').toLowerCase();
}

/// 노트 태그 사전 (assets/tags.json)
class TagDef {
  final String id;
  final String ko;
  final String en;
  final String hint;
  final String hintEn;
  final String groupId;
  final String groupKo;
  final String groupEn;
  TagDef(this.id, this.ko, this.hint, this.groupId, this.groupKo, {String? en, String? hintEn, String? groupEn})
      : en = en ?? ko,
        hintEn = hintEn ?? hint,
        groupEn = groupEn ?? groupKo;

  /// 현재 언어 이름/힌트
  String get name => L10n.isKo ? ko : en;
  String get hintText => L10n.isKo ? hint : hintEn;
  String get groupName => L10n.isKo ? groupKo : groupEn;
}

class TagGroup {
  final String id;
  final String ko;
  final String en;
  final List<TagDef> tags;
  TagGroup(this.id, this.ko, this.tags, {String? en}) : en = en ?? ko;
  String get name => L10n.isKo ? ko : en;
}
