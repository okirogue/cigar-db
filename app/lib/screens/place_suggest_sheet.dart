import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/installs.dart';
import '../data/scan_service.dart';
import '../l10n.dart';
import '../theme.dart';

/// 장소 제안 (시가 바·라운지·흡연 가능 카페). 운영자 검수 후 목록에 올라간다. 익명 전송.
/// 위치는 "현재 위치 첨부"를 누를 때만 권한을 받고, 제안 한 건에만 붙여 보낸다 (앱에 저장 안 함).
Future<bool?> suggestPlace(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _PlaceForm(),
  );
}

class _PlaceForm extends StatefulWidget {
  const _PlaceForm();
  @override
  State<_PlaceForm> createState() => _PlaceFormState();
}

class _PlaceFormState extends State<_PlaceForm> {
  final _name = TextEditingController();
  final _comment = TextEditingController();
  final _kinds = <String>{};
  final _smoking = <String>{};
  String _sells = 'unknown';
  int _rating = 0;
  Position? _pos;
  bool _locating = false;
  String? _locError;
  bool _sending = false;

  @override
  void dispose() {
    _name.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locError = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw tr('기기의 위치 서비스가 꺼져 있어요', 'Location services are turned off');
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw tr('위치 권한이 없어 첨부하지 못했어요 (없어도 제안은 보낼 수 있어요)', 'Location permission denied (you can still submit without it)');
      }
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 12)));
      setState(() => _pos = p);
    } catch (e) {
      setState(() => _locError = e is String ? e : tr('위치를 가져오지 못했어요', 'Could not get location'));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _send() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('상호명을 넣어주세요', 'Please enter the place name'))));
      return;
    }
    if (_kinds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('유형을 하나 이상 골라주세요', 'Pick at least one type'))));
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (!ScanService.instance.ready || uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('지금은 서버에 연결되지 않아요. 잠시 후 다시 시도해 주세요.', 'Not connected right now. Please try again later.'))));
      return;
    }
    setState(() => _sending = true);
    try {
      final info = await PackageInfo.fromPlatform();
      await FirebaseFirestore.instance.collection('place_suggestions').add({
        'uid': uid,
        'name': name,
        'kinds': _kinds.toList()..sort(),
        'smoking': _smoking.toList()..sort(),
        'sells': _sells,
        'comment': _comment.text.trim(),
        'rating': _rating,
        if (_pos != null) 'lat': _pos!.latitude,
        if (_pos != null) 'lng': _pos!.longitude,
        'lang': L10n.code,
        'platform': Installs.platform,
        'build': int.tryParse(info.buildNumber) ?? 0,
        'created': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('전송에 실패했어요. 네트워크를 확인해 주세요.', 'Failed to send. Check your network.'))));
    }
  }

  Widget _multi(List<(String, String)> opts, Set<String> sel) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (k, label) in opts)
          PillChip(
            label: label,
            selected: sel.contains(k),
            onTap: () => setState(() => sel.contains(k) ? sel.remove(k) : sel.add(k)),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottom = mq.viewInsets.bottom + mq.padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('장소 제안', 'Suggest a place'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          SubText(tr('시가를 피울 수 있는 바·라운지·카페를 알려주세요. 운영자가 확인한 뒤 목록에 올라가요. 익명으로 전송됩니다.',
              'Tell us a bar, lounge or café where you can smoke cigars. The maintainer verifies it before listing. Sent anonymously.'), size: 12),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: tr('상호명 *', 'Place name *'), hintText: tr('예: 버닝 시가 라운지', 'e.g. Casa de Montecristo')),
          ),
          const SizedBox(height: 14),
          SubText(tr('유형 *', 'Type *')),
          const SizedBox(height: 6),
          _multi([('bar', tr('시가 바', 'Cigar bar')), ('lounge', tr('라운지', 'Lounge')), ('cafe', tr('카페', 'Café'))], _kinds),
          const SizedBox(height: 12),
          SubText(tr('흡연', 'Smoking')),
          const SizedBox(height: 6),
          _multi([('indoor', tr('실내', 'Indoor')), ('outdoor', tr('실외', 'Outdoor'))], _smoking),
          const SizedBox(height: 12),
          SubText(tr('시가 판매', 'Sells cigars')),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final (k, label) in [('yes', tr('예', 'Yes')), ('no', tr('아니오', 'No')), ('unknown', tr('모름', 'Not sure'))])
              PillChip(label: label, selected: _sells == k, onTap: () => setState(() => _sells = k)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFB8A999)), foregroundColor: C.accent),
              icon: _locating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_pos == null ? Icons.my_location : Icons.check, size: 18),
              onPressed: _locating ? null : _locate,
              label: Text(_pos == null ? tr('현재 위치 첨부', 'Attach my location') : tr('위치 첨부됨', 'Location attached')),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SubText(
                _locError ?? (_pos == null ? tr('그 자리에서 제안할 때 누르면 찾기 쉬워요 (선택)', 'Tap if you are there now — it helps us find it (optional)') : '${_pos!.latitude.toStringAsFixed(4)}, ${_pos!.longitude.toStringAsFixed(4)}'),
                size: 11,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _comment, maxLines: 2, maxLength: 400, decoration: InputDecoration(labelText: tr('코멘트 (선택)', 'Comment (optional)'), hintText: tr('분위기, 가격대, 가는 법 등', 'Vibe, prices, how to get there…'), counterText: '')),
          const SizedBox(height: 8),
          Row(children: [
            SubText(tr('별점', 'Rating')),
            const SizedBox(width: 10),
            for (var i = 1; i <= 5; i++)
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(i <= _rating ? Icons.star : Icons.star_border, color: C.gold, size: 26),
                onPressed: () => setState(() => _rating = _rating == i ? 0 : i),
              ),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: C.accent),
              onPressed: _sending ? null : _send,
              child: Text(_sending ? tr('보내는 중…', 'Sending…') : tr('제안 보내기', 'Send suggestion')),
            ),
          ),
        ]),
      ),
    );
  }
}
