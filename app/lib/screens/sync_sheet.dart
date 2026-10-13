import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/sync.dart';
import '../l10n.dart';
import '../state.dart';
import '../theme.dart';

/// 운영자 전용 동기화 설정 시트. 다른 사용자가 열어도 로그인은 운영자 계정만 통과한다.
Future<void> openSyncSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _SyncSheet(),
  );
}

class _SyncSheet extends StatefulWidget {
  const _SyncSheet();
  @override
  State<_SyncSheet> createState() => _SyncSheetState();
}

class _SyncSheetState extends State<_SyncSheet> {
  bool _busy = false;
  String? _msg;
  late Future<(bool, DateTime?)> _info = _load();

  Future<(bool, DateTime?)> _load() async => (await Sync.instance.enabled, await Sync.instance.lastSyncedAt);

  @override
  Widget build(BuildContext context) {
    final sync = Sync.instance;
    final signed = sync.signedIn;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.paddingOf(context).bottom),
      child: FutureBuilder<(bool, DateTime?)>(
        future: _info,
        builder: (ctx, snap) {
          final on = snap.data?.$1 ?? false;
          final at = snap.data?.$2;
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('운영자 동기화', 'Maintainer sync'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            SubText(
              tr('운영자 본인 계정(${Sync.operatorEmail})으로만 쓸 수 있는 기능이에요. 폰과 PC 웹판 사이에 휴미더·기록을 맞춰요(사진 제외).',
                  'Only the maintainer account (${Sync.operatorEmail}) can use this. Keeps humidor and logs in sync between phone and the web build (photos excluded).'),
              size: 12,
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: C.chip, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  signed ? tr('연결됨 · ${Sync.operatorEmail}', 'Linked · ${Sync.operatorEmail}') : tr('연결 안 됨', 'Not linked'),
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                if (signed) ...[
                  const SizedBox(height: 2),
                  SubText(on ? (at == null ? tr('아직 동기화 전', 'Not synced yet') : tr('마지막 동기화 ${_fmt(at)}', 'Last sync ${_fmt(at)}')) : tr('동기화 꺼짐', 'Sync off'), size: 12),
                ],
                if (sync.lastError != null) ...[
                  const SizedBox(height: 4),
                  Text(sync.lastError!, style: TextStyle(fontSize: 11, color: Colors.red.shade700), maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
              ]),
            ),
            if (_msg != null) ...[
              const SizedBox(height: 10),
              Text(_msg!, style: const TextStyle(fontSize: 13, color: C.accent)),
            ],
            const SizedBox(height: 14),
            if (!signed)
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                icon: const Icon(Icons.login, size: 18),
                label: Text(_busy ? tr('로그인 중…', 'Signing in…') : tr('구글로 운영자 로그인', 'Sign in with Google (maintainer)')),
                onPressed: _busy ? null : () => _run(() async => await sync.signIn()),
              )
            else ...[
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                    icon: const Icon(Icons.sync, size: 18),
                    label: Text(_busy ? tr('동기화 중…', 'Syncing…') : tr('지금 동기화', 'Sync now')),
                    onPressed: _busy || !on
                        ? null
                        : () => _run(() async {
                              await sync.syncNow();
                              return sync.lastError ?? tr('동기화 완료', 'Synced');
                            }),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            await sync.setEnabled(!on);
                            if (!on) await sync.syncNow();
                            return null;
                          }),
                  child: Text(on ? tr('끄기', 'Turn off') : tr('켜기', 'Turn on')),
                ),
              ]),
            ],
            const SizedBox(height: 8),
            SubText(
              tr('순서: 폰에서 먼저 로그인(기존 익명 ID에 계정 연결) → PC 웹판에서 같은 계정으로 로그인. 끄면 서버 사본은 그대로 두고 올리기/받기만 멈춰요.',
                  'Order: sign in on the phone first (links the existing anonymous ID), then on the web build with the same account. Turning off keeps the server copy and just stops syncing.'),
              size: 11,
            ),
          ]);
        },
      ),
    );
  }

  Future<void> _run(Future<String?> Function() f) async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    final st = context.read<AppState>();
    final r = await f();
    await st.reload();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _msg = r;
      _info = _load();
    });
  }

  static String _fmt(DateTime d) => '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
