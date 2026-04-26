import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/user.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('server_users.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL
      )
    ''');
  }

  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  Future<User> addUser(String username, String password) async {
    final db = await instance.database;
    final hash = hashPassword(password);
    
    final id = await db.insert('users', {
      'username': username,
      'password_hash': hash,
    });
    return User(id: id, username: username, passwordHash: hash);
  }

  Future<int> updateUserPassword(int id, String newPassword) async {
    final db = await instance.database;
    final hash = hashPassword(newPassword);
    return await db.update(
      'users',
      {'password_hash': hash},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<User>> getUsers() async {
    final db = await instance.database;
    final result = await db.query('users', orderBy: 'id ASC');
    return result.map((json) => User.fromMap(json)).toList();
  }

  Future<int> deleteUser(int id) async {
    final db = await instance.database;
    return await db.delete('users', where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> verifyCredentials(String username, String password) async {
    final db = await instance.database;
    final hash = hashPassword(password);
    
    final result = await db.query(
      'users',
      where: 'username = ? AND password_hash = ?',
      whereArgs: [username, hash],
    );
    return result.isNotEmpty;
  }
}
