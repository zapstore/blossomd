import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as path;
import '../config/blossom_config.dart';

class DatabaseService {
  static Database initialize(BlossomConfig config) {
    final dbPath = path.join(config.workingDir, 'database.sqlite');
    Directory(config.workingDir).createSync(recursive: true);

    final db = sqlite3.open(dbPath);

    // Check if whitelist table exists and has the old schema
    final tableInfo = db.select("PRAGMA table_info(whitelist)");
    final hasLevelColumn = tableInfo.any((row) => row['name'] == 'level');

    if (hasLevelColumn) {
      print(
        '[INFO] Migrating whitelist table to new schema (removing level column)',
      );

      // Create new whitelist table
      db.execute('''
        CREATE TABLE IF NOT EXISTS whitelist_new (
          pubkey text NOT NULL,
          PRIMARY KEY (pubkey)
        )
      ''');

      // Copy data from old table to new table (only pubkeys, ignoring levels)
      db.execute('''
        INSERT OR IGNORE INTO whitelist_new (pubkey)
        SELECT pubkey FROM whitelist
      ''');

      // Drop old table and rename new table
      db.execute('DROP TABLE whitelist');
      db.execute('ALTER TABLE whitelist_new RENAME TO whitelist');

      print('[INFO] Whitelist migration completed');
    } else {
      // Create whitelist table if it doesn't exist (new installations)
      db.execute('''
        CREATE TABLE IF NOT EXISTS whitelist (
          pubkey text NOT NULL,
          PRIMARY KEY (pubkey)
        )
      ''');
    }

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
