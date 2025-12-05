import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as path;
import '../config/blossom_config.dart';

class DatabaseService {
  static Database initialize(BlossomConfig config) {
    final dbPath = path.join(config.workingDir, 'database.sqlite');
    Directory(config.workingDir).createSync(recursive: true);

    final db = sqlite3.open(dbPath);

    // Whitelist table removed - external authorization is used now

    // Create blob ownership table to track file-pubkey associations
    db.execute('''
      CREATE TABLE IF NOT EXISTS blobs (
        sha256 text NOT NULL,
        pubkey text NOT NULL,
        size integer NOT NULL,
        type text,
        uploaded integer NOT NULL,
        PRIMARY KEY (sha256, pubkey)
      )
    ''');

    print('[INFO] Database initialized at $dbPath');
    return db;
  }
}
