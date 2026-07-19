import 'package:bestcard/util/formatting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes known legal issuer names', () {
    expect(displayIssuer('JPMORGAN CHASE BANK, N.A.'), 'Chase');
    expect(displayIssuer('Goldman Sachs'), 'Goldman Sachs');
    expect(displayIssuer('Wio Bank PJSC'), 'Wio');
    expect(displayIssuer('Emirates NBD'), 'Emirates NBD');
    expect(displayIssuer('American Express'), 'American Express');
  });

  test('falls back to cleaned title-case for unknown issuers', () {
    expect(displayIssuer('ACME BANK, N.A.'), 'Acme');
    expect(displayIssuer('some new fintech ltd'), 'Some New Fintech');
  });
}
