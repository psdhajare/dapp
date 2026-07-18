/// C2: location -> venue types -> canonical category, with a forever-cache.
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Abstraction over "what kind of place is at these coords" so the category
/// service is testable without network.
abstract class VenueLookup {
  Future<List<String>> nearbyTypes(double lat, double lng);
}

/// Pure mapping: first venue type that has a canonical category wins.
String? categoryForTypes(List<String> types, Map<String, String> poiMap) {
  for (final t in types) {
    final cat = poiMap[t];
    if (cat != null) return cat;
  }
  return null;
}

class VenueCategoryService {
  final VenueLookup lookup;
  final Map<String, String> poiMap;
  final Map<String, String> _cache = {};

  VenueCategoryService({required this.lookup, required this.poiMap});

  /// Category at a location. Caches by rounded coords so repeat visits skip the
  /// network entirely (offline after first lookup).
  Future<String?> categoryAt(double lat, double lng) async {
    final key = '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';
    if (_cache.containsKey(key)) return _cache[key];

    final types = await lookup.nearbyTypes(lat, lng);
    final cat = categoryForTypes(types, poiMap) ?? 'general';
    _cache[key] = cat;
    return cat;
  }
}

/// Google Places Nearby Search impl. Returns the top result's types.
class GooglePlacesLookup implements VenueLookup {
  final String apiKey;
  final http.Client client;
  GooglePlacesLookup({required this.apiKey, http.Client? client})
      : client = client ?? http.Client();

  @override
  Future<List<String>> nearbyTypes(double lat, double lng) async {
    if (apiKey.isEmpty) return const []; // no key -> caller falls back to general

    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
      '?location=$lat,$lng&rankby=distance&key=$apiKey',
    );
    try {
      final resp = await client.get(uri);
      if (resp.statusCode != 200) return const [];
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final results = body['results'] as List<dynamic>? ?? const [];
      if (results.isEmpty) return const [];
      final top = results.first as Map<String, dynamic>;
      return (top['types'] as List<dynamic>? ?? const []).cast<String>();
    } catch (_) {
      return const []; // lookup failure degrades to general, never blocks payment
    }
  }
}
