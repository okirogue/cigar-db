import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../models/local.dart';
import '../state.dart';
import '../theme.dart';
import 'add_stock_screen.dart';
import 'detail_screen.dart';
import 'record_screen.dart';
import 'wishlist_sheet.dart';

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
        title: Text(tr('휴미더', 'Humidor'), style: const TextStyle(fontSize: 24)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Center(child: SubText(tr('총 ${st.totalQty}개비', '${st.totalQty} total'), size: 14)),
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
                  // 재고 카드를 길게 눌러 끌어다 놓으면 그 휴미더로 이동
                  DragTarget<StockItem>(
                    onWillAcceptWithDetails: (d) => d.data.humidorId != h.id,
                    onAcceptWithDetails: (d) => moveStockFlow(context, d.data, h),
                    builder: (_, cand, __) => _HumidorTab(
                      label: '${h.name} · ${st.qtyByHumidor[h.id] ?? 0}',
                      selected: current?.id == h.id,
                      highlight: cand.isNotEmpty,
                      onTap: () => setState(() => _selected = h.id),
                      onLongPress: () => _editHumidor(context, h),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (st.canAddHumidor) ...[
                  _DashedButton(onTap: () => _addHumidor(context)),
                  const SizedBox(width: 8),
                ],
                // 위시리스트 (다음에 살 것)
                _WishChip(count: st.wishlist.length, onTap: () => openWishlistSheet(context)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 정렬
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                SubText(tr('정렬', 'Sort')),
                const SizedBox(width: 8),
                PillChip(label: tr('입고일', 'Date added'), dark: true, selected: _sort == StockSort.added, onTap: () => setState(() => _sort = StockSort.added)),
                const SizedBox(width: 8),
                PillChip(label: tr('수량', 'Qty'), dark: true, selected: _sort == StockSort.qty, onTap: () => setState(() => _sort = StockSort.qty)),
                const SizedBox(width: 8),
                PillChip(label: tr('숙성일', 'Aging'), dark: true, selected: _sort == StockSort.aging, onTap: () => setState(() => _sort = StockSort.aging)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: items.isEmpty
                ? Center(child: SubText(tr('아직 비어 있어요. 아래 + 입고로 시가를 넣어보세요.', 'Empty so far. Tap + Add below to add cigars.'), size: 13))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => humidors.length > 1
                        ? LongPressDraggable<StockItem>(
                            data: items[i],
                            dragAnchorStrategy: pointerDragAnchorStrategy,
                            feedback: _DragChip(item: items[i]),
                            childWhenDragging: Opacity(opacity: 0.35, child: _StockCard(item: items[i])),
                            child: _StockCard(item: items[i]),
                          )
                        : _StockCard(item: items[i]),
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
              label: Text(tr('+ 입고', '+ Add')),
            ),
    );
  }

  Future<void> _addHumidor(BuildContext context) async {
    final st = context.read<AppState>();
    final name = await _askName(context, title: tr('휴미더 이름', 'Humidor name'));
    if (name == null || name.isEmpty) return;
    final id = await st.db.addHumidor(name);
    await st.reload();
    setState(() => _selected = id);
  }

  /// 휴미더 순서: 손잡이를 끌어서 바꾸는 시트. 닫으면 저장 + 동기화.
  Future<void> _reorderHumidors(BuildContext context) async {
    final st = context.read<AppState>();
    var order = [...st.humidors];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sctx) => StatefulBuilder(
        builder: (sctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(tr('휴미더 순서 — 손잡이를 끌어서 바꾸세요', 'Humidor order — drag the handles'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              const SizedBox(height: 8),
              ReorderableListView(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                onReorder: (from, to) {
                  setSheet(() {
                    if (to > from) to -= 1;
                    final h = order.removeAt(from);
                    order.insert(to, h);
                  });
                },
                children: [
                  for (var i = 0; i < order.length; i++)
                    ListTile(
                      key: ValueKey(order[i].id),
                      dense: true,
                      leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle, color: C.hint)),
                      title: Text(order[i].name),
                      trailing: SubText('${st.qtyByHumidor[order[i].id] ?? 0}', size: 12),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.pop(sctx), child: Text(tr('완료', 'Done'))),
              ),
            ]),
          ),
        ),
      ),
    );
    final before = st.humidors.map((h) => h.id).toList(), after = order.map((h) => h.id).toList();
    if (before.join(',') == after.join(',')) return;
    await st.db.reorderHumidors(after);
    await st.reload();
  }

  Future<void> _editHumidor(BuildContext context, Humidor h) async {
    final st = context.read<AppState>();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_outlined), title: Text(tr('이름 바꾸기', 'Rename')), onTap: () => Navigator.pop(sctx, 'rename')),
          if (st.humidors.length > 1)
            ListTile(leading: const Icon(Icons.swap_vert), title: Text(tr('휴미더 순서 바꾸기', 'Reorder humidors')), onTap: () => Navigator.pop(sctx, 'reorder')),
          if (st.humidors.length > 1)
            ListTile(leading: const Icon(Icons.delete_outline), title: Text(tr('휴미더 삭제 (안의 재고도 삭제)', 'Delete humidor (and its stock)')), onTap: () => Navigator.pop(sctx, 'delete')),
        ]),
      ),
    );
    if (!context.mounted) return;
    if (action == 'reorder') {
      await _reorderHumidors(context);
      return;
    }
    if (action == 'rename') {
      final name = await _askName(context, title: tr('휴미더 이름', 'Humidor name'), initial: h.name);
      if (name != null && name.isNotEmpty) {
        await st.db.renameHumidor(h.id, name);
        await st.reload();
      }
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: Text(tr('${h.name} 삭제', 'Delete ${h.name}')),
          content: Text(tr('이 휴미더와 안의 재고 목록이 지워져요. 기록(다이어리)은 남아요.', 'This humidor and its stock list will be removed. Your diary logs stay.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(tr('취소', 'Cancel'))),
            TextButton(onPressed: () => Navigator.pop(dctx, true), child: Text(tr('삭제', 'Delete'))),
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
      content: TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: tr('예: 아도리니, 락앤락', 'e.g. Adorini, Tupperdor'))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx), child: Text(tr('취소', 'Cancel'))),
        TextButton(onPressed: () => Navigator.pop(dctx, c.text.trim()), child: Text(tr('확인', 'OK'))),
      ],
    ),
  );
}

