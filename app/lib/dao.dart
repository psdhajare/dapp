/// C1: reads the bundled SQLite DB into engine inputs.
import 'dart:convert';

import 'package:engine/engine.dart';
import 'package:sqflite_common/sqlite_api.dart';

import 'util/offer_dedupe.dart';

class CardInfo {
  final String id;
  final String name;
  final String issuer;
  final String network;
  final String? colorPrimary; // '#RRGGBB' of the physical card, if known
  final String? colorSecondary;
  final bool held;
  const CardInfo({
    required this.id,
    required this.name,
    required this.issuer,
    this.network = 'other',
    this.colorPrimary,
    this.colorSecondary,
    required this.held,
  });

  String get label => '$issuer · $name';
}

class OfferInfo {
  final String cardLabel;
  final String cardName;
  final String? colorPrimary;
  final String? colorSecondary;
  final String title;
  final String? description;
  const OfferInfo({
    required this.cardLabel,
    this.cardName = '',
    this.colorPrimary,
    this.colorSecondary,
    required this.title,
    this.description,
  });
}

class RuleInfo {
  final String category;
  final double rate;
  final String unit; // cashback_pct | points_per_unit
  final double? capAmount;
  final String capPeriod;
  final double? minSpend;
  final String? conditions;
  const RuleInfo({
    required this.category,
    required this.rate,
    required this.unit,
    this.capAmount,
    required this.capPeriod,
    this.minSpend,
    this.conditions,
  });
}

class CardDetails {
  final String currency;
  final double annualFee;
  final String network;
  final double? apr;
  final double? foreignTxFee;
  final double? minSalary;
  final int? interestFreeDays;
  final List<RuleInfo> rules;
  const CardDetails({
    required this.currency,
    required this.annualFee,
    required this.network,
    this.apr,
    this.foreignTxFee,
    this.minSalary,
    this.interestFreeDays,
    required this.rules,
  });
}

class CardDao {
  final Database db;
  CardDao(this.db);

  /// Build engine [CardRules] for every card the user holds.
  Future<List<CardRules>> loadUserCards() async {
    final cards = await db.rawQuery(
      'SELECT c.id FROM cards c JOIN user_cards u ON u.card_id = c.id',
    );

    final result = <CardRules>[];
    for (final c in cards) {
      final cardId = c['id'] as String;

      final ruleRows = await db.query(
        'reward_rules',
        columns: ['category', 'rate', 'unit', 'cap_amount', 'cap_period', 'min_spend'],
        where: 'card_id = ?',
        whereArgs: [cardId],
      );
      final rules = <String, Rule>{};
      for (final r in ruleRows) {
        rules[r['category'] as String] = Rule(
          category: r['category'] as String,
          rate: (r['rate'] as num).toDouble(),
          unit: r['unit'] as String,
          capAmount: (r['cap_amount'] as num?)?.toDouble(),
          capPeriod: r['cap_period'] as String,
          minSpend: (r['min_spend'] as num?)?.toDouble(),
        );
      }

      final valRows = await db.query(
        'points_valuation',
        columns: ['value_per_point'],
        where: 'card_id = ?',
        whereArgs: [cardId],
      );
      final valuePerPoint =
          valRows.isEmpty ? null : (valRows.first['value_per_point'] as num).toDouble();

      result.add(CardRules(
        cardId: cardId,
        rulesByCategory: rules,
        valuePerPoint: valuePerPoint,
      ));
    }
    return result;
  }

  /// Places API venue type -> canonical category.
  Future<Map<String, String>> loadPoiMap() async {
    final rows = await db.query('poi_category_map');
    return {
      for (final r in rows) r['places_type'] as String: r['category'] as String,
    };
  }

  /// Human-readable card name.
  Future<String> cardName(String cardId) async {
    final rows = await db.query('cards',
        columns: ['name'], where: 'id = ?', whereArgs: [cardId]);
    return rows.isEmpty ? cardId : rows.first['name'] as String;
  }

