import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state.dart';
import '../theme.dart';
import 'picker_screen.dart';

/// 시가 입고: 시가 선택 → 비톨라 → 수량 → 구매가(선택) → 입고일 → 휴미더
class AddStockScreen extends StatefulWidget {
  final int initialHumidorId;
  final PickResult? preset; // 상세 화면에서 "휴미더에 추가"로 들어올 때
  const AddStockScreen({super.key, required this.initialHumidorId, this.preset});

  @override
  State<AddStockScreen> createState() => _AddStockScreenState();
}

const _currencies = ['USD', 'KRW', 'IDR', 'HKD', 'JPY', 'EUR'];

class _AddStockScreenState extends State<AddStockScreen> {
  PickResult? _pick;
  String? _vitola;
  final _vitolaCtl = TextEditingController();
  int _qty = 1;
  final _priceCtl = TextEditingController();
  final _rateCtl = TextEditingController(text: '1400');
  String _cur = 'USD';
  late DateTime _date = DateTime.now();
  late int _humidorId = widget.initialHumidorId;

  @override
  void initState() {
    super.initState();
    _pick = widget.preset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pick == null) _choose();
    });
  }

  @override
  void dispose() {
    _vitolaCtl.dispose();
    _priceCtl.dispose();
    _rateCtl.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    final r = await PickerScreen.open(context, showStock: false);
    if (r != null) {
      setState(() {
        _pick = r;
        _vitola = null;
        _vitolaCtl.clear();
      });
    } else if (_pick == null && mounted) {
      Navigator.pop(context);
    }
  }

  /// 개비당 원화 (구매가 비우면 null)
  int? get _pricePerStick {
    final total = double.tryParse(_priceCtl.text.replaceAll(',', ''));
    if (total == null || total <= 0 || _qty <= 0) return null;
    final rate = _cur == 'KRW' ? 1.0 : (double.tryParse(_rateCtl.text.replaceAll(',', '')) ?? 0);
    if (rate <= 0) return null;
    return (total * rate / _qty).round();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final cigar = _pick?.cigar;
    final vitolas = cigar?.vitolas ?? const <String>[];
    final pps = _pricePerStick;

    return Scaffold(
      appBar: AppBar(title: const Text('시가 입고')),
      body: _pick == null
          ? const SizedBox()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                // 선택된 시가
                Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _choose,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        const Thumb(size: 48),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const SubText('선택됨'),
                            Text(_pick!.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                            SubText(cigar == null ? '직접 입력' : [if (cigar.cuban) '쿠바', cigar.hasNotes ? '노트 有' : '노트 없음'].join(' · ')),
                          ]),
                        ),
                        const Text('변경', style: TextStyle(fontSize: 13, color: C.accent)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // 비톨라
                      const SubText('비톨라'),
                      const SizedBox(height: 4),
                      if (vitolas.isNotEmpty)
                        DropdownButtonFormField<String>(
                          value: _vitola,
                          hint: const Text('선택'),
                          items: [
                            for (final v in vitolas) DropdownMenuItem(value: v, child: Text(_stripBrand(v, cigar!.name))),
                            const DropdownMenuItem(value: '__other', child: Text('직접 입력')),
                          ],
                          onChanged: (v) => setState(() => _vitola = v),
                        ),
                      if (vitolas.isEmpty || _vitola == '__other') ...[
                        const SizedBox(height: 6),
                        TextField(controller: _vitolaCtl, decoration: const InputDecoration(hintText: '예: Robusto, No.4, 튜보')),
                      ],
                      const SizedBox(height: 12),
                      // 수량
                      const SubText('수량'),
                      const SizedBox(height: 4),
                      Row(children: [
                        _Sq(icon: Icons.remove, onTap: () => setState(() => _qty = (_qty - 1).clamp(1, 999))),
                        Expanded(
                          child: Text('$_qty', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        ),
                        _Sq(icon: Icons.add, onTap: () => setState(() => _qty = (_qty + 1).clamp(1, 999))),
                        const SizedBox(width: 8),
                        for (final n in [5, 10, 20, 25]) ...[
                          PillChip(label: '$n', selected: _qty == n, onTap: () => setState(() => _qty = n)),
                          const SizedBox(width: 6),
                        ],
                      ]),
                      const SizedBox(height: 12),
                      // 가격
                      const SubText('구매가 (선택, 총액)'),
                      const SizedBox(height: 4),
                      Row(children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _priceCtl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(hintText: '비우면 공란'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _cur,
                            items: [for (final c in _currencies) DropdownMenuItem(value: c, child: Text(c))],
                            onChanged: (v) => setState(() => _cur = v ?? 'USD'),
                          ),
                        ),
                      ]),
                      if (_cur != 'KRW') ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          SubText('환율 1 $_cur ='),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 110,
                            child: TextField(
                              controller: _rateCtl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(isDense: true, suffixText: '원'),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ]),
                      ],
                      const SizedBox(height: 8),
                      if (pps != null)
                        RichText(
                          text: TextSpan(style: const TextStyle(fontSize: 12, color: C.sub), children: [
                            const TextSpan(text: '개비당 약 '),
                            TextSpan(text: fmtWon(pps), style: const TextStyle(color: C.text, fontWeight: FontWeight.w700)),
                          ]),
                        )
                      else
                        const SubText('구매가를 안 쓰면 카드에 가격이 표시되지 않아요'),
                      const SizedBox(height: 12),
                      // 입고일
                      const SubText('입고일'),
                      const SizedBox(height: 4),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today_outlined, size: 16),
                        label: Align(alignment: Alignment.centerLeft, child: Text(ymd(_date))),
                        onPressed: () async {
                          final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2015), lastDate: DateTime.now());
                          if (d != null) setState(() => _date = d);
                        },
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
                const SubText('넣을 휴미더'),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final h in st.humidors)
                    ChoiceChip(
                      label: Text(h.name),
                      selected: _humidorId == h.id,
                      selectedColor: C.accent,
                      labelStyle: TextStyle(color: _humidorId == h.id ? Colors.white : C.text),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: C.line),
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _humidorId = h.id),
                    ),
                  if (st.canAddHumidor)
                    ActionChip(
                      label: const Icon(Icons.add, size: 18, color: C.accent),
                      backgroundColor: Colors.transparent,
                      side: const BorderSide(color: Color(0xFFB8A999)),
                      onPressed: () async {
                        final c = TextEditingController();
                        final name = await showDialog<String>(
                          context: context,
                          builder: (dctx) => AlertDialog(
                            title: const Text('휴미더 이름'),
                            content: TextField(controller: c, autofocus: true),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('취소')),
                              TextButton(onPressed: () => Navigator.pop(dctx, c.text.trim()), child: const Text('확인')),
                            ],
                          ),
                        );
                        if (name != null && name.isNotEmpty) {
                          final id = await st.db.addHumidor(name);
                          await st.reload();
                          setState(() => _humidorId = id);
                        }
                      },
                    ),
                ]),
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _save,
                  child: Text('입고 ($_qty개비)'),
                ),
              ],
            ),
    );
  }

  Future<void> _save() async {
    final st = context.read<AppState>();
    final v = (_vitola == null || _vitola == '__other') ? _vitolaCtl.text.trim() : _stripBrand(_vitola!, _pick!.cigar?.name ?? '');
    await st.db.addStock(
      humidorId: _humidorId,
      cigarId: _pick!.id,
      cigarName: _pick!.name,
      vitola: v.isEmpty ? null : v,
      qty: _qty,
      pricePerStick: _pricePerStick,
      addedDate: ymd(_date),
    );
    await st.reload();
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_pick!.name} $_qty개비 입고')));
  }
}

/// DB 비톨라는 "romeo no.1 ..." 처럼 라인 이름이 앞에 붙어 있어 떼어낸다.
String _stripBrand(String vitola, String lineName) {
  final v = vitola.trim();
  final l = lineName.trim().toLowerCase();
  if (l.isNotEmpty && v.toLowerCase().startsWith(l)) {
    final rest = v.substring(l.length).trim();
    if (rest.isNotEmpty) return _cap(rest);
  }
  return _cap(v);
}

String _cap(String s) => s.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

class _Sq extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _Sq({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: C.line)),
          child: Icon(icon, size: 18),
        ),
      );
}
