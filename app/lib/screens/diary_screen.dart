import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/local.dart';
import '../state.dart';
import '../theme.dart';
import 'badges_screen.dart';
import 'detail_screen.dart';
import 'record_screen.dart';

enum DiarySort { recent, score }

class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key});
  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  DiarySort _sort = DiarySort.recent;

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final logs = [...st.logs];
    if (_sort == DiarySort.score) {
      logs.sort((a, b) => b.score != a.score ? b.score.compareTo(a.score) : b.date.compareTo(a.date));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('다이어리', style: TextStyle(fontSize: 24)),
        actions: [
          IconButton(
            icon: const Icon(Icons.military_tech_outlined),
            tooltip: '내 업적',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BadgesScreen())),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Center(child: SubText(logs.isEmpty ? '' : '${logs.length}회 · 평균 ${st.avgScore.round()}점', size: 14)),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const SubText('정렬'),
            const SizedBox(width: 8),
            PillChip(label: '최근순', dark: true, selected: _sort == DiarySort.recent, onTap: () => setState(() => _sort = DiarySort.recent)),
            const SizedBox(width: 8),
            PillChip(label: '점수순', dark: true, selected: _sort == DiarySort.score, onTap: () => setState(() => _sort = DiarySort.score)),
          ]),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: logs.isEmpty
              ? const Center(child: SubText('첫 기록을 남겨보세요. 아래 + 기록', size: 13))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  itemCount: logs.length,
                  itemBuilder: (_, i) {
                    final l = logs[i];
                    final showHeader = _sort == DiarySort.recent && (i == 0 || logs[i - 1].date != l.date);
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (showHeader) Padding(padding: EdgeInsets.only(top: i == 0 ? 4 : 10, bottom: 8), child: SubText(_dateLabel(l.date))),
                      Padding(padding: const EdgeInsets.only(bottom: 10), child: _LogCard(log: l)),
                    ]);
                  },
                ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: C.accent,
        foregroundColor: Colors.white,
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecordScreen())),
        label: const Text('+ 기록'),
      ),
    );
  }

  String _dateLabel(String ymdStr) {
    final d = DateTime.tryParse(ymdStr);
    if (d == null) return ymdStr;
    const wd = ['월', '화', '수', '목', '금', '토', '일'];
    final year = d.year == DateTime.now().year ? '' : '${d.year}년 ';
    return '$year${d.month}월 ${d.day}일 (${wd[d.weekday - 1]})';
  }
}

class _LogCard extends StatelessWidget {
  final SmokeLog log;
  const _LogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final sub = <String>[
      if (log.vitola != null && log.vitola!.isNotEmpty) log.vitola!,
      if (log.place != null) log.place!,
      if (log.pairing != null) log.pairing!,
    ];
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Thumb(size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(log.cigarName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
                  Text('${log.score}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: C.accent)),
                ]),
                if (sub.isNotEmpty) SubText(sub.join(' · ')),
                if (log.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final t in log.tags.take(6)) NoteChip(label: st.repo.tagKo(t), small: true)]),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    final st = context.read<AppState>();
    final repo = st.repo;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, ctl) => ListView(
          controller: ctl,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Row(children: [
              Expanded(child: Text(log.cigarName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              Text('${log.score}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: C.accent)),
            ]),
            SubText([log.date, if (log.vitola != null) log.vitola!, if (log.place != null) log.place!, if (log.pairing != null) log.pairing!].join(' · '), size: 13),
            const SizedBox(height: 14),
            if (log.tags.isNotEmpty) ...[
              const Text('느낀 노트', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final t in log.tags) NoteChip(label: repo.tagKo(t))]),
              const SizedBox(height: 14),
            ],
            for (final e in [('초반', log.noteStart), ('중반', log.noteMid), ('후반', log.noteEnd)])
              if (e.$2 != null && e.$2!.isNotEmpty) ...[
                Text(e.$1, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 4),
                Text(e.$2!, style: const TextStyle(fontSize: 14, height: 1.5)),
                const SizedBox(height: 12),
              ],
            const SizedBox(height: 8),
            Row(children: [
              if (repo.byId(log.cigarId) != null)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(cigar: repo.byId(log.cigarId)!)));
                    },
                    child: const Text('시가 정보'),
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: ctx,
                      builder: (dctx) => AlertDialog(
                        title: const Text('기록 삭제'),
                        content: const Text('이 기록을 지울까요? 재고는 되돌리지 않아요.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('취소')),
                          TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('삭제')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await st.db.deleteLog(log.id);
                      await st.reload();
                      if (ctx.mounted) Navigator.pop(ctx);
                    }
                  },
                  child: const Text('삭제'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
