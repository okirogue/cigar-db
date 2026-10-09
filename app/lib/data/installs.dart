import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n.dart';
import 'scan_service.dart';

/// 앱 실행 기록: installs/<익명 UID> 에 플랫폼·언어·빌드 번호·마지막 실행일만.
/// 사용자 수·버전 분포 파악용 (운영자 통계). 기록·재고 내용은 안 보냄. 하루 한 번만 씀.
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

  Future<void> ping() async {
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
      if (p.getString('install_ping') == '$today/$build') return;
      final doc = FirebaseFirestore.instance.collection('installs').doc(uid);
      final data = <String, dynamic>{
        'platform': platform,
        'lang': L10n.code,
        'build': build,
        'version': info.version,
        'last': today,
      };
      final cur = await doc.get().timeout(const Duration(seconds: 6));
      if (!cur.exists) data['first'] = today;
      await doc.set(data, SetOptions(merge: true)).timeout(const Duration(seconds: 8));
      await p.setString('install_ping', '$today/$build');
    } catch (_) {}
  }
}
