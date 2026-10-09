import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/backup.dart';
import '../data/cigar_repo.dart';
import '../data/photos.dart';
import '../data/share_stats.dart';
import '../l10n.dart';
import '../models/local.dart';
import '../state.dart';
import '../theme.dart';
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
        title: Text(tr('다이어리', 'Diary'), style: const TextStyle(fontSize: 24)),
        actions: [
          Center(child: SubText(logs.isEmpty ? '' : tr('${logs.length}회 · 평균 ${fmtScore(st.avgScore)}점', '${logs.length} smoked · avg ${fmtScore(st.avgScore)}'), size: 14)),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) => _menu(context, v),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'export', child: Text(tr('백업 내보내기 (JSON)', 'Export backup (JSON)'))),
              PopupMenuItem(value: 'import', child: Text(tr('가져오기 — 기존에 추가', 'Import — add to existing'))),
              PopupMenuItem(value: 'replace', child: Text(tr('가져오기 — 전부 덮어쓰기', 'Import — replace all'))),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'share', child: Text(tr('익명 기록 공유 설정', 'Anonymous sharing settings'))),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            SubText(tr('정렬', 'Sort')),
            const SizedBox(width: 8),
            PillChip(label: tr('최근순', 'Recent'), dark: true, selected: _sort == DiarySort.recent, onTap: () => setState(() => _sort = DiarySort.recent)),
            const SizedBox(width: 8),
            PillChip(label: tr('점수순', 'Score'), dark: true, selected: _sort == DiarySort.score, onTap: () => setState(() => _sort = DiarySort.score)),
          ]),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: logs.isEmpty
              ? Center(child: SubText(tr('첫 기록을 남겨보세요. 아래 + 기록', 'Write your first log with + Log below'), size: 13))
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
        label: Text(tr('+ 기록', '+ Log')),
      ),
    );
  }

  Future<void> _menu(BuildContext context, String v) async {
    final st = context.read<AppState>();
    final sm = ScaffoldMessenger.of(context);
    if (v == 'share') {
      final cur = await ShareStats.instance.enabled ?? false;
      if (!context.mounted) return;
      final on = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: Text(tr('익명 기록 공유', 'Anonymous sharing')),
          content: Text(
            tr(
              '${cur ? '지금 켜져 있어요.' : '지금 꺼져 있어요.'}\n\n켜면 기록 저장 시 시가 이름·점수·노트 태그·날짜만 익명으로 모아 커뮤니티 평점에 써요. 메모·장소·페어링은 보내지 않아요.\n끄면 이미 올라간 내 기록도 서버에서 지워요.',
              '${cur ? 'Currently on.' : 'Currently off.'}\n\nWhen on, only the cigar name, score, note tags and date are collected anonymously for community ratings. Memo, place and pairing are never sent.\nWhen off, your logs already uploaded are deleted from the server.',
            ),
            style: const TextStyle(fontSize: 13.5, height: 1.5),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(tr('끄기', 'Turn off'))),
            FilledButton(onPressed: () => Navigator.pop(dctx, true), child: Text(tr('켜기', 'Turn on'))),
          ],
        ),
      );
      if (on == null) return;
      await ShareStats.instance.set(on);
      if (on) {
        await ShareStats.instance.backfill(st.logs);
      } else {
        for (final l in st.logs) {
          await ShareStats.instance.removeForce(l.id);
        }
      }
      sm.showSnackBar(SnackBar(
          content: Text(on
              ? tr('익명 공유 켬 — 기존 기록도 올렸어요', 'Anonymous sharing on — existing logs uploaded')
              : tr('익명 공유 끔 — 서버의 내 기록을 지웠어요', 'Anonymous sharing off — your logs removed from the server'))));
      return;
    }
    try {
      if (v == 'export') {
        await Backup.export(st);
        return;
      }
      if (v == 'replace') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (dctx) => AlertDialog(
            title: Text(tr('전부 덮어쓰기', 'Replace all')),
            content: Text(tr('지금 앱에 있는 휴미더·재고·기록을 모두 지우고 파일 내용으로 바꿔요. 되돌릴 수 없어요.',
                'All humidors, stock and logs in the app will be deleted and replaced with the file contents. This cannot be undone.')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(tr('취소', 'Cancel'))),
              TextButton(onPressed: () => Navigator.pop(dctx, true), child: Text(tr('덮어쓰기', 'Replace'))),
            ],
          ),
        );
        if (ok != true) return;
      }
      final r = await Backup.import(st, replace: v == 'replace');
      if (r == null) return;
      sm.showSnackBar(SnackBar(
          content: Text(tr('가져옴 — 휴미더 ${r.$1} · 재고 ${r.$2}줄 · 기록 ${r.$3}건',
              'Imported — ${r.$1} humidors · ${r.$2} stock rows · ${r.$3} logs'))));
    } catch (e) {
      sm.showSnackBar(SnackBar(content: Text(tr('실패: 파일 형식을 확인해 주세요 ($e)', 'Failed: please check the file format ($e)'))));
    }
  }

  String _dateLabel(String ymdStr) {
    final d = DateTime.tryParse(ymdStr);
    if (d == null) return ymdStr;
    if (!L10n.isKo) {
      const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      const wdEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final yearEn = d.year == DateTime.now().year ? '' : ', ${d.year}';
      return '${wdEn[d.weekday - 1]}, ${mon[d.month - 1]} ${d.day}$yearEn';
    }
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
            const CigarThumb(size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(log.cigarName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
                  Text(fmtScore(log.score), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: C.accent)),
                ]),
                if (log.hasStockInfo) ...[
                  const SizedBox(height: 4),
                  _StockInfoRow(log: log, small: true),
                  const SizedBox(height: 4),
                ],
                if (sub.isNotEmpty) SubText(sub.join(' · ')),
                if (log.summary != null && log.summary!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(log.summary!, style: const TextStyle(fontSize: 13.5, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                if (log.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final t in log.tags.take(6)) NoteChip(label: st.repo.tagName(t), small: true)]),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  void _open(BuildContext context) => openLogSheet(context, log);
}

