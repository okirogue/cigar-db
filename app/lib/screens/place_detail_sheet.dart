import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/place_reviews.dart';
import '../l10n.dart';
import '../models/place.dart';
import '../theme.dart';

/// 장소 상세: 정보 · 구글맵 · 평가 쓰기 · 별점 요약 · 코멘트 목록
Future<void> showPlaceDetail(BuildContext context, Place place) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _PlaceDetail(place),
  );
}

String kindLabel(String k) => switch (k) {
      'bar' => tr('시가 바', 'Cigar bar'),
      'lounge' => tr('라운지', 'Lounge'),
      'cafe' => tr('카페', 'Café'),
      _ => k,
    };

class _PlaceDetail extends StatefulWidget {
  final Place place;
  const _PlaceDetail(this.place);
  @override
  State<_PlaceDetail> createState() => _PlaceDetailState();
}

class _PlaceDetailState extends State<_PlaceDetail> {
  final reviews = PlaceReviews.instance;

  @override
  void initState() {
    super.initState();
    reviews.refresh(widget.place.id); // 열 때 그 장소만 최신으로
  }

  Future<void> _write() async {
    final p = widget.place;
    final mine = reviews.mine(p.id);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ReviewForm(place: p, initial: mine),
    );
    if (ok == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.place;
    final mq = MediaQuery.of(context);
    final note = L10n.isKo ? p.note : p.noteEn;
    return ListenableBuilder(
      listenable: reviews,
      builder: (context, _) {
        final list = reviews.of(p.id);
        final (avg, n) = reviews.summary(p.id);
        final mine = reviews.mine(p.id);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (_, ctl) => ListView(
            controller: ctl,
            padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + mq.padding.bottom),
            children: [
              Text(L10n.isKo ? p.name : p.nameEn, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              if (L10n.isKo && p.nameEn != p.name) SubText(p.nameEn),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final k in p.kinds) _tag(kindLabel(k)),
                for (final s in p.smoking) _tag(s == 'indoor' ? tr('실내 흡연', 'Indoor') : tr('실외 흡연', 'Outdoor')),
                if (p.sells == 'yes') _tag(tr('시가 판매', 'Sells cigars')),
                if (p.sells == 'no') _tag(tr('시가 판매 안 함', 'No cigar sales')),
              ]),
              if (note.isNotEmpty) ...[const SizedBox(height: 10), Text(note, style: const TextStyle(fontSize: 14, height: 1.4))],
              if (p.address != null && p.address!.isNotEmpty) ...[const SizedBox(height: 6), SubText(p.address!)],
              const SizedBox(height: 14),
              Builder(builder: (context) {
                final mapBtn = Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFB8A999)), foregroundColor: C.accent),
                    icon: const Icon(Icons.map_outlined, size: 18),
                    onPressed: () => launchUrl(Uri.parse(p.mapsLink), mode: LaunchMode.externalApplication),
                    label: Text(tr('구글맵', 'Google Maps')),
                  ),
                );
                final rateBtn = Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: C.accent),
                    icon: Icon(mine == null ? Icons.star_border : Icons.edit, size: 18),
                    onPressed: _write,
                    label: Text(mine == null ? tr('평가·코멘트', 'Rate & comment') : tr('내 평가 수정', 'Edit my review')),
                  ),
                );
                final hasNaver = p.naverLink != null;
                if (!hasNaver) return Row(children: [mapBtn, const SizedBox(width: 10), rateBtn]);
                // 한국 장소(또는 네이버 링크 있음)면 지도 버튼 두 개를 한 줄에, 평가는 아래 전체 폭
                final naverBtn = Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFB8A999)), foregroundColor: C.accent),
                    icon: const Icon(Icons.place_outlined, size: 18),
                    onPressed: () => launchUrl(Uri.parse(p.naverLink!), mode: LaunchMode.externalApplication),
                    label: Text(tr('네이버지도', 'Naver Map')),
                  ),
                );
                return Column(children: [
                  Row(children: [mapBtn, const SizedBox(width: 10), naverBtn]),
                  const SizedBox(height: 8),
                  Row(children: [rateBtn]),
                ]);
              }),
              const SizedBox(height: 18),
              Row(children: [
                Text(tr('평가', 'Reviews'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                if (avg != null) ...[
                  const Icon(Icons.star, color: C.gold, size: 18),
                  Text(' ${avg.toStringAsFixed(1)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  SubText('  ($n)'),
                ] else if (n > 0)
                  SubText(tr('$n명 평가 · ${PlaceReviews.minForAverage}명부터 평균 표시', '$n rated · average shown from ${PlaceReviews.minForAverage}'))
                else
                  SubText(tr('아직 평가가 없어요', 'No reviews yet')),
              ]),
              const SizedBox(height: 8),
              if (list.isEmpty)
                SubText(tr('다녀오셨다면 첫 평가를 남겨주세요.', 'Been here? Leave the first review.'), size: 12)
              else
                for (final r in list) _ReviewRow(r: r, isMine: mine != null && r.uid == mine.uid),
            ],
          ),
        );
      },
    );
  }

  Widget _tag(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: const TextStyle(fontSize: 11, color: C.accent)),
      );
}

