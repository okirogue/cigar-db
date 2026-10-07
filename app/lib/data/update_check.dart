import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// GitHub Releases 최신 버전 확인. 태그 형식: v0.1.0-b123 (b 뒤가 빌드 번호)
class UpdateInfo {
  final String tag;
  final int build;
  final String notes;
  final String apkUrl;
  UpdateInfo(this.tag, this.build, this.notes, this.apkUrl);
}

class UpdateCheck {
  static const repo = 'okirogue/cigar-db';
  static const apkUrl = 'https://github.com/$repo/releases/latest/download/MyHumidor.apk';

  /// 새 버전 있으면 UpdateInfo, 없거나 실패하면 null
  static Future<UpdateInfo?> check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final mine = int.tryParse(info.buildNumber) ?? 0;
      final r = await http.get(Uri.parse('https://api.github.com/repos/$repo/releases/latest'), headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final tag = (j['tag_name'] ?? '') as String;
      final m = RegExp(r'-b(\d+)$').firstMatch(tag);
      if (m == null) return null;
      final build = int.parse(m.group(1)!);
      if (build <= mine) return null;
      return UpdateInfo(tag, build, (j['body'] ?? '') as String, apkUrl);
    } catch (_) {
      return null;
    }
  }
}
