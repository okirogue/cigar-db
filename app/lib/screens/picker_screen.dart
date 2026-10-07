import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../models/cigar.dart';
import '../models/local.dart';
import '../state.dart';
import '../theme.dart';
import 'custom_cigar_sheet.dart';

/// 선택 결과. DB에 없는 시가는 cigar == null, customName 사용.
class PickResult {
  final Cigar? cigar;
  final String? customName;
  final String? vitola; // 내 휴미더에서 골랐을 때
  final int? stockItemId;
  PickResult({this.cigar, this.customName, this.vitola, this.stockItemId});

  String get id => cigar?.id ?? 'custom:${customName!.toLowerCase().replaceAll(RegExp(r'\s+'), '-')}';
  String get name => cigar?.fullName ?? customName!;
}

/// "어떤 시가?" 검색 화면. 내 휴미더 재고 → 전체 DB 순으로 보여준다.
class PickerScreen extends StatefulWidget {
  final bool showStock; // 기록용이면 true, 입고용이면 false
  const PickerScreen({super.key, this.showStock = true});

  static Future<PickResult?> open(BuildContext context, {bool showStock = true}) {
    return Navigator.push<PickResult>(context, MaterialPageRoute(builder: (_) => PickerScreen(showStock: showStock), fullscreenDialog: true));
  }

  @override
  State<PickerScreen> createState() => _PickerScreenState();
}

class _PickerScreenState extends State<PickerScreen> {
  final _c = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final q = _q.trim().toLowerCase();
    final results = st.repo.search(_q);
    final stock = widget.showStock
        ? st.allStock.where((s) => q.isEmpty || s.cigarName.toLowerCase().contains(q)).toList()
        : <StockItem>[];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        title: Text(tr('어떤 시가?', 'Which cigar?')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _c,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(hintText: tr('브랜드나 라인 이름 (영문)', 'Brand or line name')),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                if (stock.isNotEmpty) ...[
                  Padding(padding: const EdgeInsets.only(bottom: 6), child: SubText(tr('내 휴미더', 'My humidor'))),
                  for (final s in stock)
                    _Row(
                      title: s.cigarName,
                      sub: [if (s.vitola != null && s.vitola!.isNotEmpty) s.vitola!, tr('${s.agingDays}일 숙성', 'aged ${s.agingDays} days')].join(' · '),
                      trailing: _Badge(tr('재고 ${s.qty}', 'Stock ${s.qty}')),
                      onTap: () => Navigator.pop(context, PickResult(cigar: st.repo.byId(s.cigarId), customName: st.repo.byId(s.cigarId) == null ? s.cigarName : null, vitola: s.vitola, stockItemId: s.id)),
                    ),
                  const SizedBox(height: 10),
                ],
                if (q.isNotEmpty) ...[
                  Padding(padding: const EdgeInsets.only(bottom: 6), child: SubText(tr('전체 DB', 'All cigars'))),
                  if (results.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: SubText(tr('검색 결과가 없어요', 'No results'), size: 13)),
                  for (final c in results)
                    _Row(
                      title: c.fullName,
                      sub: _specLine(c),
                      trailing: c.hasNotes ? _Badge(tr('노트', 'Notes')) : null,
                      onTap: () => Navigator.pop(context, PickResult(cigar: c)),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFB8A999)), foregroundColor: C.accent),
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: () async {
                      final c = await addCustomCigar(context, initial: _q.trim());
                      if (c != null && context.mounted) Navigator.pop(context, PickResult(cigar: c));
                    },
                    label: Text(tr('못 찾겠어요 · "${_q.trim()}" 직접 추가', 'Not listed · add "${_q.trim()}" manually')),
                  ),
                ] else if (stock.isEmpty)
                  Padding(padding: const EdgeInsets.only(top: 40), child: Center(child: SubText(tr('브랜드 이름부터 쳐보세요 (예: romeo, oliva)', 'Start with a brand name (e.g. romeo, oliva)'), size: 13))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _specLine(Cigar c) {
    final p = <String>[
      if (c.cuban) tr('쿠바', 'Cuban'),
      if (c.specs['length_in'] != null && c.specs['ring_gauge'] != null) '${c.specs['length_in']} × ${c.specs['ring_gauge']}',
      if (c.specs['strength'] != null) c.specs['strength']!,
      if (c.vitolas.isNotEmpty) tr('${c.vitolas.length}종', '${c.vitolas.length} vitolas'),
    ];
    return p.join(' · ');
  }
}

class _Row extends StatelessWidget {
  final String title;
  final String sub;
  final Widget? trailing;
  final VoidCallback onTap;
  const _Row({required this.title, required this.sub, this.trailing, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              const CigarThumb(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  if (sub.isNotEmpty) SubText(sub),
                ]),
              ),
              if (trailing != null) trailing!,
            ]),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge(this.text);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(fontSize: 11, color: C.accent)),
      );
}
