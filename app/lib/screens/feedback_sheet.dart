import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/installs.dart';
import '../data/scan_service.dart';
import '../l10n.dart';
import '../theme.dart';

/// 제작자에게 한마디: 익명으로 feedback 컬렉션에 한 건. 연락처는 선택.
Future<void> openFeedbackSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _FeedbackSheet(),
  );
}

/// 홈 상단의 작은 말풍선 버튼
class FeedbackButton extends StatelessWidget {
  const FeedbackButton({super.key});
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tr('제작자에게 제안하기', 'Suggest to the maker'),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => openFeedbackSheet(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.chat_bubble_outline, size: 15, color: C.accent),
        ),
      ),
    );
  }
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet();
  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _text = TextEditingController();
  final _contact = TextEditingController();
  bool _sending = false;
  static const maxLen = 500;

  @override
  void dispose() {
    _text.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final sm = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _sending = true);
    try {
      if (!ScanService.instance.ready) throw 'offline';
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw 'no-auth';
      final info = await PackageInfo.fromPlatform();
      await FirebaseFirestore.instance.collection('feedback').add({
        'uid': uid,
        'text': text,
        'contact': _contact.text.trim(),
        'lang': L10n.code,
        'platform': Installs.platform,
        'build': int.tryParse(info.buildNumber) ?? 0,
        'created': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 10));
      nav.pop();
      sm.showSnackBar(SnackBar(content: Text(tr('보냈어요. 고마워요!', 'Sent. Thank you!'))));
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      sm.showSnackBar(SnackBar(content: Text(tr('지금은 보낼 수 없어요. 잠시 후 다시 시도해 주세요.', 'Could not send right now. Please try again later.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + mq.viewInsets.bottom + mq.padding.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('제작자에게 한마디', 'A word to the maker'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          SubText(tr('있었으면 하는 기능, 불편한 점, 틀린 시가 정보 뭐든요. 익명으로 전송돼요.', 'Feature ideas, annoyances, wrong cigar data — anything. Sent anonymously.'), size: 12),
          const SizedBox(height: 14),
          TextField(
            controller: _text,
            autofocus: true,
            minLines: 4,
            maxLines: 8,
            maxLength: maxLen,
            decoration: InputDecoration(hintText: tr('예: 휴미더 순서를 바꿀 수 있으면 좋겠어요', 'e.g. I wish I could reorder humidors')),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _contact,
            decoration: InputDecoration(
              labelText: tr('답장 받을 곳 (선택)', 'Where to reply (optional)'),
              hintText: tr('카페 닉네임, 이메일, 레딧 아이디…', 'Café nickname, email, Reddit handle…'),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: C.accent, minimumSize: const Size.fromHeight(46)),
              onPressed: _sending ? null : _send,
              child: Text(_sending ? tr('보내는 중…', 'Sending…') : tr('보내기', 'Send')),
            ),
          ),
        ]),
      ),
    );
  }
}
