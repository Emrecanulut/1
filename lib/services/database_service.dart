import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/error_code.dart';

class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();
  static const _dbName = 'motoman_fix.db';
  static const _tableName = 'error_codes';
  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    _database = await _openDatabase();
    return _database!;
  }

  Future<void> initialize() async {
    final db = await database;
    final countResult = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $_tableName',
    );
    final count = Sqflite.firstIntValue(countResult) ?? 0;
    if (count == 0) {
      await _seedFromJson(db);
    }
  }

  Future<ErrorCode?> findByCode(String code) async {
    final db = await database;
    final normalizedCode = _normalizeCode(code);

    final rows = await db.query(
      _tableName,
      where: 'code = ?',
      whereArgs: <String>[normalizedCode],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return ErrorCode.fromMap(rows.first);
    }

    final codeNumberMatch = RegExp(r'(\d{3,5})').firstMatch(normalizedCode);
    if (codeNumberMatch == null) {
      return null;
    }

    final codeNumber = codeNumberMatch.group(1)!;
    final fallbackRows = await db.query(
      _tableName,
      where: 'code LIKE ?',
      whereArgs: <String>['%$codeNumber%'],
      limit: 1,
    );

    if (fallbackRows.isEmpty) {
      return null;
    }
    return ErrorCode.fromMap(fallbackRows.first);
  }

  Future<void> upsertErrorCode(ErrorCode errorCode) async {
    final db = await database;
    await db.insert(
      _tableName,
      errorCode.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ErrorCode>> getAllErrorCodes() async {
    final db = await database;
    final rows = await db.query(
      _tableName,
      orderBy: 'code ASC',
    );
    return rows.map(ErrorCode.fromMap).toList();
  }

  Future<void> deleteByCode(String code) async {
    final db = await database;
    await db.delete(
      _tableName,
      where: 'code = ?',
      whereArgs: <String>[code],
    );
  }

  Future<Database> _openDatabase() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(appDir.path, _dbName);

    return openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName(
            code TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            solution TEXT NOT NULL,
            expert_note TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<void> _seedFromJson(Database db) async {
    final raw = await rootBundle.loadString('lib/data/error_db.json');
    final List<dynamic> list = jsonDecode(raw) as List<dynamic>;

    final batch = db.batch();
    for (final item in list) {
      final record = ErrorCode.fromMap(item as Map<String, dynamic>);
      batch.insert(
        _tableName,
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  String _normalizeCode(String code) {
    return code.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
