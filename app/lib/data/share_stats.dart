import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n.dart';
import '../models/local.dart';
import 'scan_service.dart';

/// 익명 기록 공유: 시가·점수·노트 태그·날짜만 서버로. 메모/장소/페어링은 절대 안 올림.
/// 문서 id = "<uid>_<logId>" 라서 수정/삭제도 같이 반영된다.
class ShareStats {
  ShareStats._();
  static final instance = ShareStats._();

  static const _key = 'share_stats'; // 없으면 기본 켜짐. 사용자가 끄면 false
  static const _noticeKey = 'share_notice_shown'; // 첫 기록 때 안내 한 번
  static const _backfilledKey = 'share_backfilled'; // 기존 기록 일괄 업로드 완료
  static const _pendingKey = 'share_pending'; // 전송 실패분: "push:<id>" / "del:<id>"
  bool? _enabled;

  /// 기본 ON. 예전에 "공유 안 함"을 골랐던 사람은 false 가 저장돼 있어 그대로 존중.
  Future<bool> get enabled async {
    if (_enabled != null) return _enabled!;
    final p = await SharedPreferences.getInstance();
    return _enabled = p.getBool(_key) ?? true;
  }

  Future<void> set(bool v) async {
    _enabled = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, v);
    if (!v) await p.remove(_backfilledKey); // 다시 켜면 전부 다시 올리게
  }

  Future<bool> get backfilled async => (await SharedPreferences.getInstance()).getBool(_backfilledKey) ?? false;

  // ---- 전송 실패분 기억 → 다음 실행 때 재시도 ----
  Future<List<String>> _pending() async => (await SharedPreferences.getInstance()).getStringList(_pendingKey) ?? const [];

  Future<void> _mark(String item, {required bool failed}) async {
    final p = await SharedPreferences.getInstance();
    final cur = (p.getStringList(_pendingKey) ?? []).toSet();
    if (failed) {
      cur.add(item);
    } else {
      cur.remove(item);
    }
    await p.setStringList(_pendingKey, cur.toList());
  }

  /// 앱 시작 시: 아직 일괄 업로드 안 했으면 전부, 했으면 실패분만 재시도. 공유 꺼져 있으면 아무것도 안 함.
  Future<void> syncOnStart(List<SmokeLog> logs) async {
    if (!await enabled || !ScanService.instance.ready) return;
    if (!await backfilled) {
      await backfill(logs);
      return;
    }
    final pend = await _pending();
    if (pend.isEmpty) return;
    final byId = {for (final l in logs) l.id: l};
    for (final item in pend) {
      final id = int.tryParse(item.split(':').last);
      if (id == null) continue;
      if (item.startsWith('push:')) {
        final l = byId[id];
        if (l == null) {
          await _mark(item, failed: false); // 그새 지워진 기록
        } else {
          await push(l);
        }
      } else if (item.startsWith('del:')) {
        await remove(id);
      }
    }
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
        'lang': L10n.code, // 기록 당시 앱 언어 (ko/en) — 한국/글로벌 사용자 구분용
        'updated': FieldValue.serverTimestamp(),
      };

  /// 저장/수정 후 호출. 꺼져 있으면 무시. 실패하면 기억해 뒀다가 다음 실행 때 재시도.
  Future<void> push(SmokeLog l) async {
    if (!await enabled) return;
    final uid = _uid;
    if (!ScanService.instance.ready || uid == null) {
      await _mark('push:${l.id}', failed: true);
      return;
    }
    try {
      await _col.doc('${uid}_${l.id}').set(_doc(l, uid)).timeout(const Duration(seconds: 8));
      await _mark('push:${l.id}', failed: false);
    } catch (_) {
      await _mark('push:${l.id}', failed: true);
    }
  }

  Future<void> remove(int logId) async {
    if (!await enabled) return;
    await _mark('push:$logId', failed: false);
    final uid = _uid;
    if (!ScanService.instance.ready || uid == null) {
      await _mark('del:$logId', failed: true);
      return;
    }
    try {
      await _col.doc('${uid}_$logId').delete().timeout(const Duration(seconds: 8));
      await _mark('del:$logId', failed: false);
    } catch (_) {
      await _mark('del:$logId', failed: true);
    }
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

  /// 기존 기록 전부 올리기 (처음 켤 때·앱 설치 후 첫 실행·점수 스케일 변경 때). 성공하면 완료 표시.
  Future<void> backfill(List<SmokeLog> logs) async {
    if (!await enabled || !ScanService.instance.ready) return;
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
      final p = await SharedPreferences.getInstance();
      await p.setBool(_backfilledKey, true);
      await p.remove(_pendingKey);
    } catch (_) {}
  }

  /// 카페 평점: 이 시가의 공유된 기록 집계 (평균·인원·많이 느낀 노트). 서버 안 되면 null.
  Future<CafeStats?> fetch(String cigarId) async {
    if (!ScanService.instance.ready) return null;
    try {
      final q = await _col.where('cigar_id', isEqualTo: cigarId).limit(500).get().timeout(const Duration(seconds: 8));
      if (q.docs.isEmpty) return CafeStats(0, 0, 0, const {});
      final users = <String>{};
      var sum = 0.0;
      final tagCount = <String, int>{};
      for (final d in q.docs) {
        final m = d.data();
        users.add(m['uid'] as String? ?? d.id);
        var sc = (m['score'] as num?)?.toDouble() ?? 0;
        if (sc > 10) sc = (sc / 5).round() / 2; // 옛 100점 문서 호환
        sum += sc;
        for (final t in (m['tags'] as List? ?? const [])) {
          tagCount[t as String] = (tagCount[t] ?? 0) + 1;
        }
      }
      return CafeStats(q.docs.length, users.length, sum / q.docs.length, tagCount);
    } catch (_) {
      return null;
    }
  }

  /// 처음 기록 저장할 때 안내 한 번 (선택지 없음 — 기본 켜짐, 다이어리 ⋮에서 끌 수 있음)
  Future<void> noticeIfNeeded(BuildContext context) async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_noticeKey) ?? false) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(tr('기록은 익명으로 집계돼요', 'Logs are counted anonymously')),
        content: Text(
          tr(
            '커뮤니티 평점(평균 점수·많이 느낀 노트)을 만들기 위해, 기록을 저장할 때 아래 항목만 익명으로 모아요.\n\n'
            '• 보내는 것: 시가 이름, 점수, 체크한 노트 태그, 날짜\n'
            '• 안 보내는 것: 메모(초반/중반/후반), 장소, 페어링, 사진, 휴미더, 이름·이메일 등 개인정보\n\n'
            '원하지 않으면 다이어리 메뉴(⋮)에서 언제든 끌 수 있고, 끄면 올라간 내 기록도 지워져요.',
            'To build community ratings (average score, common notes), only the items below are collected anonymously when you save a log.\n\n'
            '• Sent: cigar name, score, checked note tags, date\n'
            '• Not sent: memo (first/second/final third), place, pairing, photos, humidor, or personal info like name or email\n\n'
            'You can turn this off anytime from the Diary menu (⋮); turning it off also deletes your uploaded logs.',
          ),
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('확인', 'OK'))),
        ],
      ),
    );
    await p.setBool(_noticeKey, true);
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
