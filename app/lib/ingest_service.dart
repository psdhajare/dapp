/// Client for the local ingestion service (Mac-side Python, holds the LLM key).
/// The app posts a card name; the service finds the doc, extracts rules, and
/// returns the structured card data to store locally.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

class IngestException implements Exception {
  final String message;
  IngestException(this.message);
  @override
  String toString() => message;
}

class IngestService {
  final Uri endpoint;
  final http.Client client;

  IngestService({required this.endpoint, http.Client? client})
      : client = client ?? http.Client();

  /// Returns one extraction payload per physical card (a product can be a
  /// bundle of several). Each: {card, rules, valuation, offers, warnings}.
  Future<List<Map<String, dynamic>>> ingest(String cardName) async {
    final body = await _post(endpoint, {'card': cardName});
    final cards = body['cards'] as List? ?? [body]; // tolerate legacy shape
    return cards.cast<Map<String, dynamic>>();
  }

  /// Live merchant lookup: {merchant, category, offers[], source_ref, cached}.
  /// offers[] items: {title, description, card_hint, valid_until, via}.
  /// [cards] are the user's held card names, used to target loyalty-program
  /// offers (e.g. Wio → Entertainer); not persisted server-side.
  Future<Map<String, dynamic>> search(String merchant,
          {List<String> cards = const []}) =>
      _post(endpoint.replace(path: '/search'),
          {'merchant': merchant, 'cards': cards});

  Future<Map<String, dynamic>> _post(Uri url, Map<String, dynamic> json) async {
    final http.Response resp;
    try {
      resp = await client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(json),
      );
    } catch (e) {
      throw IngestException('Service unreachable ($e)');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200) {
      throw IngestException(body['error']?.toString() ?? 'request failed');
    }
    return body;
  }
}
