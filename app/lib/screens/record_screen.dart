import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/local.dart';
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
  int _score = 80;
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
      appBar: AppBar(title: Text(widget.edit == null ? '기록 추가' : '기록 수정')),
      body: _cigarId == null
          ? const SizedBox()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
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
                            if (cigar != null && cigar.cuban) '쿠바',
                            if (cigar != null && cigar.specs['strength'] != null) '강도 ${cigar.specs['strength']}',
                          ].join(' · ')),
                        ]),
                      ),
                      TextButton(onPressed: _choose, child: const Text('변경')),
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
                  Expanded(child: TextField(controller: _place, decoration: const InputDecoration(hintText: '장소', isDense: true))),
                ]),
                const SizedBox(height: 8),
                TextField(controller: _pairing, decoration: const InputDecoration(hintText: '페어링 (커피, 위스키, 제로사이다…)', isDense: true)),
                const SizedBox(height: 14),

                // 노트 체크
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Text('느낀 노트', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        const Spacer(),
                        SubText('${_tags.length}개 체크', size: 11),
                      ]),
                      const SizedBox(height: 4),
                      if (suggested.isNotEmpty) ...[
                        SubText(cigar!.official.isNotEmpty ? '공식·리뷰 노트에서 고르기' : '리뷰 노트에서 고르기', size: 11),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final t in suggested)
                            NoteChip(
                              label: repo.tagKo(t),
                              selected: _tags.contains(t),
                              onTap: () => setState(() => _tags.contains(t) ? _tags.remove(t) : _tags.add(t)),
                            ),
                        ]),
                        const SizedBox(height: 12),
                      ] else
                        const Padding(padding: EdgeInsets.only(bottom: 8), child: SubText('이 시가는 아직 노트 자료가 없어요. 아래 전체 노트에서 골라주세요.', size: 12)),
                      InkWell(
                        onTap: () => setState(() => _showAllTags = !_showAllTags),
                        child: Row(children: [
                          Text(_showAllTags ? '전체 노트 접기' : '전체 노트에서 더 고르기', style: const TextStyle(fontSize: 12, color: C.accent)),
                          Icon(_showAllTags ? Icons.expand_less : Icons.expand_more, size: 16, color: C.accent),
                        ]),
                      ),
                      if (_showAllTags || suggested.isEmpty) ...[
                        const SizedBox(height: 8),
                        for (final g in repo.tagGroups) ...[
                          SubText(g.ko, size: 11),
                          const SizedBox(height: 4),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final t in g.tags)
                              Tooltip(
                                message: t.hint,
                                child: NoteChip(
                                  label: t.ko,
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
                      const Text('흐름 메모', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 10),
                      _Memo(label: '초반', ctl: _start),
                      const SizedBox(height: 8),
                      _Memo(label: '중반', ctl: _mid),
                      const SizedBox(height: 8),
                      _Memo(label: '후반', ctl: _end),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),

                // 점수
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('총평', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _summary,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(hintText: '한 줄로 — 예: 커피랑 잘 맞음, 또 살 듯'),
                      ),
                      const SizedBox(height: 14),
                      Row(children: [
                        const Text('점수', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        const Spacer(),
                        Text('$_score', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: C.accent)),
                      ]),
                      Slider(
                        value: _score.toDouble(),
                        min: 50,
                        max: 100,
                        divisions: 50,
                        activeColor: C.accent,
                        onChanged: (v) => setState(() => _score = v.round()),
                      ),
                      const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        SubText('50 별로', size: 11),
                        SubText('75 무난', size: 11),
                        SubText('85 또 사고 싶음', size: 11),
                        SubText('100', size: 11),
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
                        title: const Text('휴미더 재고에서 1개 빼기', style: TextStyle(fontSize: 14)),
                        subtitle: _stockCandidates.length > 1 ? const Text('어느 줄에서 뺄지 아래에서 선택') : null,
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
                                title: Text('${st.humidors.where((h) => h.id == s.humidorId).map((h) => h.name).join()} · ${s.vitola ?? ''} · 재고 ${s.qty}', style: const TextStyle(fontSize: 13)),
                              ),
                          ]),
                        ),
                    ]),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _save,
                  child: const Text('저장'),
                ),
              ],
            ),
    );
  }

  Future<void> _save() async {
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
      });
      await st.reload();
      final updated = st.logs.where((l) => l.id == widget.edit!.id).firstOrNull;
      if (updated != null) ShareStats.instance.push(updated);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$_cigarName 기록 수정됨')));
      return;
    }
    await ShareStats.instance.askIfNeeded(context);
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
      deductStockId: _deduct ? _deductStockId : null,
    );
    await st.reload();
    final added = st.logs.where((l) => l.id == newId).firstOrNull;
    if (added != null) {
      // 처음 켠 경우 기존 기록까지 한 번에
      final p = await SharedPreferences.getInstance();
      if (!(p.getBool('share_backfilled') ?? false)) {
        await ShareStats.instance.backfill(st.logs);
        await p.setBool('share_backfilled', true);
      } else {
        ShareStats.instance.push(added);
      }
    }
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$_cigarName $_score점 기록${_deduct && _deductStockId != null ? ' · 재고 -1' : ''}')));
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
