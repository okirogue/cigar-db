import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/analytics.dart';
import 'data/installs.dart';
import 'data/scan_service.dart';
import 'l10n.dart';
import 'screens/badges_screen.dart';
import 'screens/diary_screen.dart';
import 'screens/explore_screen.dart';
import 'screens/humidor_screen.dart';
import 'state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await L10n.init();
  await ScanService.instance.init(); // 실패해도 앱은 뜸 (스캔만 비활성)
  Installs.instance.ping(); // 실행 기록(플랫폼·언어·빌드) — 기다리지 않음
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: const CigarApp(),
    ),
  );
}

class CigarApp extends StatelessWidget {
  const CigarApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 언어가 바뀌면 key 가 바뀌어 트리 전체가 새 문구로 다시 그려진다
    return ValueListenableBuilder<String>(
      valueListenable: L10n.lang,
      builder: (_, lang, __) => MaterialApp(
        key: ValueKey(lang),
        title: 'MyHumidor',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: Locale(lang),
        navigatorObservers: Analytics.instance.observers,
        // 넓은 화면(데스크톱 웹)에선 폰 폭으로 가운데 정렬
        builder: (ctx, child) {
          final mq = MediaQuery.of(ctx);
          if (mq.size.width <= 640) return child!;
          return ColoredBox(
            color: C.text,
            child: Center(
              child: SizedBox(
                width: 480,
                child: ClipRect(
                  child: MediaQuery(data: mq.copyWith(size: Size(480, mq.size.height)), child: child!),
                ),
              ),
            ),
          );
        },
        home: const Home(),
      ),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final ready = context.select<AppState, bool>((s) => s.ready);
    if (!ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: C.accent)));
    }
    const pages = [BadgesScreen(), HumidorScreen(), DiaryScreen(), ExploreScreen()];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          Analytics.instance.tab(const ['home', 'humidor', 'diary', 'explore'][i]);
        },
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: tr('홈', 'Home')),
          NavigationDestination(icon: const Icon(Icons.inventory_2_outlined), selectedIcon: const Icon(Icons.inventory_2), label: tr('휴미더', 'Humidor')),
          NavigationDestination(icon: const Icon(Icons.menu_book_outlined), selectedIcon: const Icon(Icons.menu_book), label: tr('다이어리', 'Diary')),
          NavigationDestination(icon: const Icon(Icons.search), selectedIcon: const Icon(Icons.search), label: tr('탐색', 'Explore')),
        ],
      ),
    );
  }
}
