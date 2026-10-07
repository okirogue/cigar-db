import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../models/cigar.dart';
import '../models/local.dart';
import '../state.dart';
import '../theme.dart';
import 'diary_screen.dart';

/// 취향 지도: 가로 = 강도(순함→셈), 세로 = 향의 결(밝은 결↑ / 묵직한 결↓), 색 = 필러 산지, 점 모양 = 내 판정.
class TasteMap extends StatelessWidget {
  const TasteMap({super.key});

  static Map<String, (Color, String)> get _origin => {
        'cuba': (const Color(0xFFC9963F), tr('쿠바', 'Cuba')),
        'nica': (const Color(0xFF3F84C9), tr('니카라과', 'Nicaragua')),
        'domi': (const Color(0xFFC95A8F), tr('도미니카', 'Dominican')),
        'other': (const Color(0xFF6E9E3C), tr('혼합·기타', 'Blend / other')),
      };

  // 태그 → 밝기 가중치 (+ 밝은 결, − 묵직한 결)
  static const _bright = <String, double>{
    'cedar': .9, 'floral': 1, 'citrus': 1, 'hay': .8, 'grass': .8, 'tea': .6, 'cream': .6, 'honey': .5, 'vanilla': .4,
    'sandalwood': .5, 'white_pepper': .4, 'almond': .4, 'mineral': .5, 'dried_fruit': .3, 'cherry': .3, 'sweet': .2,
    'butter': .3, 'bread': .2, 'nuts': .1, 'caramel': 0, 'cinnamon': 0, 'spice': -.1, 'woody': -.1, 'oak': -.3, 'toast': -.3,
    'tobacco': -.3, 'pepper': -.3, 'brown_sugar': -.2, 'clove': -.4, 'cocoa': -.6, 'coffee': -.7, 'molasses': -.7,
    'dark_chocolate': -.8, 'musty': -.8, 'earth': -1, 'leather': -1, 'espresso': -1,
  };

  // 태그 → 체감 강도 보정 (+ 세게 느껴지는 쪽, − 순하게 느껴지는 쪽)
  static const _punch = <String, double>{
    'pepper': .14, 'white_pepper': .08, 'spice': .08, 'clove': .08, 'leather': .08, 'earth': .06, 'espresso': .08, 'dark_chocolate': .05,
    'musty': .04, 'oak': .03, 'tobacco': .05, 'cinnamon': .03,
    'cream': -.10, 'butter': -.08, 'sweet': -.06, 'honey': -.08, 'vanilla': -.08, 'caramel': -.05, 'floral': -.08, 'hay': -.06,
    'grass': -.05, 'tea': -.04, 'citrus': -.03, 'bread': -.04, 'almond': -.03, 'nuts': -.02,
  };

  /// 0(순함) ~ 1(셈). DB 강도(5단계)에 내가 체크한 노트로 연속 보정.
  static double _strengthX(SmokeLog l, Cigar? c) {
    final s = (c?.specs['strength'] ?? c?.specs['strength_felt'] ?? '').toLowerCase();
    double base;
    final full = s.contains('full'), med = s.contains('medium'), mild = s.contains('mild') || s.contains('light');
    if (full && med) {
      base = .7;
    } else if (full) {
      base = .88;
    } else if (med && mild) {
      base = .3;
    } else if (med) {
      base = .5;
    } else if (mild) {
      base = .14;
    } else {
      base = .5;
    }
    final adj = l.tags.map((t) => _punch[t]).whereType<double>().fold(0.0, (a, b) => a + b);
    // 강도 정보가 없으면 태그 보정을 더 크게 (그게 유일한 단서라서)
    return (base + adj.clamp(-.2, .2) * (s.isEmpty ? 1.6 : 1.0)).clamp(.04, .96);
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
      pts.add(_Pt(i + 1, l, (_strengthX(l, c) + jx).clamp(.03, .97), (_brightY(l, c) + jy).clamp(.03, .97), _originKey(c)));
    }

