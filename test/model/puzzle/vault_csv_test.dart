import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/puzzle/vault_csv.dart';

void main() {
  group('splitCsvLine', () {
    test('splits plain fields', () {
      expect(splitCsvLine('a,b,c'), ['a', 'b', 'c']);
    });

    test('honours quoted commas', () {
      expect(splitCsvLine('a,"b,c",d'), ['a', 'b,c', 'd']);
    });
  });

  group('parseVaultCsvLine', () {
    const sample =
        '00sHx,q3k1nr/1pp1nQpp/3p4/1P2p3/4P3/B1PP1b2/B5PP/5K2 b k - 0 17,e8d7 a2e6 d7d8 f7f8,1760,80,83,72,mate mateIn2 middlegame short,https://lichess.org/yyznGmXs/black#34,Italian_Game,';

    test('maps a sample row', () {
      final row = parseVaultCsvLine(sample)!;
      expect(row.puzzle.id.value, '00sHx');
      expect(row.puzzle.rating, 1760);
      expect(row.puzzle.solution.toList(), ['e8d7', 'a2e6', 'd7d8', 'f7f8']);
      expect(row.themes.contains('mate'), isTrue);
    });

    test('rejects bad rows', () {
      expect(parseVaultCsvLine(''), isNull);
      expect(parseVaultCsvLine('a,b,c'), isNull);
      expect(parseVaultCsvLine('id,fen,,notanumber,1,2,3,themes,url,open'), isNull);
    });
  });

  group('mbToRowCount', () {
    test('maps MB through row size', () {
      expect(mbToRowCount(50, bytesPerRow: 500), greaterThan(100000));
    });

    test('clamps to bounds', () {
      expect(mbToRowCount(0), 100);
      expect(mbToRowCount(100000), 6000000);
    });
  });
}