/// 기록 상세 바텀시트 (목록·지도에서 공용)
void openLogSheet(BuildContext context, SmokeLog log) {
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
          // 하단: 안드로이드 내비게이션 바(제스처 영역)에 버튼이 가리지 않게 안전영역만큼 더
          padding: EdgeInsets.fromLTRB(20, 16, 20, 32 + MediaQuery.paddingOf(ctx).bottom),
          children: [
            Row(children: [
              Expanded(child: Text(log.cigarName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              Text(fmtScore(log.score), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: C.accent)),
            ]),
            if (log.hasStockInfo) ...[
              const SizedBox(height: 6),
              _StockInfoRow(log: log),
              const SizedBox(height: 6),
            ],
            SubText([log.date, if (log.vitola != null) log.vitola!, if (log.place != null) log.place!, if (log.pairing != null) log.pairing!].join(' · '), size: 13),
            const SizedBox(height: 14),
            if (LogPhotos.supported && log.photos.isNotEmpty) ...[
              _PhotoStrip(photos: log.photos),
              const SizedBox(height: 14),
            ],
            if (log.tags.isNotEmpty) ...[
              Text(tr('느낀 노트', 'Notes'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final t in log.tags) NoteChip(label: repo.tagName(t))]),
              const SizedBox(height: 14),
            ],
            if (log.summary != null && log.summary!.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(12)),
                child: Text(log.summary!, style: const TextStyle(fontSize: 14.5, height: 1.5, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(height: 14),
            ],
            for (final e in [
              (tr('초반', 'First third'), log.noteStart),
              (tr('중반', 'Second third'), log.noteMid),
              (tr('후반', 'Final third'), log.noteEnd),
            ])
              if (e.$2 != null && e.$2!.isNotEmpty) ...[
                Text(e.$1, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 4),
                Text(e.$2!, style: const TextStyle(fontSize: 14, height: 1.5)),
                const SizedBox(height: 12),
              ],
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => RecordScreen(edit: log)));
                  },
                  child: Text(tr('수정', 'Edit')),
                ),
              ),
              const SizedBox(width: 8),
              if (repo.byId(log.cigarId) != null)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(cigar: repo.byId(log.cigarId)!)));
                    },
                    child: Text(tr('시가 정보', 'Cigar info')),
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
                        title: Text(tr('기록 삭제', 'Delete log')),
                        content: Text(tr('이 기록을 지울까요? 재고는 되돌리지 않아요.', 'Delete this log? Stock will not be restored.')),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(tr('취소', 'Cancel'))),
                          TextButton(onPressed: () => Navigator.pop(dctx, true), child: Text(tr('삭제', 'Delete'))),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await LogPhotos.instance.deleteAll(log.photos);
                      await st.db.deleteLog(log.id);
                      ShareStats.instance.remove(log.id);
                      await st.reload();
                      if (ctx.mounted) Navigator.pop(ctx);
                    }
                  },
                  child: Text(tr('삭제', 'Delete')),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            // 카페·레딧에 붙여넣기용 텍스트
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: Text(tr('텍스트로 공유', 'Share as text')),
                  onPressed: () => _shareLogText(ctx, log, repo),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: Text(tr('복사', 'Copy')),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: logToText(log, repo)));
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(tr('복사했어요', 'Copied'))));
                },
              ),
            ]),
            // 같은 시가의 다른 기록
            ...() {
              final all = st.logs.where((l) => l.cigarId == log.cigarId).toList()..sort((a, b) => b.date.compareTo(a.date));
              final others = all.where((l) => l.id != log.id).toList();
              if (others.isEmpty) return const <Widget>[];
              final avg = all.fold<double>(0, (a, l) => a + l.score) / all.length;
              final lo = fmtScore(all.map((l) => l.score).reduce(min)), hi = fmtScore(all.map((l) => l.score).reduce(max));
              return <Widget>[
                const SizedBox(height: 22),
                // 내 평균
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: C.text, borderRadius: BorderRadius.circular(14)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('내 평균', 'My average'), style: const TextStyle(fontSize: 11, color: Colors.white70)),
                      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(fmtScore((avg * 2).round() / 2), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: C.bg, height: 1.1)),
                        const SizedBox(width: 6),
                        Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(tr('${all.length}회', '${all.length}x'), style: const TextStyle(fontSize: 12, color: Colors.white70))),
                      ]),
                    ]),
                    const Spacer(),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(lo == hi ? tr('매번 $lo', 'Always $lo') : tr('최저 $lo · 최고 $hi', 'Low $lo · High $hi'), style: const TextStyle(fontSize: 12, color: Colors.white70)),
                      const SizedBox(height: 6),
                      // 점수 미니 막대 (최근 → 과거 순으로 최대 8개)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        for (final l in all.take(8).toList().reversed)
                          Container(
                            width: 8,
                            height: 6 + (l.score - 5).clamp(0, 5) * 4,
                            margin: const EdgeInsets.only(left: 3),
                            decoration: BoxDecoration(
                              color: l.id == log.id ? C.gold : C.bg.withValues(alpha: .55),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                      ]),
                    ]),
                  ]),
                ),
                const SizedBox(height: 14),
                Text(tr('이 시가의 다른 기록 ${others.length}회', '${others.length} other logs of this cigar'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 6),
                for (final o in others)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      Navigator.pop(ctx);
                      openLogSheet(context, o);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(children: [
                        Text(fmtScore(o.score), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: C.accent)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SubText([o.date, if (o.vitola != null && o.vitola!.isNotEmpty) o.vitola!, if (o.place != null) o.place!].join(' · '), size: 12),
                            if (o.summary != null && o.summary!.isNotEmpty)
                              Text(o.summary!, style: const TextStyle(fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis)
                            else if (o.tags.isNotEmpty)
                              Text(o.tags.take(5).map(repo.tagName).join(' · '), style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                        const Icon(Icons.chevron_right, size: 18, color: C.hint),
                      ]),
                    ),
                  ),
              ];
            }(),
          ],
        ),
      ),
    );
}

