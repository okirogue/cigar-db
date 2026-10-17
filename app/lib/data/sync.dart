import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cigar.dart';
import '../state.dart';
import 'local_db.dart';
import 'installs.dart';
import 'scan_service.dart';

/// 운영자(본인) 전용 기기 간 동기화.
///
/// - 익명 UID 에 운영자 구글 계정을 *연결*해서 UID 를 그대로 유지한다 (서버의 기존 기록·실행 기록이 이어짐).
/// - 데이터는 users/<uid>/{humidors|stock|logs|custom}/<sid> 에 두고, Firestore 규칙에서 허용된 이메일만 읽고 쓸 수 있다.
///   그래서 다른 사용자가 로그인 버튼을 눌러도 아무것도 올라가지 않는다 (앱에서도 이메일을 먼저 확인해 막음).
/// - 사진은 제외. 나머지(메모·장소·페어링 포함)는 전부. 충돌은 나중에 고친 쪽 우선(updated ms).
/// - 지운 행은 {deleted: true} 묘비 문서로 전파.
class Sync {
  Sync._();
  static final instance = Sync._();

  /// 동기화가 허용된 운영자 계정 (firestore.rules 와 같아야 함)
  static const operatorEmail = 'okirogue@gmail.com';

  /// 안드로이드 구글 로그인용 웹 클라이언트 ID (Firebase 콘솔 → Authentication → Google → 웹 SDK 구성).
  /// 비어 있으면 google-services.json 의 기본값을 쓴다 (거기에 없으면 안드로이드 로그인이 안 됨).
  static const googleWebClientId = '878079125373-ea7pmghecfdmdt4vkajk6qaq8fm45eil.apps.googleusercontent.com';

  static const _onKey = 'sync_on';
  static const _pushKey = 'sync_last_push';
  static const _pullKey = 'sync_last_pull';
  static const _atKey = 'sync_last_at';

  AppState? _st;
  Timer? _debounce;
  bool _busy = false;
  bool _applying = false; // 서버에서 받은 걸 로컬에 넣는 중 — 이때 reload 가 또 push 를 걸지 않게
  bool _gsInit = false;
  final Set<String> _pulledSids = {}; // 이번 사이클에 서버에서 받은 행 — 바로 되돌려 올리지 않게
  bool _dropDefaultHumidor = false; // 빈 기기(PC 웹판 첫 로그인)의 기본 휴미더는 서버 것을 받으면 치움
  String? lastError;

  void attach(AppState st) => _st = st;

  User? get _user => ScanService.instance.ready ? FirebaseAuth.instance.currentUser : null;

  /// 운영자 구글 계정이 연결돼 있는지
  bool get signedIn {
    if (!ScanService.instance.ready) return false;
    final u = _user;
    if (u == null) return false;
    return (u.email ?? '').toLowerCase() == operatorEmail && u.providerData.any((p) => p.providerId == 'google.com');
  }

  Future<bool> get enabled async {
    if (!signedIn) return false;
    return (await SharedPreferences.getInstance()).getBool(_onKey) ?? false;
  }

