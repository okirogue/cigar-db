import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cigar.dart';
import '../models/local.dart';
import '../state.dart';
import '../theme.dart';
import 'diary_screen.dart';

/// 취향 지도: 가로 = 강도(순함→셈), 세로 = 향의 결(밝은 결↑ / 묵직한 결↓), 색 = 필러 산지, 점 모양 = 내 판정.
class TasteMap extends StatelessWidget {
  const TasteMap({super.key});

  static const _origin = {
    'cuba': (Color(0xFFC9963F), '쿠바'),
    'nica': (Color(0xFF3F84C9), '니카라과'),
    'domi': (Color(0xFFC95A8F), '도미니카'),
    'other': (Color(0xFF6E9E3C), '혼합·기타'),
  };

  // 태그 → 밝기 가중치 (+ 밝은 결, − 묵직한 결)
  static const _bright = <String, double>{
    'cedar': .9, 'floral': 1, 'citrus': 1, 'hay': .8, 'grass': .8, 'tea': .6, 'cream': .6, 'honey': .5, 'vanilla': .4,
    'sandalwood': .5, 'white_pepper': .4, 'almond': .4, 'mineral': .5, 'dried_fruit': .3, 'cherry': .3, 'sweet': .2,
    'butter': .3, 'bread': .2, 'nuts': .1, 'caramel': 0, 'cinnamon': 0, 'spice': -.1, 'woody': -.1, 'oak': -.3, 'toast': -.3,
    'tobacco': -.3, 'pepper': -.3, 'brown_sugar': -.2, 'clove': -.4, 'cocoa': -.6, 'coffee': -.7, 'molasses': -.7,
    'dark_chocolate': -.8, 'musty': -.8, 'earth': -1, 'leather': -1, 'espresso': -1,
  };

  static double _strengthX(Cigar? c) {
    final s = (c?.specs['strength'] ?? c?.specs['strength_felt'] ?? '').toLowerCase();
    if (s.isEmpty) return .5;
    final full = s.contains('full'), med = s.contains('medium'), mild = s.contains('mild') || s.contains('light');
    if (full && med) return .7;
    if (full) return .88;
    if (med && mild) return .3;
    if (med) return .5;
    if (mild) return .14;
    return .5;
  }

  /// 0(묵직) ~ 1(밝음). 내가 체크한 태그 우선, 없으면 DB 태그.
  static double _brightY(SmokeLog l, Cigar? c) {
    var tags = l.tags;
    if (tags.isEmpty && c != null) tags = c.allTags;
    final w = tags.map((t) => _bright[t]).whereType<double>().toList();
    if (w.isEmpty) return .5;
    final m = w.reduce((a, b) => a + b) / w.length; // -1..1
    return ((m + 1) / 2).clamp(.04, .96);
  }

  static String _originKey(Cigar? c) {
    if (c == null) return 'other';
    if (c.cuban) return 'cuba';
    final f = ((c.specs['filler'] ?? '') + ' ' + (c.specs['country'] ?? '')).toLowerCase();
    if (f.contains('nicarag')) return 'nica';
    if (f.contains('dominic')) return 'domi';
    return 'other';
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    if (st.logs.length < 3) return const SizedBox.shrink();
    // 오래된 순 번호
    final logs = [...st.logs]..sort((a, b) => a.date != b.date ? a.date.compareTo(b.date) : a.id.compareTo(b.id));
    final pts = <_Pt>[];
    for (var i = 0; i < logs.length; i++) {
      final l = logs[i];
      final c = st.repo.byId(l.cigarId);
      // 같은 자리 겹침 방지용 아주 작은 흔들림 (기록 id 기반으로 고정)
      final jx = (Random(l.id).nextDouble() - .5) * .05, jy = (Random(l.id * 31).nextDouble() - .5) * .05;
      pts.add(_Pt(i + 1, l, (_strengthX(c) + jx).clamp(.03, .97), (_brightY(l, c) + jy).clamp(.03, .97), _originKey(c)));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(left: 4), child: Text('취향 지도', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
          const SizedBox(height: 2),
          const Padding(padding: EdgeInsets.only(left: 4), child: SubText('가로 강도 · 세로 향의 결 · 색 산지 · 꽉 찬 점 80↑, 반 70대, 테두리만 70 미만', size: 11)),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (_, box) {
            final w = box.maxWidth;
            final h = w * 1.05;
            return SizedBox(
              width: w,
              height: h,
              child: GestureDetector(
                onTapUp: (d) {
                  final hit = _hit(pts, d.localPosition, w, h);
                  if (hit != null) openLogSheet(context, hit.log);
                },
                child: CustomPaint(painter: _MapPainter(pts, _origin)),
              ),
            );
          }),
          const SizedBox(height: 10),
          Wrap(spacing: 14, runSpacing: 6, children: [
            for (final e in _origin.entries)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: e.value.$1, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                SubText(e.value.$2, size: 11),
              ]),
          ]),
        ]),
      ),
    );
  }

  static const _padL = 34.0, _padB = 30.0, _padT = 10.0, _padR = 10.0;

  _Pt? _hit(List<_Pt> pts, Offset p, double w, double h) {
    final pw = w - _padL - _padR, ph = h - _padT - _padB;
    _Pt? best;
    var bd = 18.0;
    for (final pt in pts) {
      final o = Offset(_padL + pt.x * pw, _padT + (1 - pt.y) * ph);
      final d = (o - p).distance;
      if (d < bd) {
        bd = d;
        best = pt;
      }
    }
    return best;
  }
}

