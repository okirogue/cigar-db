import 'dart:math';

/// 시가를 피울 수 있는 장소 (db/places.json 한 항목). 운영자 검수를 거친 것만 들어온다.
class Place {
  final String id;
  final String name; // 현지어 상호명
  final String nameEn; // 영문 표기 (없으면 name)
  final List<String> kinds; // bar | lounge | cafe
  final List<String> smoking; // indoor | outdoor
  final String sells; // yes | no | unknown
  final String country; // ISO 2자리 (KR, US, ID …)
  final String city; // 표시용 도시 (ko)
  final String cityEn;
  final double lat, lng;
  final String? mapsUrl; // 구글맵 링크 (없으면 좌표로 연다)
  final String note; // 운영자 메모 (ko)
  final String noteEn;
  final double? rating; // 3명 이상일 때만 값
  final int ratingCount;

  Place({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.kinds,
    required this.smoking,
    required this.sells,
    required this.country,
    required this.city,
    required this.cityEn,
    required this.lat,
    required this.lng,
    this.mapsUrl,
    this.note = '',
    this.noteEn = '',
    this.rating,
    this.ratingCount = 0,
  });

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        id: j['id'] as String,
        name: j['name'] as String,
        nameEn: (j['name_en'] ?? j['name']) as String,
        kinds: List<String>.from(j['kinds'] ?? const []),
        smoking: List<String>.from(j['smoking'] ?? const []),
        sells: (j['sells'] ?? 'unknown') as String,
        country: j['country'] as String,
        city: j['city'] as String,
        cityEn: (j['city_en'] ?? j['city']) as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        mapsUrl: j['maps_url'] as String?,
        note: (j['note'] ?? '') as String,
        noteEn: (j['note_en'] ?? j['note'] ?? '') as String,
        rating: (j['rating'] as num?)?.toDouble(),
        ratingCount: (j['rating_count'] as num?)?.toInt() ?? 0,
      );

  /// 구글맵 열기 URL (앱 설치돼 있으면 앱으로, 아니면 웹)
  String get mapsLink => mapsUrl ?? 'https://www.google.com/maps/search/?api=1&query=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

  /// 두 좌표 사이 거리 (km, 하버사인)
  double distanceKm(double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat), dLng = _rad(lng2 - lng);
    final a = sin(dLat / 2) * sin(dLat / 2) + cos(_rad(lat)) * cos(_rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return 2 * r * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double d) => d * pi / 180;
}

/// 국가 코드 → 표시 이름
const countryNames = <String, (String, String)>{
  'KR': ('한국', 'Korea'),
  'US': ('미국', 'United States'),
  'JP': ('일본', 'Japan'),
  'ID': ('인도네시아', 'Indonesia'),
  'TH': ('태국', 'Thailand'),
  'VN': ('베트남', 'Vietnam'),
  'SG': ('싱가포르', 'Singapore'),
  'HK': ('홍콩', 'Hong Kong'),
  'TW': ('대만', 'Taiwan'),
  'PH': ('필리핀', 'Philippines'),
  'MY': ('말레이시아', 'Malaysia'),
  'CN': ('중국', 'China'),
  'AE': ('UAE', 'UAE'),
  'GB': ('영국', 'United Kingdom'),
  'FR': ('프랑스', 'France'),
  'DE': ('독일', 'Germany'),
  'ES': ('스페인', 'Spain'),
  'IT': ('이탈리아', 'Italy'),
  'CH': ('스위스', 'Switzerland'),
  'CA': ('캐나다', 'Canada'),
  'MX': ('멕시코', 'Mexico'),
  'CU': ('쿠바', 'Cuba'),
  'DO': ('도미니카', 'Dominican Republic'),
  'NI': ('니카라과', 'Nicaragua'),
  'AU': ('호주', 'Australia'),
};