  /// "Issuer · Card Name" for display.
  Future<String> cardLabel(String cardId) async {
    final rows = await db.query('cards',
        columns: ['name', 'issuer'], where: 'id = ?', whereArgs: [cardId]);
    if (rows.isEmpty) return cardId;
    return '${rows.first['issuer']} · ${rows.first['name']}';
  }

  /// Full details for the card info sheet: fee, currency, network, reward rules.
  Future<CardDetails> cardDetails(String cardId) async {
    final c = await db.query('cards',
        columns: ['currency', 'annual_fee', 'network', 'apr',
          'foreign_tx_fee', 'min_salary', 'interest_free_days'],
        where: 'id = ?', whereArgs: [cardId]);
    final ruleRows = await db.query('reward_rules',
        columns: ['category', 'rate', 'unit', 'cap_amount', 'cap_period',
          'min_spend', 'conditions'],
        where: 'card_id = ?', whereArgs: [cardId],
        orderBy: 'rate DESC');
    final row = c.isEmpty ? const {} : c.first;
    return CardDetails(
      currency: (row['currency'] as String?) ?? 'AED',
      annualFee: (row['annual_fee'] as num?)?.toDouble() ?? 0,
      network: (row['network'] as String?) ?? 'other',
      apr: (row['apr'] as num?)?.toDouble(),
      foreignTxFee: (row['foreign_tx_fee'] as num?)?.toDouble(),
      minSalary: (row['min_salary'] as num?)?.toDouble(),
      interestFreeDays: (row['interest_free_days'] as num?)?.toInt(),
      rules: [
        for (final r in ruleRows)
          RuleInfo(
            category: r['category'] as String,
            rate: (r['rate'] as num).toDouble(),
            unit: r['unit'] as String,
            capAmount: (r['cap_amount'] as num?)?.toDouble(),
            capPeriod: r['cap_period'] as String? ?? 'none',
            minSpend: (r['min_spend'] as num?)?.toDouble(),
            conditions: r['conditions'] as String?,
          ),
      ],
    );
  }

  /// Every card in the DB with whether it's in the wallet.
  Future<List<CardInfo>> allCards() async {
    final rows = await db.rawQuery('''
      SELECT c.id, c.name, c.issuer, c.network, c.color_primary,
             c.color_secondary, u.card_id IS NOT NULL AS held
      FROM cards c LEFT JOIN user_cards u ON u.card_id = c.id
      ORDER BY c.issuer, c.name
    ''');
    return [
      for (final r in rows)
        CardInfo(
          id: r['id'] as String,
          name: r['name'] as String,
          issuer: r['issuer'] as String,
          network: r['network'] as String,
          colorPrimary: r['color_primary'] as String?,
          colorSecondary: r['color_secondary'] as String?,
          held: (r['held'] as int) == 1,
        ),
    ];
  }

  /// Add/remove a card from the wallet.
  Future<void> setHeld(String cardId, bool held) async {
    if (held) {
      await db.rawInsert(
          'INSERT OR IGNORE INTO user_cards (card_id) VALUES (?)', [cardId]);
    } else {
      await db.delete('user_cards', where: 'card_id = ?', whereArgs: [cardId]);
    }
  }