  Future<void> setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_onKey, v);
    if (v) await p.setInt(_pullKey, 0); // 다시 켜면 서버 것을 전부 다시 받음 (빠진 게 있을 때 수동 복구용)
  }

  static const _schemaKey = 'sync_schema';
  static const _schema = 2; // 2: synced(서버 시각) 커서

  /// 동기화 방식이 바뀌었으면 한 번 전부 다시 올리고 받기
  Future<void> _migrateIfNeeded(SharedPreferences p) async {
    if ((p.getInt(_schemaKey) ?? 1) >= _schema) return;
    await p.setInt(_pushKey, 0);
    await p.setInt(_pullKey, 0);
    await p.setInt(_schemaKey, _schema);
  }

  Future<DateTime?> get lastSyncedAt async {
    final ms = (await SharedPreferences.getInstance()).getInt(_atKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  // ---------------- 로그인 ----------------

  /// 구글 로그인 → 익명 UID 에 연결. 이미 다른 UID 에 연결된 계정이면(예: 폰에서 먼저 했고 지금은 PC) 그 UID 로 전환.
  /// 성공하면 null, 실패하면 사용자에게 보여줄 메시지.
  Future<String?> signIn() async {
    if (!ScanService.instance.ready) return 'Firebase 연결이 안 돼 있어요';
    final auth = FirebaseAuth.instance;
    final prevUser = auth.currentUser;
    final prevUid = prevUser == null ? null : Installs.docIdFor(prevUser); // 로그인 전 실행 기록 문서 id (바뀌면 정리용)
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..addScope('email')
          ..setCustomParameters({'login_hint': operatorEmail, 'prompt': 'select_account'});
        final cur = auth.currentUser;
        try {
          if (cur != null && cur.isAnonymous) {
            await cur.linkWithPopup(provider);
          } else {
            await auth.signInWithPopup(provider);
          }
        } on FirebaseAuthException catch (e) {
          if (e.code == 'credential-already-in-use' || e.code == 'email-already-in-use' || e.code == 'provider-already-linked') {
            // 이미 다른 UID(폰)에 연결된 계정 → 운영자 계정일 때만 그 UID 로 전환 (남의 익명 UID 를 바꾸지 않게)
            if ((e.email ?? '').toLowerCase() != operatorEmail && e.code != 'provider-already-linked') return '운영자 계정이 아니에요';
            await auth.signInWithPopup(provider);
          } else {
            rethrow;
          }
        }
        // 운영자가 아니면 바로 연결 해제 (익명 상태로 복귀)
        final u = auth.currentUser;
        if (u != null && (u.email ?? '').toLowerCase() != operatorEmail) {
          try {
            await u.unlink('google.com');
          } catch (_) {}
          return '운영자 계정이 아니에요';
        }
      } else {
        final gs = GoogleSignIn.instance;
        if (!_gsInit) {
          await gs.initialize(serverClientId: googleWebClientId.isEmpty ? null : googleWebClientId);
          _gsInit = true;
        }
        final acct = await gs.authenticate(scopeHint: const ['email']);
        if (acct.email.toLowerCase() != operatorEmail) {
          await gs.signOut();
          return '운영자 계정이 아니에요';
        }
        final idToken = acct.authentication.idToken;
        if (idToken == null) return '구글 토큰을 못 받았어요';
        final cred = GoogleAuthProvider.credential(idToken: idToken);
        final cur = auth.currentUser;
        try {
          if (cur != null && cur.isAnonymous) {
            await cur.linkWithCredential(cred);
          } else {
            await auth.signInWithCredential(cred);
          }
        } on FirebaseAuthException catch (e) {
          if (e.code == 'credential-already-in-use' || e.code == 'email-already-in-use' || e.code == 'provider-already-linked') {
            await auth.signInWithCredential(cred);
          } else {
            rethrow;
          }
        }
      }
      if (!signedIn) return '로그인은 됐는데 운영자 계정 확인에 실패했어요';
      // 이전 익명 실행 기록을 새 문서에 흡수 표시 (UID 가 바뀌었거나 익명→기기별 문서로 바뀐 경우)
      if (prevUid != null) await Installs.instance.absorb(prevUid);
      final p = await SharedPreferences.getInstance();
      await p.setBool(_onKey, true);
      // 처음 연결: 전부 올리고 전부 받기
      await p.setInt(_pushKey, 0);
      await p.setInt(_pullKey, 0);
      await p.setInt(_schemaKey, _schema);
      final st = _st;
      _dropDefaultHumidor = st != null && st.logs.isEmpty && st.allStock.isEmpty && st.humidors.length == 1;
      await syncNow();
      return lastError;
    } on FirebaseAuthException catch (e) {
      return '로그인 실패: ${e.code}';
    } on GoogleSignInException catch (e) {
      return '구글 로그인 실패: ${e.code.name}';
    } catch (e) {
      return '로그인 실패: $e';
    }
  }

  // ---------------- 동기화 ----------------

  CollectionReference<Map<String, dynamic>> _col(String name) => FirebaseFirestore.instance.collection('users').doc(_user!.uid).collection(name);

  /// 로컬 변경 후(reload) 2초 뒤 한 번만
  void schedule() {
    if (_applying) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      syncNow();
    });
  }

  /// 올리고(push) 받기(pull). 켜져 있지 않으면 아무것도 안 함.
  Future<void> syncNow() async {
    if (!ScanService.instance.ready || _busy || !await enabled) return;
    _busy = true;
    lastError = null;
    try {
      await _migrateIfNeeded(await SharedPreferences.getInstance());
      // 받기 먼저: 서버에 더 최근 수정(또는 삭제)이 있으면 로컬에 먼저 반영하고, 그 다음 내 변경분을 올린다
      _pulledSids.clear();
      var changed = await _pull();
      if (_dropDefaultHumidor) {
        _dropDefaultHumidor = false;
        // 서버에서 휴미더를 받았으면 이 기기의 빈 기본 휴미더는 치움 (폰에 빈 휴미더가 하나 더 생기지 않게)
        final hs = await LocalDb.instance.humidors();
        if (hs.length > 1) {
          for (final h in hs.where((h) => !_pulledSids.contains('humidors/${h.sid}'))) {
            await LocalDb.instance.deleteHumidor(h.id);
            changed = true;
          }
        }
      }
      await _push();
      final p = await SharedPreferences.getInstance();
      await p.setInt(_atKey, LocalDb.now);
      if (changed && _st != null) {
        _applying = true;
        try {
          await _st!.reload();
        } finally {
          _applying = false;
        }
      }
    } catch (e) {
      lastError = e.toString();
    } finally {
      _busy = false;
    }
  }

  static const _tables = ['humidors', 'stock', 'logs', 'wishlist'];

  Future<void> _push() async {
    final db = LocalDb.instance;
    final p = await SharedPreferences.getInstance();
    final since = p.getInt(_pushKey) ?? 0;
    final t0 = LocalDb.now;
    // 로컬 id ↔ sid 매핑 (재고→휴미더, 기록→재고 연결을 sid 로 바꿔 올림)
    final hum = {for (final r in await db.changedSince('humidors', -1)) r['id'] as int: r['sid'] as String};
    final stk = {for (final r in await db.changedSince('stock', -1)) r['id'] as int: r['sid'] as String};
    var batch = FirebaseFirestore.instance.batch();
    var n = 0;
    Future<void> flush() async {
      if (n == 0) return;
      await batch.commit().timeout(const Duration(seconds: 30));
      batch = FirebaseFirestore.instance.batch();
      n = 0;
    }

    for (final t in _tables) {
      for (final r in await db.changedSince(t, since)) {
        final sid = r['sid'] as String?;
        if (sid == null || sid.isEmpty || _pulledSids.contains('$t/$sid')) continue;
        batch.set(_col(t).doc(sid), _toCloud(t, r, hum, stk), SetOptions(merge: true));
        if (++n >= 400) await flush();
      }
    }
    for (final r in await db.customRowsSince(since)) {
      if (_pulledSids.contains('custom/${r['id']}')) continue;
      batch.set(_col('custom').doc(r['id'] as String), {
        'json': r['json'],
        'created': r['created'],
        'updated': r['updated'],
        'deleted': false,
        'synced': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (++n >= 400) await flush();
    }
    for (final r in await db.tombstonesSince(since)) {
      final t = r['tbl'] as String;
      batch.set(_col(t == 'custom_cigars' ? 'custom' : t).doc(r['sid'] as String), {'deleted': true, 'updated': r['updated'], 'synced': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      if (++n >= 400) await flush();
    }
    await flush();
    await p.setInt(_pushKey, t0);
  }

  Map<String, dynamic> _toCloud(String t, Map<String, Object?> r, Map<int, String> hum, Map<int, String> stk) {
    final m = <String, dynamic>{'deleted': false, 'synced': FieldValue.serverTimestamp()};
    for (final e in r.entries) {
      if (e.key == 'id' || e.key == 'sid' || e.key == 'photos') continue; // 사진은 동기화 안 함
      m[e.key] = e.value;
    }
    if (t == 'stock') {
      m.remove('humidor_id');
      m['humidor_sid'] = hum[r['humidor_id'] as int?] ?? '';
    }
    if (t == 'logs') {
      m.remove('stock_item_id');
      final sidOf = stk[r['stock_item_id'] as int?];
      m['stock_sid'] = sidOf ?? '';
    }
    return m;
  }

  /// 서버 변경분을 로컬에. 뭔가 바뀌었으면 true.
  Future<bool> _pull() async {
    final db = LocalDb.instance;
    final p = await SharedPreferences.getInstance();
    // 커서는 서버 기록 시각(synced). 클라이언트 updated 로 자르면 "먼저 만들어지고 나중에 올라온" 행을 놓친다
    // (다른 기기가 로컬에서 만든 시각 < 이 기기의 마지막 받기 시각 < 실제 업로드 시각).
    final since = p.getInt(_pullKey) ?? 0;
    var maxSynced = since;
    var changed = false;

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> fetch(String c) async {
      final col = _col(c);
      final q = since == 0
          ? await col.get().timeout(const Duration(seconds: 30)) // 처음엔 전부 (synced 없는 옛 문서 포함)
          : await col.where('synced', isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(since)).get().timeout(const Duration(seconds: 30));
      for (final d in q.docs) {
        final ts = d.data()['synced'];
        if (ts is Timestamp && ts.millisecondsSinceEpoch > maxSynced) maxSynced = ts.millisecondsSinceEpoch;
      }
      return q.docs;
    }

    // 1) 직접 추가한 시가 (기록·재고가 참조할 수 있으니 먼저)
    for (final d in await fetch('custom')) {
      final m = d.data();
      _pulledSids.add('custom/${d.id}');
      if (m['deleted'] == true) {
        if (await db.deleteBySid('custom_cigars', d.id)) changed = true;
        continue;
      }
      if (await db.upsertCustom(d.id, m['json'] as String, (m['created'] as String?) ?? '', (m['updated'] as num).toInt())) {
        try {
          _st?.repo.addCustom(Cigar.fromJson(jsonDecode(m['json'] as String) as Map<String, dynamic>));
        } catch (_) {}
        changed = true;
      }
    }

    // 2) 휴미더
    for (final d in await fetch('humidors')) {
      final m = d.data();
      _pulledSids.add('humidors/${d.id}');
      if (m['deleted'] == true) {
        if (await db.deleteBySid('humidors', d.id)) changed = true;
      } else {
        final r = await db.upsertBySid('humidors', d.id, {'name': m['name'], 'sort_order': m['sort_order'] ?? 0}, (m['updated'] as num).toInt());
        if (r.$2) changed = true;
      }
    }

    // 3) 재고 (휴미더 sid → 로컬 id)
    Future<int> humidorId(String sid) async {
      final r = await db.bySid('humidors', sid);
      if (r != null) return r['id'] as int;
      // 모르는 휴미더면 서버에서 한 번 더 찾아보고, 없으면 첫 휴미더로
      try {
        final doc = await _col('humidors').doc(sid).get();
        final m = doc.data();
        if (m != null && m['deleted'] != true) {
          _pulledSids.add('humidors/$sid');
          return (await db.upsertBySid('humidors', sid, {'name': m['name'], 'sort_order': m['sort_order'] ?? 0}, (m['updated'] as num).toInt())).$1;
        }
      } catch (_) {}
      final all = await db.humidors();
      if (all.isNotEmpty) return all.first.id;
      return db.addHumidor('My humidor'); // 휴미더가 하나도 없으면(전부 지워진 직후) 기본 하나
    }

    for (final d in await fetch('stock')) {
      final m = d.data();
      _pulledSids.add('stock/${d.id}');
      if (m['deleted'] == true) {
        if (await db.deleteBySid('stock', d.id)) changed = true;
        continue;
      }
      final r = await db.upsertBySid('stock', d.id, {
        'humidor_id': await humidorId((m['humidor_sid'] as String?) ?? ''),
        'cigar_id': m['cigar_id'],
        'cigar_name': m['cigar_name'],
        'vitola': m['vitola'],
        'qty': m['qty'] ?? 0,
        'price_per_stick': m['price_per_stick'],
        'currency': m['currency'] ?? 'KRW',
        'added_date': m['added_date'],
        'memo': m['memo'],
      }, (m['updated'] as num).toInt());
      if (r.$2) changed = true;
    }

    // 4) 기록 (재고 sid → 로컬 id, 없으면 null)
    for (final d in await fetch('logs')) {
      final m = d.data();
      _pulledSids.add('logs/${d.id}');
      if (m['deleted'] == true) {
        if (await db.deleteBySid('logs', d.id)) changed = true;
        continue;
      }
      int? stockId;
      final ssid = m['stock_sid'] as String?;
      if (ssid != null && ssid.isNotEmpty) stockId = (await db.bySid('stock', ssid))?['id'] as int?;
      final r = await db.upsertBySid('logs', d.id, {
        'cigar_id': m['cigar_id'],
        'cigar_name': m['cigar_name'],
        'vitola': m['vitola'],
        'date': m['date'],
        'score': (m['score'] as num?)?.toDouble() ?? 0,
        'tags': m['tags'] ?? '',
        'note_start': m['note_start'],
        'note_mid': m['note_mid'],
        'note_end': m['note_end'],
        'summary': m['summary'],
        'place': m['place'],
        'pairing': m['pairing'],
        'stock_item_id': stockId,
        'stock_price': m['stock_price'],
        'stock_currency': m['stock_currency'],
        'stock_added': m['stock_added'],
      }, (m['updated'] as num).toInt());
      if (r.$2) changed = true;
    }

    // 5) 위시리스트
    for (final d in await fetch('wishlist')) {
      final m = d.data();
      _pulledSids.add('wishlist/${d.id}');
      if (m['deleted'] == true) {
        if (await db.deleteBySid('wishlist', d.id)) changed = true;
        continue;
      }
      // 같은 시가가 다른 sid 로 이미 있으면(두 기기에서 따로 담음) 중복으로 안 넣는다
      if (await db.bySid('wishlist', d.id) == null && await db.inWishlist((m['cigar_id'] as String?) ?? '')) continue;
      final r = await db.upsertBySid('wishlist', d.id, {
        'cigar_id': m['cigar_id'],
        'cigar_name': m['cigar_name'],
        'vitola': m['vitola'],
        'memo': m['memo'],
        'priority': m['priority'] ?? 1,
        'created': m['created'],
      }, (m['updated'] as num).toInt());
      if (r.$2) changed = true;
    }

    // 아직 synced 가 없는 문서만 있었으면(옛 업로드) 커서를 못 올리므로 다음에도 전부 받는다 — 상대 기기가 한 번 더 올리면 해소
    await p.setInt(_pullKey, maxSynced);
    return changed;
  }
}