/// 휴미더 간 이동: 몇 개 옮길지 물어보고 옮김. 1개뿐이면 바로. (드래그·⋮ 메뉴 공용)
Future<void> moveStockFlow(BuildContext context, StockItem item, Humidor to) async {
  final st = context.read<AppState>();
  if (item.humidorId == to.id) return;
  var n = item.qty;
  if (item.qty > 1) {
    final picked = await showDialog<int>(
      context: context,
      builder: (dctx) => _MoveQtyDialog(item: item, to: to),
    );
    if (picked == null || picked <= 0) return;
    n = picked;
  }
  await st.db.moveStock(item.id, to.id, n);
  await st.reload();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(tr('${item.cigarName} $n개 → ${to.name}', '$n × ${item.cigarName} → ${to.name}')),
    duration: const Duration(seconds: 2),
  ));
}

class _MoveQtyDialog extends StatefulWidget {
  final StockItem item;
  final Humidor to;
  const _MoveQtyDialog({required this.item, required this.to});
  @override
  State<_MoveQtyDialog> createState() => _MoveQtyDialogState();
}

class _MoveQtyDialogState extends State<_MoveQtyDialog> {
  late int _n = widget.item.qty;
  @override
  Widget build(BuildContext context) {
    final max = widget.item.qty;
    return AlertDialog(
      title: Text(tr('${widget.to.name}(으)로 옮기기', 'Move to ${widget.to.name}')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(widget.item.cigarName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        SubText(tr('재고 $max개 중 몇 개를 옮길까요?', 'Move how many of $max?')),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _QtyBtn(icon: Icons.remove, onTap: () => setState(() => _n = (_n - 1).clamp(1, max))),
          SizedBox(width: 56, child: Text('$_n', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
          _QtyBtn(icon: Icons.add, onTap: () => setState(() => _n = (_n + 1).clamp(1, max))),
        ]),
        const SizedBox(height: 8),
        TextButton(onPressed: () => setState(() => _n = max), child: Text(tr('전부 ($max개)', 'All ($max)'))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('취소', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, _n), child: Text(tr('옮기기', 'Move'))),
      ],
    );
  }
}

/// 드래그 중 손가락을 따라다니는 작은 칩
class _DragChip extends StatelessWidget {
  final StockItem item;
  const _DragChip({required this.item});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: C.text,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.inventory_2_outlined, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text('${item.cigarName} × ${item.qty}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

class _HumidorTab extends StatelessWidget {
  final String label;
  final bool selected;
  final bool highlight; // 드래그 중 올라와 있을 때
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _HumidorTab({required this.label, required this.selected, this.highlight = false, required this.onTap, required this.onLongPress});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: highlight ? C.gold : (selected ? C.accent : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: selected || highlight ? null : Border.all(color: C.line),
        ),
        child: Text(label, style: TextStyle(fontSize: 14, fontWeight: selected || highlight ? FontWeight.w500 : FontWeight.w400, color: selected || highlight ? Colors.white : C.text)),
      ),
    );
  }
}

