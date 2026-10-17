import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n.dart';
import 'scan_service.dart';
import 'share_stats.dart';

/// 앱 실행 기록: installs/<익명 UID> 에 플랫폼·언어·빌드 번호·실행한 날짜들·익명 공유 켜짐 여부만.
/// 사용자 수·버전 분포·재방문 파악용 (운영자 통계). 기록·재고 내용은 안 보냄. 하루 한 번만 씀.
class Installs {
  Installs._();
  static final instance = Installs._();

  static String get platform {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
      return Platform.operatingSystem;
    } catch (_) {
      return 'unknown';
    }
  }

  /// 실행 기록 문서 id. 익명이면 UID 그대로, 로그인한(운영자) 계정은 기기가 여럿이라 플랫폼별로 나눈다.
  static String docIdFor(User u) => u.isAnonymous ? u.uid : '${u.uid}~$platform';

  /// 로그인으로 실행 기록 문서가 바뀌었을 때(UID 가 바뀌었거나, 같은 UID 라도 익명→UID~플랫폼):
  /// 이전 문서 id 를 새 문서에 "흡수됨"으로 적어 통계에서 중복으로 안 세게.
  /// (옛 문서는 권한상 클라이언트가 못 지우므로 운영자 스크립트가 나중에 정리)
  Future<void> absorb(String oldUid) async {
    if (!ScanService.instance.ready) return;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || docIdFor(u) == oldUid) return;
    try {
      final doc = FirebaseFirestore.instance.collection('installs').doc(docIdFor(u));
      await doc.set({
        'platform': platform,
        'lang': L10n.code,
        'build': int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0,
        'absorbed': FieldValue.arrayUnion([oldUid]),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 8));
      // 새 문서 기준으로 오늘 다시 핑
      final p = await SharedPreferences.getInstance();
      await p.remove('install_ping');
      await ping();
    } catch (_) {}
  }

  /// [force]: 공유 설정을 바꿨을 때처럼 오늘 이미 보냈어도 다시 보냄
  Future<void> ping({bool force = false}) async {
    if (!ScanService.instance.ready) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = docIdFor(user);
    try {
      final p = await SharedPreferences.getInstance();
      final n = DateTime.now();
      final today = '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
      final info = await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber) ?? 0;
      // 같은 날·같은 빌드면 생략
      if (!force && p.getString('install_ping') == '$today/$build') return;
      final doc = FirebaseFirestore.instance.collection('installs').doc(uid);
      final data = <String, dynamic>{
        'platform': platform,
        'lang': L10n.code,
        'build': build,
        'version': info.version,
        'last': today,
        // 실행한 날짜 목록(중복 없음) — "며칠이나 다시 들어왔나" 용. 날짜만, 시간·횟수 없음
        'days': FieldValue.arrayUnion([today]),
        // 익명 집계 공유가 켜져 있는지 — 기록이 0건인 게 "안 써서"인지 "꺼서"인지 구분용
        'share': await ShareStats.instance.enabled,
      };
      final cur = await doc.get().timeout(const Duration(seconds: 6));
      if (!cur.exists) data['first'] = today;
      await doc.set(data, SetOptions(merge: true)).timeout(const Duration(seconds: 8));
      await p.setString('install_ping', '$today/$build');
    } catch (_) {}
  }
}
