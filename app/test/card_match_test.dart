import 'package:bestcard/util/card_match.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The user's real wallet: Emirates NBD Duo + Mashreq Cashback.
  const wallet = ['Emirates NBD Duo', 'Mashreq Cashback'];

  group('offer hint -> held card (accuracy)', () {
    test('matches the exact issuer of a held card', () {
      expect(offerHintMatchesAny('Emirates NBD', wallet), isTrue);
      expect(offerHintMatchesAny('Mashreq', wallet), isTrue);
    });

    test('matches issuer + card name variants', () {
      expect(offerHintMatchesAny('Emirates NBD Duo Card', wallet), isTrue);
      expect(offerHintMatchesAny('Mashreq Cashback Credit Card', wallet), isTrue);
    });

    test('does NOT match a bank the user does not hold', () {
      expect(offerHintMatchesAny('Bank of America', wallet), isFalse);
      expect(offerHintMatchesAny('ADCB', wallet), isFalse);
      expect(offerHintMatchesAny('First Abu Dhabi Bank', wallet), isFalse);
      expect(offerHintMatchesAny('Citibank', wallet), isFalse);
      expect(offerHintMatchesAny('HSBC Platinum', wallet), isFalse);
    });

    test('generic banking words never cause a match', () {
      // "bank"/"card"/"credit" are stopwords -> no false positive.
      expect(offerHintMatchesAny('Any Bank Credit Card', wallet), isFalse);
      expect(offerHintMatchesAny('Platinum Card', wallet), isFalse);
      expect(offerHintMatchesAny('Cashback offer', wallet), isFalse);
    });

    test('empty / null-ish hints do not match', () {
      expect(offerHintMatchesAny('', wallet), isFalse);
      expect(offerHintMatchesAny('   ', wallet), isFalse);
      expect(offerHintMatchesAny('the of and', wallet), isFalse);
    });

    test('America vs American are distinct tokens (no fuzzy overspill)', () {
      // Holding Amex must not make "Bank of America" look held.
      expect(offerHintMatchesAny('Bank of America', ['American Express']), isFalse);
      expect(offerHintMatchesAny('American Express', ['American Express']), isTrue);
    });

    test('only the matching card among several is picked', () {
      expect(offerHintMatchesCardText('Emirates NBD', 'Emirates NBD Duo'), isTrue);
      expect(offerHintMatchesCardText('Emirates NBD', 'Mashreq Cashback'), isFalse);
    });
  });
}
