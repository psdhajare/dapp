import 'package:bestcard/venue.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeLookup implements VenueLookup {
  final List<String> types;
  int calls = 0;
  FakeLookup(this.types);

  @override
  Future<List<String>> nearbyTypes(double lat, double lng) async {
    calls++;
    return types;
  }
}

const poiMap = {
  'restaurant': 'dining',
  'supermarket': 'grocery',
};

void main() {
  group('categoryForTypes', () {
    test('first matching type wins', () {
      expect(categoryForTypes(['point_of_interest', 'restaurant'], poiMap), 'dining');
    });
    test('no match returns null', () {
      expect(categoryForTypes(['bank', 'atm'], poiMap), isNull);
    });
  });

  group('VenueCategoryService cache', () {
    test('maps type to category, defaults to general', () async {
      final svc = VenueCategoryService(lookup: FakeLookup(['restaurant']), poiMap: poiMap);
      expect(await svc.categoryAt(51.5, -0.12), 'dining');

      final unknown = VenueCategoryService(lookup: FakeLookup(['bank']), poiMap: poiMap);
      expect(await unknown.categoryAt(51.5, -0.12), 'general');
    });

    test('cache hit skips network on repeat coords', () async {
      final lookup = FakeLookup(['supermarket']);
      final svc = VenueCategoryService(lookup: lookup, poiMap: poiMap);
      await svc.categoryAt(51.5, -0.12);
      await svc.categoryAt(51.5, -0.12);
      expect(lookup.calls, 1);
    });
  });
}