  /// Store an extraction payload from the ingestion service: card, rules,
  /// valuation, offers — and put the card in the wallet.
  Future<void> insertExtraction(
    Map<String, dynamic> data, {
    String? colorPrimary,
    String? colorSecondary,
  }) async {
    final card = data['card'] as Map<String, dynamic>;
    final cardId = card['id'] as String;

    await db.transaction((txn) async {
      await txn.insert('cards', {
        'id': cardId,
        'name': card['name'],
        'issuer': card['issuer'],
        'network': card['network'],
        'currency': card['currency'] ?? 'GBP',
        'annual_fee': card['annual_fee'] ?? 0,
        'apr': card['apr'],
        'foreign_tx_fee': card['foreign_tx_fee'],
        'min_salary': card['min_salary'],
        'interest_free_days': card['interest_free_days'],
        // User-picked gradient wins over anything the server guessed.
        'color_primary': colorPrimary ?? card['color_primary'],
        'color_secondary': colorSecondary ?? card['color_secondary'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      for (final r in (data['rules'] as List? ?? [])) {
        final rule = r as Map<String, dynamic>;
        await txn.insert('reward_rules', {
          'card_id': cardId,
          'category': rule['category'],
          'rate': rule['rate'],
          'unit': rule['unit'],
          'cap_amount': rule['cap_amount'],
          'cap_period': rule['cap_period'] ?? 'none',
          'min_spend': rule['min_spend'],
          'conditions': rule['conditions'],
          'source_ref': rule['source_ref'],
          'verified': (rule['verified'] ?? false) == true ? 1 : 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final val = data['valuation'] as Map<String, dynamic>?;
      if (val != null) {
        await txn.insert('points_valuation', {
          'card_id': cardId,
          'points_currency': val['points_currency'],
          'value_per_point': val['value_per_point'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      for (final o in (data['offers'] as List? ?? [])) {
        final offer = o as Map<String, dynamic>;
        await txn.insert('card_offers', {
          'card_id': cardId,
          'category': offer['category'],
          'title': offer['title'],
          'description': offer['description'],
          'source_ref': offer['source_ref'],
          'verified': (offer['verified'] ?? false) == true ? 1 : 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await txn.rawInsert(
          'INSERT OR IGNORE INTO user_cards (card_id) VALUES (?)', [cardId]);
    });
  }

  /// Offers on wallet cards that match [category] exactly. Category-agnostic
  /// perks (welcome bonuses, payment plans) are noise at a venue — excluded.
  Future<List<OfferInfo>> offersForCategory(String category) async {
    final rows = await db.rawQuery('''
      SELECT c.issuer, c.name, c.color_primary, c.color_secondary,
             o.title, o.description
      FROM card_offers o
      JOIN user_cards u ON u.card_id = o.card_id
      JOIN cards c ON c.id = o.card_id
      WHERE o.category = ?
      ORDER BY o.title
    ''', [category]);
    final offers = [
      for (final r in rows)
        OfferInfo(
          cardLabel: '${r['issuer']} · ${r['name']}',
          cardName: r['name'] as String,
          colorPrimary: r['color_primary'] as String?,
          colorSecondary: r['color_secondary'] as String?,
          title: r['title'] as String,
          description: r['description'] as String?,
        ),
    ];
    return dedupeByText(offers, (o) => '${o.title} ${o.description ?? ''}');
  }

  // --- merchant search cache (cache-aside) ---

  /// Cached /search payload for [key], or null if absent/expired. Expired rows
  /// are pruned lazily on read.
  Future<Map<String, dynamic>?> cachedSearch(String key, {DateTime? now}) async {
    final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final rows = await db.query('search_cache',
        columns: ['payload_json', 'expires_at'],
        where: 'query_key = ?',
        whereArgs: [key]);
    if (rows.isEmpty) return null;
    if ((rows.first['expires_at'] as int) <= t) {
      await db.delete('search_cache', where: 'query_key = ?', whereArgs: [key]);
      return null;
    }
    return jsonDecode(rows.first['payload_json'] as String)
        as Map<String, dynamic>;
  }

  Future<void> cacheSearch(String key, Map<String, dynamic> payload,
      {Duration ttl = const Duration(hours: 24), DateTime? now}) async {
    final expires =
        (now ?? DateTime.now()).add(ttl).millisecondsSinceEpoch;
    await db.insert(
      'search_cache',
      {
        'query_key': key,
        'payload_json': jsonEncode(payload),
        'expires_at': expires,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