class _WishChip extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _WishChip({required this.count, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB8A999))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(count > 0 ? Icons.favorite : Icons.favorite_border, size: 16, color: C.accent),
          const SizedBox(width: 6),
          Text(count > 0 ? tr('위시 $count', 'Wish $count') : tr('위시', 'Wish'), style: const TextStyle(fontSize: 13, color: C.accent, fontWeight: FontWeight.w600)),
        ]),
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
      if (item.pricePerStick != null) fmtPrice(item.pricePerStick!, item.currency),
      tr('${fmtShort(item.addedDate)} 입고', 'Added ${fmtShort(item.addedDate)}'),
      tr('${item.agingDays}일 숙성', '${item.agingDays}d aging'),
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
          ListTile(title: Text(item.cigarName, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text(tr('${item.vitola ?? ''} · 재고 ${item.qty}', '${item.vitola ?? ''} · Stock ${item.qty}'))),
          ListTile(
            leading: const Icon(Icons.local_fire_department_outlined),
            title: Text(tr('지금 피우기 → 기록', 'Smoke now → Log')),
            subtitle: Text(tr('저장하면 재고 1개 줄어요', 'Saving removes 1 from stock')),
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
              title: Text(tr('시가 정보 보기', 'View cigar info')),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(cigar: cigar)));
              },
            ),
          if (st.humidors.length > 1)
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: Text(tr('다른 휴미더로 옮기기', 'Move to another humidor')),
              subtitle: Text(tr('카드를 길게 눌러 휴미더 탭에 끌어다 놔도 돼요', 'You can also long-press a card and drag it onto a humidor tab')),
              onTap: () async {
                Navigator.pop(ctx);
                final to = await showModalBottomSheet<Humidor>(
                  context: context,
                  builder: (hctx) => SafeArea(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      ListTile(title: Text(tr('어디로 옮길까요?', 'Move where?'), style: const TextStyle(fontWeight: FontWeight.w600))),
                      for (final h in st.humidors.where((h) => h.id != item.humidorId))
                        ListTile(
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: Text(h.name),
                          subtitle: Text(tr('${st.qtyByHumidor[h.id] ?? 0}개비', '${st.qtyByHumidor[h.id] ?? 0} sticks')),
                          onTap: () => Navigator.pop(hctx, h),
                        ),
                    ]),
                  ),
                );
                if (to != null && context.mounted) await moveStockFlow(context, item, to);
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(tr('이 줄 삭제', 'Delete this entry')),
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
