import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DataDatabaseHelper {
  static final DataDatabaseHelper instance = DataDatabaseHelper._init();
  static Database? _database;

  DataDatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('app_data.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    // Opening without a strict schema to allow dynamic client queries
    return await openDatabase(
      path,
      version: 1,
    );
  }
}
