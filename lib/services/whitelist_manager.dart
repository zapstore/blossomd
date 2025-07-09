import 'package:sqlite3/sqlite3.dart';

class WhitelistManager {
  final Database db;

  WhitelistManager(this.db);

  void addPubkey(String pubkey) {
    if (!_isValidPubkey(pubkey)) {
      throw ArgumentError(
        'Invalid pubkey format. Must be 64-character hex string.',
      );
    }

    try {
      final stmt = db.prepare(
        'INSERT OR REPLACE INTO whitelist (pubkey) VALUES (?)',
      );
      stmt.execute([pubkey.toLowerCase()]);
      print('[INFO] Added pubkey $pubkey to whitelist');
    } catch (e) {
      throw Exception('Failed to add pubkey to whitelist: $e');
    }
  }

  void removePubkey(String pubkey) {
    if (!_isValidPubkey(pubkey)) {
      throw ArgumentError(
        'Invalid pubkey format. Must be 64-character hex string.',
      );
    }

    try {
      final stmt = db.prepare('DELETE FROM whitelist WHERE pubkey = ?');
      stmt.execute([pubkey.toLowerCase()]);
      print('[INFO] Removed pubkey $pubkey from whitelist');
    } catch (e) {
      throw Exception('Failed to remove pubkey from whitelist: $e');
    }
  }

  void listPubkeys() {
    try {
      final stmt = db.prepare('SELECT pubkey FROM whitelist ORDER BY pubkey');
      final results = stmt.select();

      if (results.isEmpty) {
        print('No pubkeys in whitelist');
        return;
      }

      print('Whitelisted pubkeys:');
      print('${'Pubkey'.padRight(66)}');
      print('${'=' * 66}');

      for (final row in results) {
        final pubkey = row['pubkey'] as String;
        print(pubkey);
      }

      print(
        '\nTotal: ${results.length} pubkey${results.length == 1 ? '' : 's'}',
      );
    } catch (e) {
      throw Exception('Failed to list pubkeys: $e');
    }
  }

  bool isWhitelisted(String pubkey) {
    print('[DEBUG] Checking whitelist for pubkey: $pubkey');
    try {
      final stmt = db.prepare('SELECT pubkey FROM whitelist WHERE pubkey = ?');
      final result = stmt.select([pubkey]);

      print('[DEBUG] Query result: $result');

      if (result.isNotEmpty) {
        print('[DEBUG] Pubkey $pubkey is whitelisted');
        return true;
      }

      print('[DEBUG] Pubkey $pubkey is not whitelisted');
      return false;
    } catch (e) {
      print('[ERROR] Database query failed for pubkey $pubkey: $e');
      return false; // Treat database errors as unauthorized
    }
  }

  bool _isValidPubkey(String pubkey) {
    return RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(pubkey);
  }
}
