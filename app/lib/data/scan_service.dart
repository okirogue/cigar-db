import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../firebase_web_options.dart';

/// Firebase 부트스트랩 (초기화 + 익명 로그인). 공유 집계·동기화·제안·실행 기록이 `ready` 를 본다.
///
/// 이름은 처음 밴드 스캔(Gemini) 기능용으로 만들어 붙은 것 — 스캔 UI 는 b52 에서 제거됐고
/// (firebase_ai·image 의존성 삭제, 코드는 git 이력에), 이 클래스는 Firebase 준비 여부만 담당한다.
class ScanService {
  ScanService._();
  static final ScanService instance = ScanService._();

  bool _ready = false;
  String? _error;

  bool get ready => _ready;
  String? get error => _error;

  /// 앱 시작 시 한 번. 실패해도 앱은 돌아가게 (온라인 기능만 비활성).
  Future<void> init() async {
    try {
      await Firebase.initializeApp(options: kIsWeb ? firebaseWebOptions : null);
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      _ready = true;
    } catch (e) {
      _error = e.toString();
      _ready = false;
    }
  }
}
