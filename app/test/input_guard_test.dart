import 'package:bestcard/input_guard.dart';
import 'package:bestcard/rate_limiter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sanitizeQuery', () {
    test('accepts normal merchant names', () {
      expect(sanitizeQuery('Glossy Hair Salon'), 'Glossy Hair Salon');
      expect(sanitizeQuery('nike.com'), 'nike.com');
      expect(sanitizeQuery("McDonald's"), "McDonald's");
      expect(sanitizeQuery('H&M'), 'H&M');
      expect(sanitizeQuery('  Hair   Salon  '), 'Hair Salon'); // collapsed
    });

    test('rejects script / SQL / template / shell injection', () {
      for (final bad in [
        '<script>alert(1)</script>',
        "'; DROP TABLE cards;--",
        '{{7*7}}',
        r'${jndi:ldap://x}',
        'javascript:alert(1)',
        'hi <img src=x onerror=alert(1)>',
        'UNION SELECT password FROM users',
        '`rm -rf /`',
      ]) {
        expect(() => sanitizeQuery(bad), throwsA(isA<InputGuardException>()),
            reason: bad);
      }
    });

    test('rejects empty and oversized', () {
      expect(() => sanitizeQuery('   '), throwsA(isA<InputGuardException>()));
      expect(() => sanitizeQuery('a' * 81), throwsA(isA<InputGuardException>()));
    });
  });

  group('ClientRateLimiter', () {
    test('allows up to limit then blocks within window', () {
      final rl = ClientRateLimiter(limit: 3);
      final t = DateTime(2026);
      expect(rl.tryAcquire(t), isTrue);
      expect(rl.tryAcquire(t), isTrue);
      expect(rl.tryAcquire(t), isTrue);
      expect(rl.tryAcquire(t), isFalse); // 4th blocked
    });

    test('window slides', () {
      final rl = ClientRateLimiter(limit: 1);
      final t = DateTime(2026);
      expect(rl.tryAcquire(t), isTrue);
      expect(rl.tryAcquire(t.add(const Duration(seconds: 30))), isFalse);
      expect(rl.tryAcquire(t.add(const Duration(seconds: 61))), isTrue);
    });
  });
}
