import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/scan_service.dart';
import 'screens/badges_screen.dart';
import 'screens/diary_screen.dart';
import 'screens/explore_screen.dart';
import 'screens/humidor_screen.dart';
import 'state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ScanService.instance.init(); // 실패해도 앱은 뜸 (스캔만 비활성)
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
    return MaterialApp(
      title: 'MyHumidor',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const Home(),
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
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '홈'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: '휴미더'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: '다이어리'),
          NavigationDestination(icon: Icon(Icons.search), selectedIcon: Icon(Icons.search), label: '탐색'),
        ],
      ),
    );
  }
}
