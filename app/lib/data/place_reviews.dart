import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n.dart';
import 'installs.dart';
import 'scan_service.dart';

/// 장소 별점·코멘트 한 건 (Firestore place_reviews, 문서 id = "<uid>_<placeId>" — 한 사람당 장소마다 하나, 다시 쓰면 수정)
class PlaceReview {
  final String placeId;
  final String uid;
  final int rating; // 1~5
  final String comment;
  final String lang;
  final DateTime? updated;
  PlaceReview(this.placeId, this.uid, this.rating, this.comment, this.lang, this.updated);

  static PlaceReview? fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    if (m == null) return null;
    final ts = m['updated'];
    return PlaceReview(
      (m['place_id'] ?? '') as String,
      (m['uid'] ?? '') as String,
      (m['rating'] as num?)?.toInt() ?? 0,
      (m['comment'] ?? '') as String,
      (m['lang'] ?? '') as String,
      ts is Timestamp ? ts.toDate() : null,
    );
  }
}

/// 장소 리뷰 저장소: 앱 시작 때 전부 한 번 받아 두고(작음), 쓰면 그 장소만 다시 받는다.
class PlaceReviews extends ChangeNotifier {
  PlaceReviews._();
  static final instance = PlaceReviews._();

  static const minForAverage = 3; // 평균 별점은 3명부터 숫자로

  final Map<String, List<PlaceReview>> _byPlace = {};
  bool _loaded = false;
  bool get loaded => _loaded;

  CollectionReference<Map<String, dynamic>> get _col => FirebaseFirestore.instance.collection('place_reviews');
  String? get _uid => ScanService.instance.ready ? FirebaseAuth.instance.currentUser?.uid : null;

  List<PlaceReview> of(String placeId) => List.unmodifiable(_byPlace[placeId] ?? const []);

  /// (평균, 인원). 인원이 [minForAverage] 미만이면 평균은 null.
  (double?, int) summary(String placeId) {
    final l = _byPlace[placeId] ?? const [];
    if (l.isEmpty) return (null, 0);
    final rated = l.where((r) => r.rating > 0).toList();
    if (rated.length < minForAverage) return (null, rated.length);
    return (rated.map((r) => r.rating).reduce((a, b) => a + b) / rated.length, rated.length);
  }

  PlaceReview? mine(String placeId) {
    final u = _uid;
    if (u == null) return null;
    for (final r in _byPlace[placeId] ?? const <PlaceReview>[]) {
      if (r.uid == u) return r;
    }
    return null;
  }

  Future<void> loadAll() async {
    if (!ScanService.instance.ready) return;
    try {
      final snap = await _col.get(const GetOptions(source: Source.serverAndCache)).timeout(const Duration(seconds: 10));
      _byPlace.clear();
      for (final d in snap.docs) {
        final r = PlaceReview.fromDoc(d);
        if (r != null && r.placeId.isNotEmpty) _byPlace.putIfAbsent(r.placeId, () => []).add(r);
      }
      for (final l in _byPlace.values) {
        l.sort((a, b) => (b.updated ?? DateTime(0)).compareTo(a.updated ?? DateTime(0)));
      }
      _loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('PlaceReviews.loadAll: $e');
    }
  }

  Future<void> refresh(String placeId) async {
    if (!ScanService.instance.ready) return;
    try {
      final snap = await _col.where('place_id', isEqualTo: placeId).get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 10));
      final l = [for (final d in snap.docs) PlaceReview.fromDoc(d)].whereType<PlaceReview>().toList()
        ..sort((a, b) => (b.updated ?? DateTime(0)).compareTo(a.updated ?? DateTime(0)));
      _byPlace[placeId] = l;
      notifyListeners();
    } catch (e) {
      debugPrint('PlaceReviews.refresh: $e');
    }
  }

  /// 내 리뷰 쓰기/수정. 실패하면 throw.
  Future<void> submit(String placeId, int rating, String comment) async {
    final u = _uid;
    if (u == null) throw StateError('offline');
    final info = await PackageInfo.fromPlatform();
    await _col.doc('${u}_$placeId').set({
      'uid': u,
      'place_id': placeId,
      'rating': rating,
      'comment': comment,
      'lang': L10n.code,
      'platform': Installs.platform,
      'build': int.tryParse(info.buildNumber) ?? 0,
      'updated': FieldValue.serverTimestamp(),
    }).timeout(const Duration(seconds: 10));
    await refresh(placeId);
  }

  /// 내 리뷰 삭제
  Future<void> remove(String placeId) async {
    final u = _uid;
    if (u == null) return;
    await _col.doc('${u}_$placeId').delete().timeout(const Duration(seconds: 10));
    await refresh(placeId);
  }
}
