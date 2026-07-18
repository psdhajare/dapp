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

  /// Returns the extraction payload: {card, rules, valuation, offers, warnings}.
  Future<Map<String, dynamic>> ingest(String cardName) async {
    final http.Response resp;
    try {
      resp = await client.post(
        endpoint,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'card': cardName}),
      );
    } catch (e) {
      throw IngestException(
          'Ingestion service unreachable — start it with: '
          'python3 -m ingestion.server ($e)');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200) {
      throw IngestException(body['error']?.toString() ?? 'ingestion failed');
    }
    return body;
  }
}