class _ReviewRow extends StatelessWidget {
  final PlaceReview r;
  final bool isMine;
  const _ReviewRow({required this.r, required this.isMine});
  @override
  Widget build(BuildContext context) {
    final d = r.updated;
    final date = d == null ? '' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var i = 1; i <= 5; i++) Icon(i <= r.rating ? Icons.star : Icons.star_border, color: C.gold, size: 15),
          const SizedBox(width: 8),
          SubText(isMine ? tr('나 · $date', 'Me · $date') : tr('익명 · $date', 'Anonymous · $date'), size: 11),
        ]),
        if (r.comment.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(r.comment, style: const TextStyle(fontSize: 14, height: 1.35))),
      ]),
    );
  }
}

class _ReviewForm extends StatefulWidget {
  final Place place;
  final PlaceReview? initial;
  const _ReviewForm({required this.place, this.initial});
  @override
  State<_ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends State<_ReviewForm> {
  late int _rating = widget.initial?.rating ?? 0;
  late final _comment = TextEditingController(text: widget.initial?.comment ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('별점을 골라주세요', 'Pick a star rating'))));
      return;
    }
    setState(() => _busy = true);
    try {
      await PlaceReviews.instance.submit(widget.place.id, _rating, _comment.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('보내지 못했어요. 네트워크를 확인해 주세요.', 'Could not send. Check your network.'))));
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await PlaceReviews.instance.remove(widget.place.id);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottom = mq.viewInsets.bottom + mq.padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(L10n.isKo ? widget.place.name : widget.place.nameEn, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        SubText(tr('익명으로 올라가요. 한 장소에 하나, 다시 쓰면 수정돼요.', 'Posted anonymously. One per place; writing again updates it.'), size: 12),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              iconSize: 36,
              icon: Icon(i <= _rating ? Icons.star : Icons.star_border, color: C.gold),
              onPressed: () => setState(() => _rating = i),
            ),
        ]),
        const SizedBox(height: 6),
        TextField(
          controller: _comment,
          maxLines: 3,
          maxLength: 200,
          decoration: InputDecoration(labelText: tr('코멘트 (선택)', 'Comment (optional)'), hintText: tr('분위기, 가격대, 추천 메뉴…', 'Vibe, prices, what to order…')),
        ),
        const SizedBox(height: 10),
        Row(children: [
          if (widget.initial != null)
            TextButton(onPressed: _busy ? null : _delete, child: Text(tr('삭제', 'Delete'), style: const TextStyle(color: C.sub))),
          const Spacer(),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.accent),
            onPressed: _busy ? null : _send,
            child: Text(_busy ? tr('보내는 중…', 'Sending…') : (widget.initial == null ? tr('올리기', 'Post') : tr('수정', 'Update'))),
          ),
        ]),
      ]),
    );
  }
}
