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

  /// [force]: 공유 설정을 바꿨을 때처럼 오늘 이미 보냈어도 다시 보냄
  Future<void> ping({bool force = false}) async {
    if (!ScanService.instance.ready) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
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
