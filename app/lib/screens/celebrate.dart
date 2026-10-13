import 'dart:math';

import 'package:flutter/material.dart';

import '../data/badges.dart';
import '../l10n.dart';
import '../theme.dart';

/// 새 뱃지 획득 축하: 이모티콘 폭죽 + 상단 배너. 루트 오버레이에 띄우므로 화면이 바뀌어도 끝까지 보인다.
void celebrateBadges(BuildContext context, List<AppBadge> badges) {
  if (badges.isEmpty) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _Celebration(badges: badges, onDone: () => entry.remove()));
  overlay.insert(entry);
}

class _Celebration extends StatefulWidget {
  final List<AppBadge> badges;
  final VoidCallback onDone;
  const _Celebration({required this.badges, required this.onDone});
  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  late final List<_Particle> _ps;
  static const _emoji = ['🎉', '✨', '🎊', '⭐', '🔥', '🥂', '💫'];

  @override
  void initState() {
    super.initState();
    final r = Random();
    _ps = List.generate(28, (i) {
      return _Particle(
        emoji: _emoji[r.nextInt(_emoji.length)],
        x0: 0.5 + (r.nextDouble() - 0.5) * 0.3,
        vx: (r.nextDouble() - 0.5) * 1.6,
        vy: 1.4 + r.nextDouble() * 1.2,
        size: 18 + r.nextDouble() * 16,
        spin: (r.nextDouble() - 0.5) * 6,
        delay: r.nextDouble() * 0.25,
      );
    });
    _ctl.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final names = widget.badges.map((b) => b.name).join(' · ');
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
        animation: _ctl,
        builder: (ctx, _) {
          final t = _ctl.value;
          final size = MediaQuery.sizeOf(ctx);
          // 배너: 0~0.15 들어오고, 0.8~1.0 사라짐
          final bannerIn = Curves.easeOutBack.transform((t / 0.15).clamp(0, 1));
          final bannerOut = 1 - ((t - 0.8) / 0.2).clamp(0, 1);
          return Stack(children: [
            for (final p in _ps) ...[
              () {
                final u = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
                if (u <= 0) return const SizedBox.shrink();
                // 아래에서 솟았다가 중력으로 떨어짐
                final x = p.x0 * size.width + p.vx * u * size.width * 0.5;
                final y = size.height * (1.05 - p.vy * u + 1.1 * u * u);
                final opacity = (1 - ((u - 0.7) / 0.3).clamp(0.0, 1.0));
                return Positioned(
                  left: x,
                  top: y,
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.rotate(angle: p.spin * u, child: Text(p.emoji, style: TextStyle(fontSize: p.size))),
                  ),
                );
              }(),
            ],
            Positioned(
              top: MediaQuery.paddingOf(ctx).top + 12 + (1 - bannerIn) * -80,
              left: 20,
              right: 20,
              child: Opacity(
                opacity: bannerOut.clamp(0.0, 1.0).toDouble(),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: C.text,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 14, offset: Offset(0, 6))],
                    ),
                    child: Row(children: [
                      const Text('🏅', style: TextStyle(fontSize: 24)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(widget.badges.length == 1 ? tr('새 뱃지!', 'New badge!') : tr('새 뱃지 ${widget.badges.length}개!', '${widget.badges.length} new badges!'),
                              style: const TextStyle(fontSize: 11, color: Colors.white70)),
                          Text(names, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.bg), maxLines: 2, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ]);
        },
        ),
      ),
    );
  }
}

class _Particle {
  final String emoji;
  final double x0, vx, vy, size, spin, delay;
  _Particle({required this.emoji, required this.x0, required this.vx, required this.vy, required this.size, required this.spin, required this.delay});
}
