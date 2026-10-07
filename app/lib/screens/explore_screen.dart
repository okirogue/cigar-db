import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/cigar_repo.dart';
import '../models/cigar.dart';
import '../state.dart';
import '../theme.dart';
import 'detail_screen.dart';
import 'custom_cigar_sheet.dart';

/// 탐색: 시가 검색 → 상세. 검색 전엔 내가 피운/보유한 시가와 브랜드 바로가기.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _c = TextEditingController();
  String _q = '';
  bool _cubanOnly = false;
  bool _notesOnly = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final repo = st.repo;
    var results = _q.trim().isEmpty ? <Cigar>[] : repo.search(_q, limit: 80);
    if (_cubanOnly) results = results.where((c) => c.cuban).toList();
    if (_notesOnly) results = results.where((c) => c.hasNotes).toList();

    final recentIds = <String>[];
    for (final l in st.logs) {
      if (!recentIds.contains(l.cigarId) && repo.byId(l.cigarId) != null) recentIds.add(l.cigarId);
      if (recentIds.length >= 8) break;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('탐색', style: TextStyle(fontSize: 24)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _c,
                decoration: InputDecoration(
                  hintText: '브랜드·라인 검색 (영문)',
                  prefixIcon: const Icon(Icons.search, color: C.sub),
                  suffixIcon: _q.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() {
                            _c.clear();
                            _q = '';
                          })),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            PillChip(label: '쿠반만', selected: _cubanOnly, onTap: () => setState(() => _cubanOnly = !_cubanOnly)),
            const SizedBox(width: 8),
            PillChip(label: '노트 있는 것만', selected: _notesOnly, onTap: () => setState(() => _notesOnly = !_notesOnly)),
            const Spacer(),
            SubText('DB ${repo.all.length}라인', size: 11),
          ]),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _q.trim().isEmpty
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    if (recentIds.isNotEmpty) ...[
                      const SubText('최근 피운 시가'),
                      const SizedBox(height: 6),
                      for (final id in recentIds) _CigarRow(cigar: repo.byId(id)!),
                      const SizedBox(height: 10),
                    ],
                    const SubText('브랜드 바로가기'),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final b in _topBrands(repo))
                        PillChip(
                          label: b,
                          onTap: () => setState(() {
                            _c.text = b;
                            _q = b;
                          }),
                        ),
                    ]),
                  ],
                )
              : results.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const SubText('검색 결과가 없어요', size: 13),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFB8A999)), foregroundColor: C.accent),
                          icon: const Icon(Icons.add, size: 18),
                          onPressed: () async {
                            final c = await addCustomCigar(context, initial: _q.trim());
                            if (c != null && context.mounted) setState(() {});
                          },
                          label: const Text('직접 추가'),
                        ),
                      ]),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: results.length,
                      itemBuilder: (_, i) => _CigarRow(cigar: results[i]),
                    ),
        ),
      ]),
    );
  }

  List<String> _topBrands(CigarRepo repo) {
    final counts = repo.brandLineCounts();
    final list = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return list.take(18).map((e) => e.key).toList();
  }
}

class _CigarRow extends StatelessWidget {
  final Cigar cigar;
  const _CigarRow({required this.cigar});
  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final smoked = st.smokedIds.contains(cigar.id);
    final sub = <String>[
      if (cigar.cuban) '쿠바',
      if (cigar.specs['strength'] != null) cigar.specs['strength']!,
      if (cigar.vitolas.isNotEmpty) '${cigar.vitolas.length}종',
      if (cigar.dojoScore != null) 'Dojo ${cigar.dojoScore}',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(cigar: cigar))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              const CigarThumb(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(cigar.fullName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  if (sub.isNotEmpty) SubText(sub.join(' · ')),
                ]),
              ),
              if (smoked) const Icon(Icons.check_circle, color: C.accent, size: 18),
              if (cigar.hasNotes && !smoked)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(6)),
                  child: Text('노트 ${cigar.allTags.length}', style: const TextStyle(fontSize: 11, color: C.accent)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
