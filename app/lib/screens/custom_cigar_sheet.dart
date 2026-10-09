import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/scan_service.dart';
import '../l10n.dart';
import '../models/cigar.dart';
import '../state.dart';
import '../theme.dart';

/// DB에 없는 시가를 직접 추가. 저장하면 내 폰 DB에 들어가고(검색·휴미더·다이어리 다 됨),
/// "DB에 제안"을 켜면 운영자 검토용으로 서버에도 한 건 올라간다.
Future<Cigar?> addCustomCigar(BuildContext context, {String initial = ''}) {
  return showModalBottomSheet<Cigar>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _CustomCigarForm(initial: initial),
  );
}

class _CustomCigarForm extends StatefulWidget {
  final String initial;
  const _CustomCigarForm({required this.initial});
  @override
  State<_CustomCigarForm> createState() => _CustomCigarFormState();
}

class _CustomCigarFormState extends State<_CustomCigarForm> {
  late final TextEditingController _brand;
  late final TextEditingController _line;
  final _vitola = TextEditingController();
  final _wrapper = TextEditingController();
  final _country = TextEditingController();
  final _note = TextEditingController();
  bool _cuban = false;
  String? _strength;
  bool _suggest = true;
  bool _saving = false;

  static const _strengths = ['Mild', 'Mild to Medium', 'Medium', 'Medium to Full', 'Full'];

  @override
  void initState() {
    super.initState();
    // "Brand Line words" → 첫 단어는 브랜드, 나머지는 라인으로 미리 채움
    final words = widget.initial.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    _brand = TextEditingController(text: words.isEmpty ? '' : words.first);
    _line = TextEditingController(text: words.length > 1 ? words.sublist(1).join(' ') : '');
  }

  @override
  void dispose() {
    for (final c in [_brand, _line, _vitola, _wrapper, _country, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final brand = _brand.text.trim();
    final line = _line.text.trim();
    if (brand.isEmpty || line.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('브랜드와 라인 이름은 꼭 넣어주세요', 'Brand and line name are required'))));
      return;
    }
    setState(() => _saving = true);
    final st = context.read<AppState>();
    final specs = <String, String>{
      if (_strength != null) 'strength': _strength!.toLowerCase(),
      if (_wrapper.text.trim().isNotEmpty) 'wrapper': _wrapper.text.trim(),
      if (_country.text.trim().isNotEmpty) 'country': _country.text.trim(),
    };
    final j = <String, dynamic>{
      'id': 'custom:${DateTime.now().millisecondsSinceEpoch}',
      'brand': brand,
      'name': line,
      'cuban': _cuban,
      'vitolas': [if (_vitola.text.trim().isNotEmpty) _vitola.text.trim()],
      'official': <String>[],
      'review': <String>[],
      'votes': <String, int>{},
      'specs': specs,
      'aliases': <String>[],
      'tubos': false,
    };
    final cigar = Cigar.fromJson(j);
    await st.db.addCustomCigar(j);
    st.repo.addCustom(cigar);

    // 서버 제안 (실패해도 로컬 저장은 유지)
    if (_suggest && ScanService.instance.ready) {
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await FirebaseFirestore.instance.collection('cigar_suggestions').add({
            'uid': uid,
            'brand': brand,
            'line': line,
            'vitola': _vitola.text.trim(),
            'country': _cuban ? 'Cuba' : _country.text.trim(),
            'strength': _strength ?? '',
            'wrapper': _wrapper.text.trim(),
            'note': _note.text.trim(),
            'created': FieldValue.serverTimestamp(),
          }).timeout(const Duration(seconds: 8));
        }
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.pop(context, cigar);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottom = mq.viewInsets.bottom + mq.padding.bottom; // 키보드 + 내비게이션 바
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('시가 직접 추가', 'Add cigar manually'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          SubText(tr('DB에 없는 한정판·소량 생산 시가를 내 기록용으로 추가해요. 영문 표기 권장.', 'Add a limited or small-batch cigar that is not in the database, for your own logs.'), size: 12),
          const SizedBox(height: 14),
          TextField(controller: _brand, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: tr('브랜드 *', 'Brand *'), hintText: tr('예: Davidoff', 'e.g. Davidoff'))),
          const SizedBox(height: 10),
          TextField(controller: _line, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: tr('라인 / 이름 *', 'Line / name *'), hintText: tr('예: Year of the Snake', 'e.g. Year of the Snake'))),
          const SizedBox(height: 10),
          TextField(controller: _vitola, decoration: InputDecoration(labelText: tr('비톨라 (선택)', 'Vitola (optional)'), hintText: tr('예: Robusto, 5″ × 50', 'e.g. Robusto, 5″ × 50'))),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _strength,
            decoration: InputDecoration(labelText: tr('강도 (선택)', 'Strength (optional)')),
            items: [for (final s in _strengths) DropdownMenuItem(value: s, child: Text(s))],
            onChanged: (v) => setState(() => _strength = v),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _wrapper, decoration: InputDecoration(labelText: tr('래퍼 (선택)', 'Wrapper (optional)'), hintText: 'Habano, Maduro…'))),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _country,
                enabled: !_cuban,
                decoration: InputDecoration(labelText: tr('원산지 (선택)', 'Origin (optional)'), hintText: _cuban ? 'Cuba' : 'Nicaragua…'),
              ),
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(tr('쿠반 시가', 'Cuban cigar'), style: const TextStyle(fontSize: 14)),
            value: _cuban,
            activeColor: C.accent,
            onChanged: (v) => setState(() => _cuban = v),
          ),
          const Divider(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(tr('공식 DB에 제안하기', 'Suggest to database'), style: const TextStyle(fontSize: 14)),
            subtitle: SubText(tr('운영자가 확인 후 다음 업데이트에 반영돼요. 익명으로 전송됩니다.', 'The maintainer reviews it for the next update. Sent anonymously.'), size: 11),
            value: _suggest,
            activeColor: C.accent,
            onChanged: (v) => setState(() => _suggest = v),
          ),
          if (_suggest) ...[
            const SizedBox(height: 4),
            TextField(controller: _note, maxLines: 2, decoration: InputDecoration(labelText: tr('운영자에게 메모 (선택)', 'Memo to maintainer (optional)'), hintText: tr('출처 링크, 한정판 정보 등', 'Source link, limited edition info, etc.'))),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: C.accent),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? tr('저장 중…', 'Saving…') : tr('추가하기', 'Add')),
            ),
          ),
        ]),
      ),
    );
  }
}
