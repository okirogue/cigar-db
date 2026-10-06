import 'package:flutter/material.dart';

/// 목업 팔레트
class C {
  static const bg = Color(0xFFF6F1EA);
  static const accent = Color(0xFF7A4A2B);
  static const accentDark = Color(0xFF5C3620);
  static const text = Color(0xFF2B2420);
  static const sub = Color(0xFF6B5F56);
  static const hint = Color(0xFF9A8E84);
  static const line = Color(0xFFD9CFC4);
  static const lineSoft = Color(0xFFE3DAD0);
  static const chip = Color(0xFFF0E7DC);
  static const thumb = Color(0xFFE7DCCF);
  static const gold = Color(0xFFD9A06B);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: C.accent,
      primary: C.accent,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: C.text,
    ),
    scaffoldBackgroundColor: C.bg,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text),
    appBarTheme: const AppBarTheme(
      backgroundColor: C.bg,
      foregroundColor: C.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: C.text),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.accent)),
      labelStyle: const TextStyle(color: C.sub, fontSize: 13),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.text,
        backgroundColor: Colors.white,
        side: const BorderSide(color: C.line),
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: C.chip,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 11,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w400,
            color: s.contains(WidgetState.selected) ? C.accent : C.sub,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? C.accent : C.sub)),
    ),
    dividerColor: C.lineSoft,
  );
}

/// 공용 위젯들
class SubText extends StatelessWidget {
  final String text;
  final double size;
  const SubText(this.text, {super.key, this.size = 12});
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontSize: size, color: C.sub));
}

class Thumb extends StatelessWidget {
  final double size;
  const Thumb({super.key, this.size = 44});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: C.thumb, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.smoking_rooms, color: C.accent, size: 20),
      );
}

/// 선택 가능한 둥근 칩 (정렬·휴미더 선택 등)
class PillChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool dark;
  const PillChip({super.key, required this.label, this.selected = false, this.onTap, this.dark = false});
  @override
  Widget build(BuildContext context) {
    final bg = selected ? (dark ? C.text : C.accent) : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: selected ? null : Border.all(color: C.line),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : C.text)),
      ),
    );
  }
}

/// 노트 태그 칩
class NoteChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool small;
  final bool dashed;
  final VoidCallback? onTap;
  const NoteChip({super.key, required this.label, this.selected = false, this.small = false, this.dashed = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final fs = small ? 11.0 : 13.0;
    final pad = small ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4) : const EdgeInsets.symmetric(horizontal: 12, vertical: 7);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: pad,
        decoration: BoxDecoration(
          color: selected ? C.accent : (dashed ? Colors.transparent : C.chip),
          borderRadius: BorderRadius.circular(8),
          border: dashed && !selected ? Border.all(color: C.line) : null,
        ),
        child: Text(label, style: TextStyle(fontSize: fs, color: selected ? Colors.white : (dashed ? C.hint : C.text))),
      ),
    );
  }
}

String fmtWon(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '$b원';
}

/// yyyy-MM-dd → M/d
String fmtShort(String ymd) {
  final d = DateTime.tryParse(ymd);
  if (d == null) return ymd;
  return '${d.month}/${d.day}';
}

String todayYmd() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
