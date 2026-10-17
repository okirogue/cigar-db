import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../models/cigar.dart';
import '../models/local.dart';
import '../state.dart';
import '../theme.dart';
import 'add_stock_screen.dart';
import 'detail_screen.dart';
import 'picker_screen.dart';

/// 위시리스트 하트 토글 (상세·탐색·추천 카드에서 공용)
class WishButton extends StatelessWidget {
  final Cigar cigar;
  final double size;
  const WishButton({super.key, required this.cigar, this.size = 22});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final on = st.inWishlist(cigar.id);
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: on ? tr('위시리스트에서 빼기', 'Remove from wishlist') : tr('위시리스트에 넣기', 'Add to wishlist'),
      icon: Icon(on ? Icons.favorite : Icons.favorite_border, size: size, color: on ? C.accent : C.hint),
      onPressed: () async {
        final added = await st.toggleWish(cigar);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(added ? tr('위시리스트에 넣었어요', 'Added to wishlist') : tr('위시리스트에서 뺐어요', 'Removed from wishlist')),
            action: added ? SnackBarAction(label: tr('보기', 'View'), onPressed: () => openWishlistSheet(context)) : null,
          ));
      },
    );
  }
}

/// 위시리스트 시트: 다음에 살 것 목록. 우선순위·메모, "입고했어요" → 재고로, 텍스트 복사.
Future<void> openWishlistSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => const _WishlistSheet(),
  );
}

class _WishlistSheet extends StatelessWidget {
  const _WishlistSheet();

  static String _priLabel(int p) => p >= 2 ? tr('꼭', 'Must') : p <= 0 ? tr('언젠가', 'Someday') : tr('보통', 'Normal');

  String _asText(List<WishItem> items) {
    final b = StringBuffer(tr('🛒 위시리스트', '🛒 Wishlist'));
    b.writeln();
    for (final w in items) {
      final v = (w.vitola ?? '').isNotEmpty ? ' · ${w.vitola}' : '';
      final m = (w.memo ?? '').isNotEmpty ? ' — ${w.memo}' : '';
      b.writeln('${w.priority >= 2 ? '★ ' : ''}${w.cigarName}$v$m');
    }
    b.writeln();
    b.write('— MyHumidor');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final items = st.wishlist;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (ctx, ctrl) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
          child: Row(children: [
            Text(tr('위시리스트', 'Wishlist'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(width: 8),
            SubText(tr('${items.length}종', '${items.length}'), size: 12),
            const Spacer(),
            if (items.isNotEmpty)
              IconButton(
                tooltip: tr('텍스트로 복사', 'Copy as text'),
                icon: const Icon(Icons.copy_outlined, size: 20),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _asText(items)));
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(tr('복사했어요', 'Copied'))));
                },
              ),
            IconButton(
              tooltip: tr('시가 찾아서 추가', 'Add a cigar'),
              icon: const Icon(Icons.add, size: 22),
              onPressed: () async {
                final r = await PickerScreen.open(context, showStock: false);
                if (r == null || !context.mounted) return;
                await st.db.addWish(cigarId: r.id, cigarName: r.name, vitola: r.vitola);
                await st.reload();
              },
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SubText(tr('다음에 살 시가. 탐색·상세·추천의 ♡ 로도 넣을 수 있어요. 길게 누르면 메모·우선순위.', 'Cigars to buy next. Use ♡ in explore/details/recommendations. Long-press for memo & priority.'), size: 11),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: items.isEmpty
              ? Center(child: SubText(tr('아직 비어 있어요', 'Nothing here yet'), size: 13))
              : ListView.separated(
                  controller: ctrl,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final w = items[i];
                    final c = st.repo.byId(w.cigarId);
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: Icon(w.priority >= 2 ? Icons.star : Icons.star_border, color: w.priority >= 2 ? C.accent : C.hint, size: 20),
                      title: Text(w.cigarName, style: const TextStyle(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [
                          if ((w.vitola ?? '').isNotEmpty) w.vitola!,
                          _priLabel(w.priority),
                          if ((w.memo ?? '').isNotEmpty) w.memo!,
                        ].join(' · '),
                        style: const TextStyle(fontSize: 11, color: C.sub),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Wrap(spacing: 0, children: [
                        if (st.humidors.isNotEmpty)
                          TextButton(
                            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                            onPressed: c == null
                                ? null
                                : () async {
                                    // 입고했어요: 재고 추가 화면으로, 저장되면 위시에서 뺀다
                                    final ok = await Navigator.push<bool>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AddStockScreen(initialHumidorId: st.humidors.first.id, preset: PickResult(cigar: c, vitola: w.vitola)),
                                      ),
                                    );
                                    // 저장되면 AddStockScreen 이 해당 시가의 위시를 지운다
                                    if (ok == true) await st.reload();
                                  },
                            child: Text(tr('입고', 'Got it'), style: const TextStyle(fontSize: 12)),
                          ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 18, color: C.hint),
                          onPressed: () async {
                            await st.db.deleteWish(w.id);
                            await st.reload();
                          },
                        ),
                      ]),
                      onTap: c == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(cigar: c))),
                      onLongPress: () => _editWish(context, st, w),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Future<void> _editWish(BuildContext context, AppState st, WishItem w) async {
    final memo = TextEditingController(text: w.memo ?? '');
    final vitola = TextEditingController(text: w.vitola ?? '');
    var pri = w.priority;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setD) => AlertDialog(
          title: Text(w.cigarName, style: const TextStyle(fontSize: 15)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: vitola, decoration: InputDecoration(labelText: tr('비톨라', 'Vitola'))),
            const SizedBox(height: 8),
            TextField(controller: memo, decoration: InputDecoration(labelText: tr('메모 (어디서 얼마에 등)', 'Memo (where, price…)')), maxLines: 2),
            const SizedBox(height: 12),
            Wrap(spacing: 6, children: [
              for (final p in [2, 1, 0]) ChoiceChip(label: Text(_priLabel(p)), selected: pri == p, onSelected: (_) => setD(() => pri = p)),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(tr('취소', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(dctx, true), child: Text(tr('저장', 'Save'))),
          ],
        ),
      ),
    );
    final v = vitola.text.trim(), m = memo.text.trim();
    memo.dispose();
    vitola.dispose();
    if (ok != true) return;
    await st.db.updateWish(w.id, vitola: v, memo: m, priority: pri);
    await st.reload();
  }
}
