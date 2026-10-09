import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../models/local.dart';
import '../data/photos.dart';
import '../data/analytics.dart';
import '../data/share_stats.dart';
import '../state.dart';
import '../theme.dart';
import 'picker_screen.dart';

/// 기록 추가: 시가 → 느낀 노트 체크 → 초반/중반/후반 메모 → 점수 → 저장(재고 차감)
class RecordScreen extends StatefulWidget {
  final String? cigarId;
  final String? cigarName;
  final String? vitola;
  final int? deductStockId;
  final SmokeLog? edit; // 수정 모드
  const RecordScreen({super.key, this.cigarId, this.cigarName, this.vitola, this.deductStockId, this.edit});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  String? _cigarId;
  String? _cigarName;
  String? _vitola;
  int? _deductStockId;
  List<StockItem> _stockCandidates = [];
  bool _deduct = true;

  final Set<String> _tags = {};
  final _start = TextEditingController();
  final _mid = TextEditingController();
  final _end = TextEditingController();
  final _summary = TextEditingController();
  final _place = TextEditingController();
  final _pairing = TextEditingController();
  final List<String> _photos = [];
  List<String> _origPhotos = const [];
  double _score = 8;
  DateTime _date = DateTime.now();
  bool _showAllTags = false;

  @override
  void initState() {
    super.initState();
    _cigarId = widget.cigarId;
    _cigarName = widget.cigarName;
    _vitola = widget.vitola;
    _deductStockId = widget.deductStockId;
    final e = widget.edit;
    if (e != null) {
      _cigarId = e.cigarId;
      _cigarName = e.cigarName;
      _vitola = e.vitola;
      _tags.addAll(e.tags);
      _start.text = e.noteStart ?? '';
      _mid.text = e.noteMid ?? '';
      _end.text = e.noteEnd ?? '';
      _summary.text = e.summary ?? '';
      _place.text = e.place ?? '';
      _pairing.text = e.pairing ?? '';
      _photos.addAll(e.photos);
      _origPhotos = List.of(e.photos);
      _score = e.score;
      _date = DateTime.tryParse(e.date) ?? DateTime.now();
      _deduct = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.edit != null) return;
      if (_cigarId == null) {
        await _choose();
      } else {
        await _loadStock();
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_start, _mid, _end, _summary, _place, _pairing]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _choose() async {
    final r = await PickerScreen.open(context);
    if (r == null) {
      if (_cigarId == null && mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      _cigarId = r.id;
      _cigarName = r.name;
      _vitola = r.vitola;
      _deductStockId = r.stockItemId;
      _tags.clear();
    });
    await _loadStock();
  }

  Future<void> _loadStock() async {
    final st = context.read<AppState>();
    final list = await st.db.stockOfCigar(_cigarId!);
    if (!mounted) return;
    setState(() {
      _stockCandidates = list;
      if (_deductStockId == null && list.isNotEmpty) _deductStockId = list.first.id;
      _deduct = _deductStockId != null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final repo = st.repo;
    final cigar = _cigarId == null ? null : repo.byId(_cigarId!);
    final suggested = cigar?.allTags ?? const <String>[];

    return Scaffold(
      appBar: AppBar(title: Text(widget.edit == null ? tr('기록 추가', 'New log') : tr('기록 수정', 'Edit log'))),
      body: _cigarId == null
          ? const SizedBox()
          : ListView(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.paddingOf(context).bottom), // 하단 안전영역
              children: [
                // 시가
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      const CigarThumb(size: 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_cigarName!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                          SubText([
                            if (_vitola != null && _vitola!.isNotEmpty) _vitola!,
                            if (cigar != null && cigar.cuban) tr('쿠바', 'Cuban'),
                            if (cigar != null && cigar.specs['strength'] != null) tr('강도 ${cigar.specs['strength']}', 'Strength ${cigar.specs['strength']}'),
                          ].join(' · ')),
                        ]),
                      ),
                      TextButton(onPressed: _choose, child: Text(tr('변경', 'Change'))),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
                // 날짜 · 장소 · 페어링
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(ymd(_date)),
                      onPressed: () async {
                        final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2015), lastDate: DateTime.now());
                        if (d != null) setState(() => _date = d);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _place, decoration: InputDecoration(hintText: tr('장소', 'Place'), isDense: true))),
                ]),
                const SizedBox(height: 8),
                TextField(controller: _pairing, decoration: InputDecoration(hintText: tr('페어링 (커피, 위스키, 제로사이다…)', 'Pairing (coffee, whisky, soda…)'), isDense: true)),
                const SizedBox(height: 10),
                // 사진 (폰 안에만 저장)
                if (LogPhotos.supported) ...[
                  _PhotoRow(photos: _photos, onAdd: _addPhoto, onRemove: (n) => setState(() => _photos.remove(n))),
                  const SizedBox(height: 14),
                ],

                // 노트 체크
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(tr('느낀 노트', 'Notes'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        const Spacer(),
                        SubText(tr('${_tags.length}개 체크', '${_tags.length} selected'), size: 11),
                      ]),
                      const SizedBox(height: 4),
                      if (suggested.isNotEmpty) ...[
                        SubText(cigar!.official.isNotEmpty ? tr('공식·리뷰 노트에서 고르기', 'Pick from official and review notes') : tr('리뷰 노트에서 고르기', 'Pick from review notes'), size: 11),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final t in suggested)
                            NoteChip(
                              label: repo.tagName(t),
                              selected: _tags.contains(t),
                              onTap: () => setState(() => _tags.contains(t) ? _tags.remove(t) : _tags.add(t)),
                            ),
                        ]),
                        const SizedBox(height: 12),
                      ] else
                        Padding(padding: const EdgeInsets.only(bottom: 8), child: SubText(tr('이 시가는 아직 노트 자료가 없어요. 아래 전체 노트에서 골라주세요.', 'No note data for this cigar yet. Pick from all notes below.'), size: 12)),
                      InkWell(
                        onTap: () => setState(() => _showAllTags = !_showAllTags),
                        child: Row(children: [
                          Text(_showAllTags ? tr('전체 노트 접기', 'Hide all notes') : tr('전체 노트에서 더 고르기', 'Pick more from all notes'), style: const TextStyle(fontSize: 12, color: C.accent)),
                          Icon(_showAllTags ? Icons.expand_less : Icons.expand_more, size: 16, color: C.accent),
                        ]),
                      ),
                      if (_showAllTags || suggested.isEmpty) ...[
                        const SizedBox(height: 8),
                        for (final g in repo.tagGroups) ...[
                          SubText(g.name, size: 11),
                          const SizedBox(height: 4),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final t in g.tags)
                              Tooltip(
                                message: t.hintText,
                                child: NoteChip(
                                  label: t.name,
                                  small: true,
                                  selected: _tags.contains(t.id),
                                  onTap: () => setState(() => _tags.contains(t.id) ? _tags.remove(t.id) : _tags.add(t.id)),
                                ),
                              ),
                          ]),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ]),
                  ),
                ),
                const SizedBox(height: 14),

                // 메모
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('흐름 메모', 'Progression memo'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 10),
                      _Memo(label: tr('초반', 'First third'), ctl: _start),
                      const SizedBox(height: 8),
                      _Memo(label: tr('중반', 'Second third'), ctl: _mid),
                      const SizedBox(height: 8),
                      _Memo(label: tr('후반', 'Final third'), ctl: _end),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),

                // 점수
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('총평', 'Summary'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _summary,
                        minLines: 1,
                        maxLines: 3,
                        decoration: InputDecoration(hintText: tr('한 줄로 — 예: 커피랑 잘 맞음, 또 살 듯', 'One line — e.g. great with coffee, would buy again')),
                      ),
                      const SizedBox(height: 14),
                      Row(children: [
                        Text(tr('점수', 'Score'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        const Spacer(),
                        Text(fmtScore(_score), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: C.accent)),
                      ]),
                      Slider(
                        value: _score,
                        min: 5,
                        max: 10,
                        divisions: 10,
                        activeColor: C.accent,
                        onChanged: (v) => setState(() => _score = (v * 2).round() / 2),
                      ),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        SubText(tr('5 별로', '5 Meh'), size: 11),
                        SubText(tr('7.5 무난', '7.5 Decent'), size: 11),
                        SubText(tr('8.5 또 사고 싶음', '8.5 Would buy again'), size: 11),
                        const SubText('10', size: 11),
                      ]),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),

                // 재고 차감 (수정 모드에선 안 보임)
                if (widget.edit == null && _stockCandidates.isNotEmpty)
                  Card(
                    child: Column(children: [
                      CheckboxListTile(
                        value: _deduct,
                        activeColor: C.accent,
                        title: Text(tr('휴미더 재고에서 1개 빼기', 'Take 1 from humidor stock'), style: const TextStyle(fontSize: 14)),
                        subtitle: _stockCandidates.length > 1 ? Text(tr('어느 줄에서 뺄지 아래에서 선택', 'Choose which row below')) : null,
                        onChanged: (v) => setState(() => _deduct = v ?? false),
                      ),
                      if (_deduct && _stockCandidates.length > 1)
                        RadioGroup<int>(
                          groupValue: _deductStockId,
                          onChanged: (v) => setState(() => _deductStockId = v),
                          child: Column(children: [
                            for (final s in _stockCandidates)
                              RadioListTile<int>(
                                dense: true,
                                value: s.id,
                                activeColor: C.accent,
                                title: Text('${st.humidors.where((h) => h.id == s.humidorId).map((h) => h.name).join()} · ${s.vitola ?? ''} · ${tr('재고 ${s.qty}', 'stock ${s.qty}')}', style: const TextStyle(fontSize: 13)),
                              ),
                          ]),
                        ),
                    ]),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _save,
                  child: Text(tr('저장', 'Save')),
                ),
              ],
            ),
    );
  }

  Future<void> _addPhoto() async {
    final gallery = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(tr('사진 찍기', 'Take photo')), onTap: () => Navigator.pop(ctx, false)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(tr('갤러리에서 선택', 'Choose from gallery')), onTap: () => Navigator.pop(ctx, true)),
        ]),
      ),
    );
    if (gallery == null) return;
    try {
      final name = await LogPhotos.instance.pick(gallery: gallery);
      if (name != null && mounted) setState(() => _photos.add(name));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('사진을 가져오지 못했어요', 'Could not get the photo'))));
    }
  }

  /// 저장 시: 편집 중 뺀 원래 사진 파일 삭제
  Future<void> _cleanupPhotos() async {
    await LogPhotos.instance.deleteAll(_origPhotos.where((n) => !_photos.contains(n)));
  }

  Future<void> _save() async {
    await _cleanupPhotos();
    final st = context.read<AppState>();
    if (widget.edit != null) {
      await st.db.updateLog(widget.edit!.id, {
        'cigar_id': _cigarId,
        'cigar_name': _cigarName,
        'vitola': _vitola,
        'date': ymd(_date),
        'score': _score,
        'tags': _tags.join(','),
        'note_start': _start.text.trim().isEmpty ? null : _start.text.trim(),
        'note_mid': _mid.text.trim().isEmpty ? null : _mid.text.trim(),
        'note_end': _end.text.trim().isEmpty ? null : _end.text.trim(),
        'summary': _summary.text.trim().isEmpty ? null : _summary.text.trim(),
        'place': _place.text.trim().isEmpty ? null : _place.text.trim(),
        'pairing': _pairing.text.trim().isEmpty ? null : _pairing.text.trim(),
        'photos': _photos.isEmpty ? null : joinPhotos(_photos),
      });
      await st.reload();
      final updated = st.logs.where((l) => l.id == widget.edit!.id).firstOrNull;
      if (updated != null) ShareStats.instance.push(updated);
      Analytics.instance.logSaved(fromStock: false, edit: true);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('$_cigarName 기록 수정됨', '$_cigarName log updated'))));
      return;
    }
    await ShareStats.instance.noticeIfNeeded(context);
    if (!mounted) return;
    final newId = await st.db.addLog(
      cigarId: _cigarId!,
      cigarName: _cigarName!,
      vitola: _vitola,
      date: ymd(_date),
      score: _score,
      tags: _tags.toList(),
      noteStart: _start.text.trim().isEmpty ? null : _start.text.trim(),
      noteMid: _mid.text.trim().isEmpty ? null : _mid.text.trim(),
      noteEnd: _end.text.trim().isEmpty ? null : _end.text.trim(),
      summary: _summary.text.trim().isEmpty ? null : _summary.text.trim(),
      place: _place.text.trim().isEmpty ? null : _place.text.trim(),
      pairing: _pairing.text.trim().isEmpty ? null : _pairing.text.trim(),
      photos: List.of(_photos),
      deductStockId: _deduct ? _deductStockId : null,
    );
    await st.reload();
    final added = st.logs.where((l) => l.id == newId).firstOrNull;
    if (added != null) {
      // 아직 기존 기록을 한 번도 안 올렸으면 이번에 전부, 아니면 이 건만
      if (!await ShareStats.instance.backfilled) {
        await ShareStats.instance.backfill(st.logs);
      } else {
        ShareStats.instance.push(added);
      }
    }
    Analytics.instance.logSaved(fromStock: _deduct && _deductStockId != null, edit: false);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(
      '$_cigarName ${fmtScore(_score)}점 기록${_deduct && _deductStockId != null ? ' · 재고 -1' : ''}',
      '$_cigarName logged at ${fmtScore(_score)}${_deduct && _deductStockId != null ? ' · stock -1' : ''}',
    ))));
  }
}

class _Memo extends StatelessWidget {
  final String label;
  final TextEditingController ctl;
  const _Memo({required this.label, required this.ctl});
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctl,
      minLines: 2,
      maxLines: 5,
      decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
    );
  }
}

/// 기록 폼의 사진 줄: 썸네일들 + 추가 버튼
class _PhotoRow extends StatelessWidget {
  final List<String> photos;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;
  const _PhotoRow({required this.photos, required this.onAdd, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final n in photos)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: FutureBuilder<File>(
                  future: LogPhotos.instance.file(n),
                  builder: (_, snap) => snap.hasData
                      ? Image.file(snap.data!, width: 72, height: 72, fit: BoxFit.cover)
                      : Container(width: 72, height: 72, color: C.chip),
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: () => onRemove(n),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ]),
          ),
        if (photos.length < 6)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onAdd,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(10)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.photo_camera_outlined, color: C.sub, size: 22),
                const SizedBox(height: 2),
                SubText(tr('사진', 'Photo'), size: 10),
              ]),
            ),
          ),
      ]),
    );
  }
}