class _Pt {
  final int n;
  final SmokeLog log;
  final double x, y;
  final String origin;
  _Pt(this.n, this.log, this.x, this.y, this.origin);
}

class _MapPainter extends CustomPainter {
  final List<_Pt> pts;
  final Map<String, (Color, String)> origin;
  _MapPainter(this.pts, this.origin);

  @override
  void paint(Canvas canvas, Size size) {
    const padL = TasteMap._padL, padB = TasteMap._padB, padT = TasteMap._padT, padR = TasteMap._padR;
    final pw = size.width - padL - padR, ph = size.height - padT - padB;
    final plot = Rect.fromLTWH(padL, padT, pw, ph);

    // 배경 + 격자
    canvas.drawRRect(RRect.fromRectAndRadius(plot, const Radius.circular(10)), Paint()..color = C.chip.withValues(alpha: .55));
    final grid = Paint()
      ..color = C.line
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final x = padL + pw * i / 4, y = padT + ph * i / 4;
      canvas.drawLine(Offset(x, padT), Offset(x, padT + ph), grid..color = i == 2 ? C.hint.withValues(alpha: .6) : C.line);
      canvas.drawLine(Offset(padL, y), Offset(padL + pw, y), grid..color = i == 2 ? C.hint.withValues(alpha: .6) : C.line);
    }

    // 축 라벨
    void label(String s, Offset at, {TextAlign align = TextAlign.left, bool rotate = false, double size = 10}) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontSize: size, color: C.sub)),
        textDirection: TextDirection.ltr,
        textAlign: align,
      )..layout();
      canvas.save();
      canvas.translate(at.dx, at.dy);
      if (rotate) canvas.rotate(-pi / 2);
      tp.paint(canvas, Offset(align == TextAlign.right ? -tp.width : (align == TextAlign.center ? -tp.width / 2 : 0), 0));
      canvas.restore();
    }

    label('순함', Offset(padL, size.height - padB + 8));
    label('강도 →', Offset(padL + pw / 2, size.height - padB + 8), align: TextAlign.center);
    label('셈', Offset(padL + pw, size.height - padB + 8), align: TextAlign.right);
    label('밝은 결 (시더·플로럴·건초)', Offset(14, padT + ph * .02), rotate: true, align: TextAlign.right);
    label('묵직한 결 (흙·가죽·에스프레소)', Offset(14, padT + ph * .98), rotate: true);

    // 점
    for (final p in pts) {
      final o = Offset(padL + p.x * pw, padT + (1 - p.y) * ph);
      final col = origin[p.origin]!.$1;
      const r = 11.0;
      final s = p.log.score;
      if (s >= 80) {
        canvas.drawCircle(o, r, Paint()..color = col);
      } else if (s >= 70) {
        canvas.drawCircle(o, r, Paint()..color = C.bg);
        canvas.drawArc(Rect.fromCircle(center: o, radius: r), -pi / 2, pi, true, Paint()..color = col);
        canvas.drawCircle(o, r, Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = 2);
      } else {
        canvas.drawCircle(o, r, Paint()..color = C.bg);
        canvas.drawCircle(o, r, Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = 2.2);
      }
      final tp = TextPainter(
        text: TextSpan(text: '${p.n}', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: s >= 80 ? Colors.white : C.text)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, o - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => old.pts.length != pts.length || old.pts.any((p) => !pts.contains(p));
}
