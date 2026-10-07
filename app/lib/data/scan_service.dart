import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cigar.dart';
import 'cigar_repo.dart';

/// 밴드 사진 → Gemini → 시가 후보. 하루 3회(기기별, Firestore 카운터).
class ScanService {
  ScanService._();
  static final ScanService instance = ScanService._();

  static const dailyLimit = 3;

  /// 시도 순서. 첫 번째가 안 되면 다음으로.
  static const _modelCandidates = ['gemini-3.8-flash', 'gemini-3.5-flash-lite', 'gemini-flash-latest', 'gemini-2.5-flash'];
  bool _ready = false;
  String? _error;

  bool get ready => _ready;
  String? get error => _error;

  /// 앱 시작 시 한 번. 실패해도 앱은 돌아가게 (스캔만 비활성).
  Future<void> init() async {
    try {
      await Firebase.initializeApp();
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      _ready = true;
    } catch (e) {
      _error = e.toString();
      _ready = false;
    }
  }

  String get _today {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  DocumentReference<Map<String, dynamic>> get _quotaDoc => FirebaseFirestore.instance.collection('scan_quota').doc(FirebaseAuth.instance.currentUser!.uid);

  // ---- 로컬 백업 카운터 (서버에 못 붙을 때) ----
  Future<int> _localCount() async {
    final p = await SharedPreferences.getInstance();
    if (p.getString('scan_date') != _today) return 0;
    return p.getInt('scan_count') ?? 0;
  }

  Future<void> _localSet(int n) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('scan_date', _today);
    await p.setInt('scan_count', n);
  }

