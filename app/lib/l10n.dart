import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱 언어(ko/en). 기본값은 폰 언어(한국어면 ko, 아니면 en), 홈 상단 토글로 바꾸면 저장.
/// 문구는 `tr('한글', 'English')` 로 인라인 번역한다.
class L10n {
  L10n._();
  static const _key = 'lang';
  static final ValueNotifier<String> lang = ValueNotifier<String>('ko');

  static bool get isKo => lang.value == 'ko';
  static String get code => lang.value;

  static Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getString(_key);
      if (saved == 'ko' || saved == 'en') {
        lang.value = saved!;
        return;
      }
    } catch (_) {}
    final device = PlatformDispatcher.instance.locale.languageCode;
    lang.value = device == 'ko' ? 'ko' : 'en';
  }

  static Future<void> set(String v) async {
    if (v != 'ko' && v != 'en') return;
    lang.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, v);
    } catch (_) {}
  }

  static Future<void> toggle() => set(isKo ? 'en' : 'ko');
}

/// 현재 언어에 맞는 문구. 보간은 양쪽에 각각 쓴다: tr('$n회', '$n times')
String tr(String ko, String en) => L10n.isKo ? ko : en;
