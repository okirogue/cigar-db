import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/local.dart';
import 'scan_service.dart';

/// 익명 기록 공유: 시가·점수·노트 태그·날짜만 서버로. 메모/장소/페어링은 절대 안 올림.
/// 문서 id = "<uid>_<logId>" 라서 수정/삭제도 같이 반영된다.
class ShareStats {
  ShareStats._();
  static final instance = ShareStats._();

  static const _key = 'share_stats'; // null=아직 안 물어봄, true/false
  bool? _enabled;

  Future<bool?> get enabled async {
    if (_enabled != null) return _enabled;
    final p = await SharedPreferences.getInstance();
    return _enabled = p.containsKey(_key) ? p.getBool(_key) : null;
  }

  Future<void> set(bool v) async {
    _enabled = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, v);
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  CollectionReference<Map<String, dynamic>> get _col => FirebaseFirestore.instance.collection('log_stats');

  Map<String, dynamic> _doc(SmokeLog l, String uid) => {
        'uid': uid,
        'log_id': l.id,
        'cigar_id': l.cigarId,
        'cigar_name': l.cigarName,
        'vitola': l.vitola ?? '',
        'date': l.date,
        'score': l.score,
        'tags': l.tags,
        'updated': FieldValue.serverTimestamp(),
      };

  /// 저장/수정 후 호출. 꺼져 있거나 서버 안 되면 조용히 무시.
  Future<void> push(SmokeLog l) async {
    if (await enabled != true || !ScanService.instance.ready) return;
    final uid = _uid;
    if (uid == null) return;
    try {
      await _col.doc('${uid}_${l.id}').set(_doc(l, uid)).timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  Future<void> remove(int logId) async {
    if (await enabled != true || !ScanService.instance.ready) return;
    final uid = _uid;
    if (uid == null) return;
    try {
      await _col.doc('${uid}_$logId').delete().timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  /// 공유를 끌 때: 설정과 무관하게 서버 문서 삭제
  Future<void> removeForce(int logId) async {
    if (!ScanService.instance.ready) return;
    final uid = _uid;
    if (uid == null) return;
    try {
      await _col.doc('${uid}_$logId').delete().timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  /// 켠 직후 기존 기록 전부 올리기
  Future<void> backfill(List<SmokeLog> logs) async {
    if (await enabled != true || !ScanService.instance.ready) return;
    final uid = _uid;
    if (uid == null) return;
    try {
      // 400개 단위 배치 (한도 500)
      for (var i = 0; i < logs.length; i += 400) {
        final b = FirebaseFirestore.instance.batch();
        for (final l in logs.skip(i).take(400)) {
          b.set(_col.doc('${uid}_${l.id}'), _doc(l, uid));
        }
        await b.commit().timeout(const Duration(seconds: 20));
      }
    } catch (_) {}
  }

  /// 카페 평점: 이 시가의 공유된 기록 집계 (평균·인원·많이 느낀 노트). 서버 안 되면 null.
  Future<CafeStats?> fetch(String cigarId) async {
    if (!ScanService.instance.ready) return null;
    try {
      final q = await _col.where('cigar_id', isEqualTo: cigarId).limit(500).get().timeout(const Duration(seconds: 8));
      if (q.docs.isEmpty) return CafeStats(0, 0, 0, const {});
      final users = <String>{};
      var sum = 0;
      final tagCount = <String, int>{};
      for (final d in q.docs) {
        final m = d.data();
        users.add(m['uid'] as String? ?? d.id);
        sum += (m['score'] as num?)?.toInt() ?? 0;
        for (final t in (m['tags'] as List? ?? const [])) {
          tagCount[t as String] = (tagCount[t] ?? 0) + 1;
        }
      }
      return CafeStats(q.docs.length, users.length, sum / q.docs.length, tagCount);
    } catch (_) {
      return null;
    }
  }

  /// 처음 기록 저장할 때 한 번 묻기. 이미 답했으면 바로 true 반환.
  Future<bool> askIfNeeded(BuildContext context) async {
    if (await enabled != null) return true;
    if (!context.mounted) return true;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('기록을 익명으로 공유할까요?'),
        content: const Text(
          '카페 회원들의 평균 점수·많이 느낀 노트 같은 통계를 만들기 위해, 기록을 저장할 때 아래 항목만 익명으로 모아요.\n\n'
          '• 보내는 것: 시가 이름, 점수, 체크한 노트 태그, 날짜\n'
          '• 안 보내는 것: 메모(초반/중반/후반), 장소, 페어링, 이름·이메일 등 개인정보\n\n'
          '다이어리 메뉴(⋮)에서 언제든 끄고 켤 수 있어요.',
          style: TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('공유 안 함')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('익명 공유')),
        ],
      ),
    );
    await set(ok ?? false);
    return true;
  }
}

class CafeStats {
  final int logs; // 기록 수
  final int people; // 사람 수(익명 ID 기준)
  final double avg;
  final Map<String, int> tagCount;
  CafeStats(this.logs, this.people, this.avg, this.tagCount);

  /// 2명 이상이 느낀 노트 우선, 많이 나온 순
  List<String> topTags(int n) {
    final e = tagCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return e.take(n).map((x) => x.key).toList();
  }
}