  /// 오늘 남은 횟수 (서버 우선, 실패 시 로컬)
  Future<int> remaining() async {
    if (!_ready) return 0;
    try {
      final d = await _quotaDoc.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 6));
      final m = d.data();
      final used = (m == null || m['date'] != _today) ? 0 : ((m['count'] as num?)?.toInt() ?? 0);
      await _localSet(used); // 로컬도 동기화
      return (dailyLimit - used).clamp(0, dailyLimit);
    } catch (_) {
      return (dailyLimit - await _localCount()).clamp(0, dailyLimit);
    }
  }

  /// 카운터 +1. 서버 트랜잭션 실패(네트워크 등)면 로컬 카운터로 대체. 한도 넘으면 false.
  Future<bool> _consume() async {
    try {
      final ok = await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(_quotaDoc);
        final m = snap.data();
        var count = 0;
        if (m != null && m['date'] == _today) count = (m['count'] as num?)?.toInt() ?? 0;
        if (count >= dailyLimit) return false;
        tx.set(_quotaDoc, {'date': _today, 'count': count + 1, 'updated': FieldValue.serverTimestamp()});
        await _localSet(count + 1);
        return true;
      }).timeout(const Duration(seconds: 8));
      return ok;
    } catch (_) {
      final n = await _localCount();
      if (n >= dailyLimit) return false;
      await _localSet(n + 1);
      return true;
    }
  }

  /// 서버 실패(붐빔)로 인식을 못 했을 때 카운트 되돌리기 (best-effort)
  Future<void> _refund() async {
    final n = await _localCount();
    if (n > 0) await _localSet(n - 1);
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(_quotaDoc);
        final m = snap.data();
        if (m == null || m['date'] != _today) return;
        final c = (m['count'] as num?)?.toInt() ?? 0;
        if (c > 0) tx.update(_quotaDoc, {'count': c - 1});
      }).timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  /// 카메라로 찍기 / 갤러리에서 고르기 → 리사이즈된 JPEG 바이트 (취소하면 null)
  Future<Uint8List?> takePhoto({bool gallery = false}) async {
    final x = await ImagePicker().pickImage(source: gallery ? ImageSource.gallery : ImageSource.camera, maxWidth: 1280, imageQuality: 85);
    if (x == null) return null;
    final bytes = await x.readAsBytes();
    // 혹시 큰 경우 한 번 더 축소 (Gemini 비용·속도)
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final resized = decoded.width > 1024 ? img.copyResize(decoded, width: 1024) : decoded;
    return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
  }

  /// 밴드 인식. 반환: 후보 시가 목록(유사도순) + 모델이 읽은 텍스트.
  Future<ScanResult> recognize(Uint8List jpeg, CigarRepo repo) async {
    if (!_ready) throw ScanException('스캔 서버에 연결되지 않았어요. 네트워크를 확인해 주세요.');
    if (!await _consume()) throw ScanException('오늘 스캔 $dailyLimit회를 다 썼어요. 내일 다시 열려요.');

    const prompt = '''
This is a photo of a cigar band (or a cigar box / tube). Read the brand and line name.
Return ONLY JSON: {"brand": string, "line": string, "vitola": string|null, "country": string|null, "confidence": 0-1, "raw_text": string}
- "brand" is the maker (e.g. "Romeo y Julieta", "Davidoff", "Oliva"). "line" is the series/blend (e.g. "Romeo No.1", "Serie V Melanio", "Signature").
- Use the common English retail spelling. If unsure, give your best guess and lower confidence.
- raw_text: all legible text on the band.''';
    // 모델 이름은 Google이 자주 바꾸므로(2.5-flash 신규 사용자 차단 등) 순서대로 시도.
    final content = [
      Content.multi([TextPart(prompt), InlineDataPart('image/jpeg', jpeg)])
    ];
    String? text;
    Object? lastErr;
    var busy = false;
    outer:
    for (final name in _modelCandidates) {
      // 같은 모델로 최대 2번 (바쁠 때 2초 쉬고 한 번 더)
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final model = FirebaseAI.googleAI().generativeModel(
            model: name,
            generationConfig: GenerationConfig(responseMimeType: 'application/json', temperature: 0.1),
          );
          final res = await model.generateContent(content).timeout(const Duration(seconds: 40));
          text = res.text ?? '{}';
          break outer;
        } catch (e) {
          lastErr = e;
          final msg = e.toString().toLowerCase();
          final isBusy = msg.contains('busy') || msg.contains('overloaded') || msg.contains('503') || msg.contains('unavailable') || msg.contains('429') || msg.contains('resource') || msg.contains('quota');
          final modelIssue = msg.contains('not found') || msg.contains('no longer available') || msg.contains('not supported') || msg.contains('deprecated') || msg.contains('404');
          if (isBusy) {
            busy = true;
            if (attempt == 0) {
              await Future.delayed(const Duration(seconds: 2));
              continue; // 같은 모델 재시도
            }
            break; // 다음 모델로
          }
          if (modelIssue) break; // 다음 모델로
          break outer; // 네트워크 등 → 중단
        }
      }
    }
    if (text == null) {
      if (busy) {
        await _refund();
        throw ScanException('지금 인식 서버가 붐벼요. 잠시 후 다시 시도해 주세요. (이번 시도는 횟수에서 차감되지 않아요)');
      }
      final m = lastErr.toString();
      throw ScanException(m.length > 160 ? '${m.substring(0, 160)}…' : m);
    }
    Map<String, dynamic> j;
    try {
      j = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw ScanException('밴드를 읽지 못했어요. 더 밝은 곳에서 밴드가 정면으로 보이게 찍어주세요.');
    }
    final brand = (j['brand'] ?? '').toString().trim();
    final line = (j['line'] ?? '').toString().trim();
    final conf = (j['confidence'] as num?)?.toDouble() ?? 0;

    // DB 매칭: 브랜드+라인 → 브랜드만 → 원문 단어
    var cands = repo.search('$brand $line', limit: 8);
    if (cands.isEmpty && brand.isNotEmpty) cands = repo.search(brand, limit: 12);
    if (cands.isEmpty) {
      final words = (j['raw_text'] ?? '').toString().split(RegExp(r'[^A-Za-z0-9]+')).where((w) => w.length > 3).take(3).join(' ');
      if (words.isNotEmpty) cands = repo.search(words, limit: 8);
    }
    return ScanResult(brand: brand, line: line, vitola: j['vitola']?.toString(), confidence: conf, candidates: cands, rawText: j['raw_text']?.toString() ?? '');
  }
}

class ScanResult {
  final String brand;
  final String line;
  final String? vitola;
  final double confidence;
  final List<Cigar> candidates;
  final String rawText;
  ScanResult({required this.brand, required this.line, this.vitola, required this.confidence, required this.candidates, required this.rawText});

  String get readName => [brand, line].where((s) => s.isNotEmpty).join(' ');
}

class ScanException implements Exception {
  final String message;
  ScanException(this.message);
  @override
  String toString() => message;
}
