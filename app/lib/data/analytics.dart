import 'package:firebase_analytics/firebase_analytics.dart';

import 'scan_service.dart';

/// Google Analytics for Firebase — 사용자 수·유지율·화면 사용량만. 광고 ID 수집 안 함(매니페스트).
/// 기록 내용(시가·점수·메모)은 이벤트에 넣지 않는다.
class Analytics {
  Analytics._();
  static final instance = Analytics._();

  FirebaseAnalytics? get _a => ScanService.instance.ready ? FirebaseAnalytics.instance : null;

  /// 화면(라우트) 전환 자동 기록용
  List<NavigatorObserver> get observers => _a == null ? const [] : [FirebaseAnalyticsObserver(analytics: _a!)];

  Future<void> tab(String name) async {
    try {
      await _a?.logScreenView(screenName: name);
    } catch (_) {}
  }

  /// 기록 저장 — 내용 없이 "저장했다"만
  Future<void> logSaved({required bool fromStock, required bool edit}) async {
    try {
      await _a?.logEvent(name: edit ? 'log_edit' : 'log_add', parameters: {'from_stock': fromStock ? 1 : 0});
    } catch (_) {}
  }

  Future<void> event(String name) async {
    try {
      await _a?.logEvent(name: name);
    } catch (_) {}
  }
}
