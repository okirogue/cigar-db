import 'dart:io';

import 'package:flutter/material.dart';

import '../data/photos.dart';
import '../l10n.dart';
import '../theme.dart';
import 'crop_screen.dart';

/// 재고 사진 공통: 카메라/갤러리 선택 → 틀 맞추기 → photos/ 에 저장하고 파일 이름 반환. 취소면 null.
/// (기록 사진과 같은 폴더·같은 규칙. 기기 로컬 전용, 동기화·백업 안 함)
Future<String?> pickStockPhoto(BuildContext context) async {
  final gallery = await showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(tr('사진 찍기', 'Take photo')), onTap: () => Navigator.pop(ctx, false)),
        ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(tr('갤러리에서 선택', 'Choose from gallery')), onTap: () => Navigator.pop(ctx, true)),
      ]),
    ),
  );
  if (gallery == null || !context.mounted) return null;
  try {
    final bytes = await LogPhotos.instance.pickBytes(gallery: gallery);
    if (bytes == null || !context.mounted) return null;
    final cropped = await cropPhoto(context, bytes);
    if (cropped == null) return null;
    return LogPhotos.instance.saveBytes(cropped);
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('사진을 가져오지 못했어요', 'Could not get the photo'))));
    return null;
  }
}

/// 재고 카드용 썸네일: 사진이 있으면 그 사진, 없으면 기본 시가 아이콘
class StockThumb extends StatelessWidget {
  final String? photo;
  final double size;
  final VoidCallback? onTap;
  const StockThumb({super.key, required this.photo, this.size = 44, this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = photo;
    if (name == null || name.isEmpty || !LogPhotos.supported) return CigarThumb(size: size);
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: FutureBuilder<File>(
          key: ValueKey(name),
          future: LogPhotos.instance.file(name),
          builder: (_, snap) => snap.hasData
              ? Image.file(snap.data!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => CigarThumb(size: size))
              : Container(width: size, height: size, decoration: BoxDecoration(color: C.thumb, borderRadius: BorderRadius.circular(10))),
        ),
      ),
    );
  }
}

/// 사진 크게 보기
Future<void> showStockPhoto(BuildContext context, String name, {String? title}) async {
  final f = await LogPhotos.instance.file(name);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          InteractiveViewer(child: Image.file(f, fit: BoxFit.contain)),
          if (title != null)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
        ]),
      ),
    ),
  );
}
