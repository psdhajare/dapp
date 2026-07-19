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

/// Venue lookup via TomTom Nearby Search (own commercial POI data — better
/// coverage than OSM in the Gulf). Maps TomTom categories to our poi_category_map
/// vocabulary, nearest first.
class TomTomLookup implements VenueLookup {
  final String apiKey;
  final http.Client client;
  TomTomLookup({required this.apiKey, http.Client? client})
      : client = client ?? http.Client();

  // TomTom category text -> a token present in poi_category_map.
  static String? _token(String text) {
    bool has(List<String> ks) => ks.any(text.contains);
    if (has(['petrol', 'fuel', 'gas station'])) return 'fuel';
    if (has(['cinema', 'movie', 'theater', 'theatre'])) return 'cinema';
    if (has(['pharmacy', 'chemist', 'drug', 'clinic', 'hospital', 'medical',
        'doctor', 'dentist'])) return 'pharmacy';
    if (has(['salon', 'spa', 'beauty', 'hair'])) return 'hairdresser';
    if (has(['convenience'])) return 'convenience';
    if (has(['market', 'supermarket', 'grocery', 'hypermarket'])) {
      return 'supermarket';
    }
    if (has(['restaurant', 'cafe', 'coffee', 'pub', 'bar', 'food', 'dining',
        'bistro', 'bakery', 'eatery'])) return 'restaurant';
    return null;
  }

  @override
  Future<List<String>> nearbyTypes(double lat, double lng) async {
    if (apiKey.isEmpty) return const [];
    final uri = Uri.parse(
      'https://api.tomtom.com/search/2/nearbySearch/.json'
      '?lat=$lat&lon=$lng&radius=150&limit=20&key=$apiKey',
    );
    try {
      final resp = await client.get(uri);
      if (resp.statusCode != 200) return const [];
      final results = (jsonDecode(resp.body)
          as Map<String, dynamic>)['results'] as List<dynamic>? ?? const [];
      final out = <String>[]; // results are distance-sorted (nearest first)
      for (final r in results.cast<Map<String, dynamic>>()) {
        final poi = r['poi'] as Map<String, dynamic>?;
        if (poi == null) continue;
        final cats = (poi['categories'] as List<dynamic>? ?? const [])
            .join(' ')
            .toLowerCase();
        final tok = _token(cats);
        if (tok != null) out.add(tok);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}

/// Keyless venue lookup via OpenStreetMap's Overpass API. Returns the OSM tag
/// values (e.g. "supermarket", "cinema", "restaurant") of nearby POIs, nearest
/// first, mapped to categories by poi_category_map. Free, no API key.
class OverpassLookup implements VenueLookup {
  final http.Client client;
  final String endpoint;
  OverpassLookup({
    http.Client? client,
    this.endpoint = "https://overpass-api.de/api/interpreter",
  }) : client = client ?? http.Client();

  @override
  Future<List<String>> nearbyTypes(double lat, double lng) async {
    // POIs within 90m carrying a shop/amenity/leisure tag.
    final q = "[out:json][timeout:10];("
        "nwr(around:90,$lat,$lng)[shop];"
        "nwr(around:90,$lat,$lng)[amenity];"
        "nwr(around:90,$lat,$lng)[leisure];"
        ");out tags center 30;";
    try {
      // Overpass 406s without a User-Agent.
      final resp = await client.post(Uri.parse(endpoint),
          headers: {"User-Agent": "ToroKard/1.0 (card recommender)"},
          body: {"data": q});
      if (resp.statusCode != 200) return const [];
      final els = (jsonDecode(resp.body)
          as Map<String, dynamic>)['elements'] as List<dynamic>? ?? const [];
      // Sort by distance from the user so the venue they're in wins.
      final scored = <(double, String)>[];
      for (final e in els.cast<Map<String, dynamic>>()) {
        final tags = e['tags'] as Map<String, dynamic>? ?? const {};
        final type = (tags['shop'] ?? tags['amenity'] ?? tags['leisure'])
            ?.toString();
        if (type == null) continue;
        final elat = (e['lat'] ?? (e['center']?['lat'])) as num?;
        final elng = (e['lon'] ?? (e['center']?['lon'])) as num?;
        final d = (elat == null || elng == null)
            ? 1e9
            : (elat - lat) * (elat - lat) + (elng - lng) * (elng - lng);
        scored.add((d.toDouble(), type));
      }
      scored.sort((a, b) => a.$1.compareTo(b.$1));
      return [for (final s in scored) s.$2];
    } catch (_) {
      return const []; // degrade to general, never block
    }
  }
}
