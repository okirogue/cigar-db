import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';

/// 사진 틀 맞추기: 박스 모서리를 끌어 크기·비율을 자유롭게 바꾸고(갤러리처럼), 원하면 1:1·4:3·16:9·9:16 고정.
/// 확인하면 박스 안 영역만 돌려주고, 취소하면 null.

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
  double? _aspect; // null = 자유

  static const _presets = <(String, double?)>[('자유', null), ('1:1', 1.0), ('4:3', 4 / 3), ('16:9', 16 / 9), ('9:16', 9 / 16)];

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
            aspectRatio: _aspect,
            initialRectBuilder: InitialRectBuilder.withSizeAndRatio(size: 0.92, aspectRatio: _aspect),
            baseColor: Colors.black,
            maskColor: Colors.black.withValues(alpha: 0.6),
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
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 8, children: [
                for (final (label, a) in _presets)
                  ChoiceChip(
                    label: Text(label == '자유' ? tr('자유', 'Free') : label, style: TextStyle(fontSize: 12, color: _aspect == a ? Colors.black : Colors.white)),
                    selected: _aspect == a,
                    selectedColor: C.gold,
                    backgroundColor: Colors.white12,
                    side: BorderSide.none,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      _aspect = a;
                      _ctl.aspectRatio = a;
                    }),
                  ),
              ]),
              const SizedBox(height: 8),
              Text(tr('박스 모서리를 끌어 크기를 바꾸고, 박스를 옮겨 원하는 부분을 골라주세요', 'Drag the corners to resize the box and move it over the part you want'),
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
        ),
      ]),
    );
  }
}
