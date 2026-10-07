import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 기록 사진: 앱 문서 폴더의 photos/ 아래에 파일로만 저장 (서버 전송 없음).
/// DB 에는 파일 이름만 콤마로 이어 붙여 둔다.
class LogPhotos {
  LogPhotos._();
  static final instance = LogPhotos._();

  /// 웹에선 파일 저장소가 없어 사진 기능을 숨긴다 (추후 IndexedDB 저장으로 확장 가능)
  static bool get supported => !kIsWeb;

  Directory? _dir;

  Future<Directory> get dir async {
    if (_dir != null) return _dir!;
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'photos'));
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  Future<File> file(String name) async => File(p.join((await dir).path, name));

  /// 카메라 촬영 또는 갤러리 선택 → 리사이즈된 사본을 photos/ 에 저장하고 파일 이름 반환. 취소하면 null.
  Future<String?> pick({bool gallery = false}) async {
    final x = await ImagePicker().pickImage(
      source: gallery ? ImageSource.gallery : ImageSource.camera,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (x == null) return null;
    final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final dest = p.join((await dir).path, name);
    await File(x.path).copy(dest);
    try {
      await File(x.path).delete(); // 캐시 사본 정리
    } catch (_) {}
    return name;
  }

  Future<void> delete(String name) async {
    try {
      final f = await file(name);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> deleteAll(Iterable<String> names) async {
    for (final n in names) {
      await delete(n);
    }
  }
}

/// "a.jpg,b.jpg" ↔ ["a.jpg","b.jpg"]
List<String> splitPhotos(String? s) => (s ?? '').split(',').where((e) => e.isNotEmpty).toList();
String joinPhotos(List<String> l) => l.join(',');
