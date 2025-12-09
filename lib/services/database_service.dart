import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as path;
import '../config/blossom_config.dart';

class DatabaseService {
  static Database initialize(BlossomConfig config) {
    final dbPath = path.join(config.workingDir, 'database.sqlite');
    Directory(config.workingDir).createSync(recursive: true);

    final db = sqlite3.open(dbPath);

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

    // Ensure filename column exists for name-based lookup
    _ensureFilenameColumn(db);

    // Unique index on filename (allows multiple NULLs) for global name→hash mapping
    db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_blobs_filename
      ON blobs(filename)
      WHERE filename IS NOT NULL
    ''');

    // Track download counts per unique hash
    db.execute('''
      CREATE TABLE IF NOT EXISTS blob_downloads (
        sha256 text PRIMARY KEY,
        downloads integer NOT NULL DEFAULT 0
      )
    ''');

    print('[INFO] Database initialized at $dbPath');
    return db;
  }

  static void _ensureFilenameColumn(Database db) {
    final pragma = db.select('PRAGMA table_info(blobs);');
    final hasFilename = pragma.any((row) => row['name'] == 'filename');
    if (!hasFilename) {
      db.execute('ALTER TABLE blobs ADD COLUMN filename text');
    }
  }
}