    final origin = _origin;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(left: 4), child: Text(tr('취향 지도', 'Taste Map'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
          const SizedBox(height: 2),
          Padding(
              padding: const EdgeInsets.only(left: 4),
              child: SubText(
                  tr('가로 강도 · 세로 향의 결 · 색 산지 · 꽉 찬 점 80↑, 반 70대, 테두리만 70 미만',
                      'X strength · Y flavor profile · color origin · filled 80+, half 70s, outline under 70'),
                  size: 11)),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (_, box) {
            final w = box.maxWidth;
            final h = w * 1.05;
            final r = pts.length > 20 ? 9.5 : 11.0;
            final placed = _layout(pts, w, h, r);
            return SizedBox(
              width: w,
              height: h,
              child: GestureDetector(
                onTapUp: (d) {
                  final hit = _hit(placed, d.localPosition, r);
                  if (hit != null) openLogSheet(context, hit.pt.log);
                },
                child: CustomPaint(painter: _MapPainter(placed, origin, r, L10n.code)),
              ),
            );
          }),
          const SizedBox(height: 10),
          Wrap(spacing: 14, runSpacing: 6, children: [
            for (final e in origin.entries)
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

  /// 정규화 좌표 → 픽셀. 겹치는 점은 서로 밀어내서 번호가 보이게 (원래 자리에서 멀어지지 않게 당기는 힘도 같이).
  static List<_Placed> _layout(List<_Pt> pts, double w, double h, double r) {
    final pw = w - _padL - _padR, ph = h - _padT - _padB;
    final home = [for (final p in pts) Offset(_padL + p.x * pw, _padT + (1 - p.y) * ph)];
    final pos = [...home];
    final minD = r * 2 + 3;
    for (var iter = 0; iter < 120; iter++) {
      var moved = false;
      for (var i = 0; i < pos.length; i++) {
        for (var j = i + 1; j < pos.length; j++) {
          final d = pos[j] - pos[i];
          var dist = d.distance;
          if (dist >= minD) continue;
          moved = true;
          Offset dir;
          if (dist < 0.01) {
            // 완전히 겹치면 번호 기반으로 방향 정함
            final a = (i * 2.399) % (2 * pi);
            dir = Offset(cos(a), sin(a));
            dist = 0.01;
          } else {
            dir = d / dist;
          }
          final push = (minD - dist) / 2 * 0.6;
          pos[i] = pos[i] - dir * push;
          pos[j] = pos[j] + dir * push;
        }
      }
      // 원래 자리로 살짝 당김 + 영역 안으로 클램프
      for (var i = 0; i < pos.length; i++) {
        pos[i] = pos[i] + (home[i] - pos[i]) * 0.05;
        pos[i] = Offset(pos[i].dx.clamp(_padL + r, _padL + pw - r), pos[i].dy.clamp(_padT + r, _padT + ph - r));
      }
      if (!moved) break;
    }
    return [for (var i = 0; i < pts.length; i++) _Placed(pts[i], pos[i])];
  }

  _Placed? _hit(List<_Placed> placed, Offset p, double r) {
    _Placed? best;
    var bd = r + 8;
    for (final pl in placed) {
      final d = (pl.o - p).distance;
      if (d < bd) {
        bd = d;
        best = pl;
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

class _Placed {
  final _Pt pt;
  final Offset o;
  _Placed(this.pt, this.o);
}

class _MapPainter extends CustomPainter {
  final List<_Placed> pts;
  final Map<String, (Color, String)> origin;
  final double r;
  final String lang;
  _MapPainter(this.pts, this.origin, this.r, this.lang);

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

    label(tr('순함', 'Mild'), Offset(padL, size.height - padB + 8));
    label(tr('강도 →', 'Strength →'), Offset(padL + pw / 2, size.height - padB + 8), align: TextAlign.center);
    label(tr('셈', 'Full'), Offset(padL + pw, size.height - padB + 8), align: TextAlign.right);
    label(tr('밝은 결 (시더·플로럴·건초)', 'Bright (cedar · floral · hay)'), Offset(14, padT + ph * .02), rotate: true, align: TextAlign.right);
    label(tr('묵직한 결 (흙·가죽·에스프레소)', 'Heavy (earth · leather · espresso)'), Offset(14, padT + ph * .98), rotate: true);

    // 점
    for (final pl in pts) {
      final p = pl.pt;
      final o = pl.o;
      final col = origin[p.origin]!.$1;
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
      // 흰 테두리로 인접 점과 구분
      canvas.drawCircle(o, r + 1, Paint()..color = C.bg..style = PaintingStyle.stroke..strokeWidth = 1.5);
      final tp = TextPainter(
        text: TextSpan(text: '${p.n}', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: s >= 80 ? Colors.white : C.text)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, o - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.lang != lang || old.pts.length != pts.length || old.r != r || old.pts.any((p) => !pts.contains(p));
}
