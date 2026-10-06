import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/local.dart';
import '../state.dart';
import '../theme.dart';
import 'add_stock_screen.dart';
import 'detail_screen.dart';
import 'record_screen.dart';

enum StockSort { added, qty, aging }

class HumidorScreen extends StatefulWidget {
  const HumidorScreen({super.key});
  @override
  State<HumidorScreen> createState() => _HumidorScreenState();
}

class _HumidorScreenState extends State<HumidorScreen> {
  int? _selected; // null이면 첫 휴미더
  StockSort _sort = StockSort.added;

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final humidors = st.humidors;
    final current = humidors.isEmpty ? null : humidors.firstWhere((h) => h.id == _selected, orElse: () => humidors.first);
    final items = current == null ? <StockItem>[] : st.stockIn(current.id);
    switch (_sort) {
      case StockSort.added:
        items.sort((a, b) => b.addedDate.compareTo(a.addedDate));
      case StockSort.qty:
        items.sort((a, b) => b.qty.compareTo(a.qty));
      case StockSort.aging:
        items.sort((a, b) => b.agingDays.compareTo(a.agingDays));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('휴미더', style: TextStyle(fontSize: 24)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Center(child: SubText('총 ${st.totalQty}개비', size: 14)),
          ),
        ],
      ),
      body: Column(
        children: [
          // 휴미더 선택 줄
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                for (final h in humidors) ...[
                  _HumidorTab(
                    label: '${h.name} · ${st.qtyByHumidor[h.id] ?? 0}',
                    selected: current?.id == h.id,
                    onTap: () => setState(() => _selected = h.id),
                    onLongPress: () => _editHumidor(context, h),
                  ),
                  const SizedBox(width: 8),
                ],
                if (st.canAddHumidor)
                  _DashedButton(onTap: () => _addHumidor(context)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 정렬
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const SubText('정렬'),
                const SizedBox(width: 8),
                PillChip(label: '입고일', dark: true, selected: _sort == StockSort.added, onTap: () => setState(() => _sort = StockSort.added)),
                const SizedBox(width: 8),
                PillChip(label: '수량', dark: true, selected: _sort == StockSort.qty, onTap: () => setState(() => _sort = StockSort.qty)),
                const SizedBox(width: 8),
                PillChip(label: '숙성일', dark: true, selected: _sort == StockSort.aging, onTap: () => setState(() => _sort = StockSort.aging)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: items.isEmpty
                ? const Center(child: SubText('아직 비어 있어요. 아래 + 입고로 시가를 넣어보세요.', size: 13))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _StockCard(item: items[i]),
                  ),
          ),
        ],
      ),
      floatingActionButton: current == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: C.accent,
              foregroundColor: Colors.white,
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => AddStockScreen(initialHumidorId: current.id)));
              },
              label: const Text('+ 입고'),
            ),
    );
  }

  Future<void> _addHumidor(BuildContext context) async {
    final st = context.read<AppState>();
    final name = await _askName(context, title: '휴미더 이름');
    if (name == null || name.isEmpty) return;
    final id = await st.db.addHumidor(name);
    await st.reload();
    setState(() => _selected = id);
  }

  Future<void> _editHumidor(BuildContext context, Humidor h) async {
    final st = context.read<AppState>();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('이름 바꾸기'), onTap: () => Navigator.pop(sctx, 'rename')),
          if (st.humidors.length > 1)
            ListTile(leading: const Icon(Icons.delete_outline), title: const Text('휴미더 삭제 (안의 재고도 삭제)'), onTap: () => Navigator.pop(sctx, 'delete')),
        ]),
      ),
    );
    if (!context.mounted) return;
    if (action == 'rename') {
      final name = await _askName(context, title: '휴미더 이름', initial: h.name);
      if (name != null && name.isNotEmpty) {
        await st.db.renameHumidor(h.id, name);
        await st.reload();
      }
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: Text('${h.name} 삭제'),
          content: const Text('이 휴미더와 안의 재고 목록이 지워져요. 기록(다이어리)은 남아요.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('취소')),
            TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('삭제')),
          ],
        ),
      );
      if (ok == true) {
        await st.db.deleteHumidor(h.id);
        await st.reload();
        setState(() => _selected = null);
      }
    }
  }
}

Future<String?> _askName(BuildContext context, {required String title, String? initial}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: '예: 아도리니, 락앤락')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('취소')),
        TextButton(onPressed: () => Navigator.pop(dctx, c.text.trim()), child: const Text('확인')),
      ],
    ),
  );
}

class _HumidorTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _HumidorTab({required this.label, required this.selected, required this.onTap, required this.onLongPress});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? C.accent : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: selected ? null : Border.all(color: C.line),
        ),
        child: Text(label, style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w500 : FontWeight.w400, color: selected ? Colors.white : C.text)),
      ),
    );
  }
}

class _DashedButton extends StatelessWidget {
  final VoidCallback onTap;
  const _DashedButton({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB8A999))),
        child: const Icon(Icons.add, color: C.accent),
      ),
    );
  }
}

class _StockCard extends StatelessWidget {
  final StockItem item;
  const _StockCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final cigar = st.repo.byId(item.cigarId);
    final parts = <String>[
      if (item.vitola != null && item.vitola!.isNotEmpty) item.vitola!,
      if (cigar != null && cigar.specs['length_in'] != null && cigar.specs['ring_gauge'] != null) '${cigar.specs['length_in']}×${cigar.specs['ring_gauge']}',
      if (item.pricePerStick != null) fmtWon(item.pricePerStick!),
      '${fmtShort(item.addedDate)} 입고',
      '${item.agingDays}일 숙성',
    ];
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openMenu(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const CigarThumb(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.cigarName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  SubText(parts.join(' · ')),
                ]),
              ),
              const SizedBox(width: 8),
              _QtyBtn(icon: Icons.remove, onTap: () => _change(context, -1)),
              SizedBox(width: 28, child: Text('${item.qty}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
              _QtyBtn(icon: Icons.add, onTap: () => _change(context, 1)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _change(BuildContext context, int delta) async {
    final st = context.read<AppState>();
    await st.db.changeQty(item.id, delta);
    await st.reload();
  }

  Future<void> _openMenu(BuildContext context) async {
    final st = context.read<AppState>();
    final cigar = st.repo.byId(item.cigarId);
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(item.cigarName, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text('${item.vitola ?? ''} · 재고 ${item.qty}')),
          ListTile(
            leading: const Icon(Icons.local_fire_department_outlined),
            title: const Text('지금 피우기 → 기록'),
            subtitle: const Text('저장하면 재고 1개 줄어요'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => RecordScreen(cigarId: item.cigarId, cigarName: item.cigarName, vitola: item.vitola, deductStockId: item.id)),
              );
            },
          ),
          if (cigar != null)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('시가 정보 보기'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(cigar: cigar)));
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('이 줄 삭제'),
            onTap: () async {
              Navigator.pop(ctx);
              await st.db.deleteStock(item.id);
              await st.reload();
            },
          ),
        ]),
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: C.line)),
        child: Icon(icon, size: 16),
      ),
    );
  }
}
