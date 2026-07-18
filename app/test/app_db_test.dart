import 'package:bestcard/app_db.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitSqlStatements', () {
    test('splits on semicolons outside strings', () {
      final stmts = splitSqlStatements('CREATE TABLE a (x);\nINSERT INTO a VALUES (1);');
      expect(stmts, hasLength(2));
    });

    test('keeps semicolons inside string literals', () {
      final stmts = splitSqlStatements(
          "INSERT INTO o VALUES ('lounge access; for self and guest');");
      expect(stmts, hasLength(1));
      expect(stmts.first, contains('for self and guest'));
    });

    test('handles escaped quotes inside strings', () {
      final stmts = splitSqlStatements(
          "INSERT INTO o VALUES ('it''s; tricky');INSERT INTO o VALUES (2);");
      expect(stmts, hasLength(2));
      expect(stmts.first, contains("it''s; tricky"));
    });

    test('drops comments and pragmas', () {
      final stmts = splitSqlStatements(
          '-- comment\nPRAGMA foreign_keys = ON;\nCREATE TABLE a (x);');
      expect(stmts, hasLength(1));
      expect(stmts.first, startsWith('CREATE TABLE'));
    });
  });
}