/// 기록 상세의 사진 띠 (가로 스크롤, 탭하면 크게)
class _PhotoStrip extends StatelessWidget {
  final List<String> photos;
  const _PhotoStrip({required this.photos});

  @override
  Widget build(BuildContext context) {
    final single = photos.length == 1;
    return SizedBox(
      height: single ? 220 : 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => FutureBuilder<File>(
          future: LogPhotos.instance.file(photos[i]),
          builder: (ctx, snap) {
            if (!snap.hasData) return Container(width: 160, decoration: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(12)));
            final f = snap.data!;
            return GestureDetector(
              onTap: () => showDialog<void>(
                context: ctx,
                builder: (d) => Dialog(
                  backgroundColor: Colors.black,
                  insetPadding: const EdgeInsets.all(8),
                  child: GestureDetector(onTap: () => Navigator.pop(d), child: InteractiveViewer(child: Image.file(f, fit: BoxFit.contain))),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: single
                    ? SizedBox(width: MediaQuery.of(ctx).size.width - 40, child: Image.file(f, fit: BoxFit.cover))
                    : Image.file(f, width: 160, height: 160, fit: BoxFit.cover),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 기록 → 붙여넣기용 텍스트 (카페·레딧). 비어 있는 항목은 뺀다.
String logToText(SmokeLog log, CigarRepo repo) {
  final ko = L10n.isKo;
  final b = StringBuffer();
  final title = log.vitola != null && log.vitola!.isNotEmpty ? '${log.cigarName} · ${log.vitola}' : log.cigarName;
  b.writeln('🚬 $title');
  final meta = [log.date, if (log.place != null && log.place!.isNotEmpty) log.place!, if (log.pairing != null && log.pairing!.isNotEmpty) log.pairing!];
  b.writeln(meta.join(' · '));
  final stockParts = stockInfoParts(log);
  if (stockParts.isNotEmpty) b.writeln('🗄 ${stockParts.join(' · ')}');
  b.writeln('⭐ ${fmtScore(log.score)} / 10');
  if (log.tags.isNotEmpty) {
    b.writeln();
    b.writeln('${ko ? '노트' : 'Notes'}: ${log.tags.map(repo.tagName).join(' · ')}');
  }
  final thirds = [
    (ko ? '초반' : 'First third', log.noteStart),
    (ko ? '중반' : 'Second third', log.noteMid),
    (ko ? '후반' : 'Final third', log.noteEnd),
  ].where((e) => e.$2 != null && e.$2!.trim().isNotEmpty).toList();
  if (thirds.isNotEmpty) {
    b.writeln();
    for (final t in thirds) {
      b.writeln('${t.$1}: ${t.$2!.trim()}');
    }
  }
  if (log.summary != null && log.summary!.trim().isNotEmpty) {
    b.writeln();
    b.writeln('${ko ? '한마디' : 'Verdict'}: ${log.summary!.trim()}');
  }
  b.writeln();
  b.write('— MyHumidor');
  return b.toString();
}

Future<void> _shareLogText(BuildContext ctx, SmokeLog log, CigarRepo repo) async {
  final text = logToText(log, repo);
  try {
    // 사진이 있으면 같이 실어 보냄 (받는 앱에 따라 텍스트만/사진만 받을 수 있음)
    if (LogPhotos.supported && log.photos.isNotEmpty) {
      final files = <XFile>[];
      for (final n in log.photos) {
        final f = await LogPhotos.instance.file(n);
        if (await f.exists()) files.add(XFile(f.path, mimeType: 'image/jpeg'));
      }
      if (files.isNotEmpty) {
        await Share.shareXFiles(files, text: text, subject: log.cigarName);
        return;
      }
    }
    await Share.share(text, subject: log.cigarName);
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(tr('복사했어요', 'Copied'))));
  }
}

/// 재고에서 기록한 로그의 구매가·입고일·숙성 기간 (없는 항목은 생략)
List<String> stockInfoParts(SmokeLog log) {
  final out = <String>[];
  if (log.stockPrice != null) out.add(fmtPrice(log.stockPrice!, log.stockCurrency ?? 'KRW'));
  if (log.stockAdded != null) out.add(tr('입고 ${fmtShort(log.stockAdded!)}', 'Added ${fmtShort(log.stockAdded!)}'));
  final aged = log.agingDaysAtSmoke;
  if (aged != null) out.add(tr('숙성 $aged일', 'Aged ${aged}d'));
  return out;
}

/// 구매가 · 입고일 · 숙성 — 작은 알약 모양으로 한 줄
class _StockInfoRow extends StatelessWidget {
  final SmokeLog log;
  final bool small;
  const _StockInfoRow({required this.log, this.small = false});

  @override
  Widget build(BuildContext context) {
    final parts = stockInfoParts(log);
    if (parts.isEmpty) return const SizedBox.shrink();
    final fs = small ? 11.0 : 12.5;
    final pad = small ? const EdgeInsets.symmetric(horizontal: 7, vertical: 2) : const EdgeInsets.symmetric(horizontal: 9, vertical: 3);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(Icons.inventory_2_outlined, size: small ? 12 : 14, color: C.accent),
        for (final p in parts)
          Container(
            padding: pad,
            decoration: BoxDecoration(color: C.accent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(6)),
            child: Text(p, style: TextStyle(fontSize: fs, color: C.accent, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }
}
