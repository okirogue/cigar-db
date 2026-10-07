import 'package:firebase_core/firebase_core.dart';

/// 웹 빌드용 Firebase 설정 (Firebase 콘솔 > 프로젝트 설정 > 내 앱 > MyHumidor Web).
/// 웹 API 키는 공개되는 값이라 저장소에 둬도 됨 — 접근 제어는 Firestore 규칙이 담당.
const firebaseWebOptions = FirebaseOptions(
  apiKey: 'AIzaSyBn4LhCuOJ0rxYbOP3YEcj4Mtr2tChIwh8',
  authDomain: 'myhumidor-2482d.firebaseapp.com',
  projectId: 'myhumidor-2482d',
  storageBucket: 'myhumidor-2482d.firebasestorage.app',
  messagingSenderId: '878079125373',
  appId: '1:878079125373:web:d464b29ef0ee61b6de0e14',
  measurementId: 'G-XWST8N7RPJ',
);
