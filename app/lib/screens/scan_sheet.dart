import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/scan_service.dart';
import '../l10n.dart';
import '../models/cigar.dart';
import '../state.dart';
import '../theme.dart';

/// 카메라 → 인식 → 후보 선택. 선택한 Cigar를 돌려준다 (없으면 null).
Future<Cigar?> runScan(BuildContext context) async {
  final st = context.read<AppState>();
  final svc = ScanService.instance;
  final sm = ScaffoldMessenger.of(context);

  if (!svc.ready) {
    sm.showSnackBar(SnackBar(content: Text(tr('스캔 서버에 연결되지 않았어요. 잠시 후 다시 시도해 주세요.', 'Could not reach the scan server. Please try again later.'))));
    return null;
  }
  final left = await svc.remaining();
  if (left <= 0) {
    sm.showSnackBar(SnackBar(content: Text(tr('오늘 스캔 3회를 다 썼어요. 내일 다시 열려요.', 'You have used all 3 scans for today. Try again tomorrow.'))));
    return null;
  }

  final photo = await svc.takePhoto();
  if (photo == null || !context.mounted) return null;

  // 진행 다이얼로그
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(children: [
        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent)),
        const SizedBox(width: 16),
        Expanded(child: Text(tr('밴드를 읽는 중…', 'Reading the band…'), style: const TextStyle(fontSize: 14))),
      ]),
    ),
  );
  ScanResult? result;
  String? err;
  try {
    result = await svc.recognize(photo, st.repo);
  } catch (e) {
    err = e.toString();
  }
  if (!context.mounted) return null;
  Navigator.pop(context); // 진행 다이얼로그 닫기
  if (err != null) {
    sm.showSnackBar(SnackBar(content: Text(err)));
    return null;
  }
  final r = result!;
  final remain = left - 1;

  return showModalBottomSheet<Cigar>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(tr('밴드 인식 결과', 'Band scan result'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            SubText(tr('오늘 $remain회 남음', '$remain left today'), size: 11),
          ]),
          const SizedBox(height: 4),
          SubText(
            r.readName.isEmpty
                ? tr('읽은 글자: ${r.rawText}', 'Text read: ${r.rawText}')
                : tr(
                    '읽음: ${r.readName}${r.vitola != null ? ' · ${r.vitola}' : ''} (확신 ${(r.confidence * 100).round()}%)',
                    'Read: ${r.readName}${r.vitola != null ? ' · ${r.vitola}' : ''} (${(r.confidence * 100).round()}% confidence)',
                  ),
            size: 12,
          ),
          const SizedBox(height: 12),
          if (r.candidates.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: SubText(tr('DB에서 일치하는 시가를 못 찾았어요. 검색창에 직접 입력해 주세요.', 'No matching cigar in the database. Try typing it in the search box.'), size: 13))
          else
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final c in r.candidates.take(6))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CigarThumb(size: 40),
                    title: Text(c.fullName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                    subtitle: SubText([if (c.cuban) tr('쿠바', 'Cuban'), if (c.specs['strength'] != null) c.specs['strength']!, if (c.hasNotes) tr('노트 有', 'Has notes')].join(' · ')),
                    onTap: () => Navigator.pop(ctx, c),
                  ),
              ]),
            ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('여기 없음 · 직접 검색', 'Not here · search manually'))),
        ]),
      ),
    ),
  );
}
