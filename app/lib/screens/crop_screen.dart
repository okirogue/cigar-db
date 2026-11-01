import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';

/// 사진 틀 맞추기: 고정 비율(16:9) 틀 안에서 사진을 밀고 확대해 원하는 부분을 고른다.
/// 확인하면 틀 안 영역만 JPEG 바이트로 돌려주고, 취소하면 null.
const photoAspect = 16 / 9;

Future<Uint8List?> cropPhoto(BuildContext context, Uint8List bytes) {
  return Navigator.push<Uint8List>(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => _CropScreen(bytes)));
}

class _CropScreen extends StatefulWidget {
  final Uint8List bytes;
  const _CropScreen(this.bytes);
  @override
  State<_CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<_CropScreen> {
  final _ctl = CropController();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(tr('사진 틀 맞추기', 'Adjust photo'), style: const TextStyle(fontSize: 17, color: Colors.white)),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    setState(() => _busy = true);
                    _ctl.crop();
                  },
            child: Text(_busy ? tr('처리 중…', 'Working…') : tr('완료', 'Done'), style: const TextStyle(color: C.gold, fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Crop(
            image: widget.bytes,
            controller: _ctl,
            aspectRatio: photoAspect,
            interactive: true, // 틀은 고정, 사진을 밀고 확대
            fixCropRect: true,
            baseColor: Colors.black,
            maskColor: Colors.black.withValues(alpha: 0.6),
            cornerDotBuilder: (_, __) => const SizedBox.shrink(),
            onCropped: (result) {
              if (!mounted) return;
              switch (result) {
                case CropSuccess(:final croppedImage):
                  Navigator.pop(context, croppedImage);
                case CropFailure():
                  setState(() => _busy = false);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('사진을 자르지 못했어요', 'Could not crop the photo'))));
              }
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Text(tr('두 손가락으로 확대하고 끌어서 원하는 부분을 틀에 맞춰 주세요', 'Pinch to zoom and drag to fit the part you want inside the frame'),
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ),
      ]),
    );
  }
}
