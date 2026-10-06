import 'package:flutter_test/flutter_test.dart';

import 'package:cigar_log/data/cigar_repo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('central DB loads and searches', () async {
    final repo = CigarRepo.instance;
    await repo.load();
    expect(repo.all.length, greaterThan(2000));
    expect(repo.tagCount, 37);
    final r = repo.search('romeo no.1');
    expect(r, isNotEmpty);
    expect(r.first.brand, 'Romeo y Julieta');
  });
}
