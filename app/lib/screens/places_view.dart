import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/place_repo.dart';
import '../l10n.dart';
import '../models/place.dart';
import '../theme.dart';
import 'place_suggest_sheet.dart';

/// 탐색 › 장소: 국가 › 도시별 목록, "내 주변" 거리순, 장소 제안. 탭하면 구글맵.
class PlacesView extends StatefulWidget {
  const PlacesView({super.key});
  @override
  State<PlacesView> createState() => _PlacesViewState();
}

class _PlacesViewState extends State<PlacesView> {
  final repo = PlaceRepo.instance;
  Position? _me; // 내 주변 모드일 때 좌표
  bool _locating = false;
  String _kind = ''; // '' | bar | lounge | cafe

  Future<void> _near() async {
    if (_me != null) {
      setState(() => _me = null);
      return;
    }
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw tr('위치 권한이 없어요', 'Location permission denied');
      }
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 12)));
      setState(() => _me = p);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is String ? e : tr('위치를 가져오지 못했어요', 'Could not get location'))));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _suggest() async {
    final ok = await suggestPlace(context);
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('고마워요! 확인 후 목록에 올릴게요.', 'Thanks! We will verify and list it.'))));
    }
  }

  bool _pass(Place p) => _kind.isEmpty || p.kinds.contains(_kind);

  @override
  Widget build(BuildContext context) {
    final all = repo.all.where(_pass).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          for (final (k, label) in [('', tr('전체', 'All')), ('bar', tr('바', 'Bar')), ('lounge', tr('라운지', 'Lounge')), ('cafe', tr('카페', 'Café'))]) ...[
            PillChip(label: label, selected: _kind == k, onTap: () => setState(() => _kind = k)),
            const SizedBox(width: 6),
          ],
          const Spacer(),
          PillChip(
            label: _locating ? '…' : tr('내 주변', 'Near me'),
            selected: _me != null,
            dark: true,
            onTap: _locating ? null : _near,
          ),
        ]),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: repo.all.isEmpty
            ? _empty(context)
            : _me != null
                ? _nearList(all)
                : _groupedList(all),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFB8A999)), foregroundColor: C.accent),
              icon: const Icon(Icons.add_location_alt_outlined, size: 18),
              onPressed: _suggest,
              label: Text(tr('장소 제안하기', 'Suggest a place')),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _empty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.place_outlined, color: C.hint, size: 40),
            const SizedBox(height: 10),
            Text(tr('아직 등록된 장소가 없어요', 'No places yet'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SubText(tr('아는 시가 바·라운지·카페를 제안해 주세요. 확인되면 모두에게 보여요.', 'Suggest a cigar bar, lounge or café you know. Once verified it shows for everyone.'), size: 12),
          ]),
        ),
      );

  Widget _nearList(List<Place> all) {
    final rows = [for (final p in all) (p, p.distanceKm(_me!.latitude, _me!.longitude))]..sort((a, b) => a.$2.compareTo(b.$2));
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      children: [
        SubText(tr('가까운 순', 'Nearest first')),
        const SizedBox(height: 6),
        for (final (p, km) in rows.take(40)) _PlaceRow(place: p, trailing: km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(km < 10 ? 1 : 0)} km'),
      ],
    );
  }

  Widget _groupedList(List<Place> all) {
    final tmp = PlaceRepo.instance.grouped(L10n.code);
    final ids = all.map((p) => p.id).toSet();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      children: [
        for (final (country, cities) in tmp) ...[
          if (cities.any((c) => c.$2.any((p) => ids.contains(p.id)))) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              child: Text(L10n.isKo ? (countryNames[country]?.$1 ?? country) : (countryNames[country]?.$2 ?? country),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            for (final (city, places) in cities)
              if (places.any((p) => ids.contains(p.id))) ...[
                Padding(padding: const EdgeInsets.only(top: 4, bottom: 6), child: SubText(L10n.isKo ? city : (places.first.cityEn))),
                for (final p in places)
                  if (ids.contains(p.id)) _PlaceRow(place: p),
              ],
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _PlaceRow extends StatelessWidget {
  final Place place;
  final String? trailing;
  const _PlaceRow({required this.place, this.trailing});

  static String kindLabel(String k) => switch (k) {
        'bar' => tr('바', 'Bar'),
        'lounge' => tr('라운지', 'Lounge'),
        'cafe' => tr('카페', 'Café'),
        _ => k,
      };

  @override
  Widget build(BuildContext context) {
    final p = place;
    final sub = <String>[
      p.kinds.map(kindLabel).join('·'),
      if (p.smoking.isNotEmpty) p.smoking.map((s) => s == 'indoor' ? tr('실내', 'Indoor') : tr('실외', 'Outdoor')).join('·'),
      if (p.sells == 'yes') tr('시가 판매', 'Sells cigars'),
      if (p.rating != null) '★ ${p.rating!.toStringAsFixed(1)} (${p.ratingCount})',
    ];
    final note = L10n.isKo ? p.note : p.noteEn;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => launchUrl(Uri.parse(p.mapsLink), mode: LaunchMode.externalApplication),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: C.thumb, borderRadius: BorderRadius.circular(10)),
                child: Icon(p.kinds.contains('cafe') && p.kinds.length == 1 ? Icons.local_cafe_outlined : Icons.local_bar_outlined, color: C.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(L10n.isKo ? p.name : p.nameEn, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  SubText(sub.where((s) => s.isNotEmpty).join(' · ')),
                  if (note.isNotEmpty) SubText(note, size: 11),
                ]),
              ),
              if (trailing != null) Text(trailing!, style: const TextStyle(fontSize: 12, color: C.sub)),
              const SizedBox(width: 6),
              const Icon(Icons.map_outlined, color: C.hint, size: 18),
            ]),
          ),
        ),
      ),
    );
  }
}
