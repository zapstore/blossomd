import 'package:sqlite3/sqlite3.dart';
import 'package:bech32/bech32.dart';
import 'dart:typed_data';

class WhitelistManager {
  final Database db;

  WhitelistManager(this.db);

  void addPubkey(String pubkey) {
    final hexPubkey = _normalizeToHex(pubkey);
    if (hexPubkey == null) {
      throw ArgumentError(
        'Invalid pubkey format. Must be 64-character hex string or valid npub.',
      );
    }

    try {
      final stmt = db.prepare(
        'INSERT OR REPLACE INTO whitelist (pubkey) VALUES (?)',
      );
      stmt.execute([hexPubkey.toLowerCase()]);
      print('[INFO] Added pubkey $pubkey to whitelist');
    } catch (e) {
      throw Exception('Failed to add pubkey to whitelist: $e');
    }
  }

  void removePubkey(String pubkey) {
    final hexPubkey = _normalizeToHex(pubkey);
    if (hexPubkey == null) {
      throw ArgumentError(
        'Invalid pubkey format. Must be 64-character hex string or valid npub.',
      );
    }

    try {
      final stmt = db.prepare('DELETE FROM whitelist WHERE pubkey = ?');
      stmt.execute([hexPubkey.toLowerCase()]);
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
      print('${'Pubkey (hex)'.padRight(66)} | ${'Npub'.padRight(66)}');
      print('${'=' * 66} | ${'=' * 66}');

      for (final row in results) {
        final pubkey = row['pubkey'] as String;
        final npub = _hexToNpub(pubkey);
        print('${pubkey.padRight(66)} | ${npub.padRight(66)}');
      }

      print(
        '\nTotal: ${results.length} pubkey${results.length == 1 ? '' : 's'}',
      );
    } catch (e) {
      throw Exception('Failed to list pubkeys: $e');
    }
  }

  bool isWhitelisted(String pubkey) {
    final hexPubkey = _normalizeToHex(pubkey);
    if (hexPubkey == null) {
      print('[DEBUG] Invalid pubkey format: $pubkey');
      return false;
    }

    print('[DEBUG] Checking whitelist for pubkey: $hexPubkey');
    try {
      final stmt = db.prepare('SELECT pubkey FROM whitelist WHERE pubkey = ?');
      final result = stmt.select([hexPubkey]);

      print('[DEBUG] Query result: $result');

      if (result.isNotEmpty) {
        print('[DEBUG] Pubkey $hexPubkey is whitelisted');
        return true;
      }

      print('[DEBUG] Pubkey $hexPubkey is not whitelisted');
      return false;
    } catch (e) {
      print('[ERROR] Database query failed for pubkey $hexPubkey: $e');
      return false; // Treat database errors as unauthorized
    }
  }

  /// Public method to normalize pubkey to hex format
  /// Accepts both hex and npub formats
  String? normalizePubkey(String pubkey) {
    return _normalizeToHex(pubkey);
  }

  /// Normalizes pubkey to hex format (64-character hex string)
  /// Accepts both hex and npub formats
  String? _normalizeToHex(String pubkey) {
    // Check if it's already a valid hex pubkey
    if (_isValidHexPubkey(pubkey)) {
      return pubkey.toLowerCase();
    }

    // Try to decode as npub
    try {
      return _npubToHex(pubkey);
    } catch (e) {
      return null;
    }
  }

  /// Converts npub format to hex
  String _npubToHex(String npub) {
    if (!npub.startsWith('npub1')) {
      throw ArgumentError('Invalid npub format: must start with npub1');
    }

    try {
      final bech32Codec = Bech32Codec();
      final decoded = bech32Codec.decode(npub);

      if (decoded.hrp != 'npub') {
        throw ArgumentError('Invalid npub format: wrong HRP');
      }

      // Convert from 5-bit groups to bytes
      final bytes = _convertBits(decoded.data, 5, 8, false);

      if (bytes.length != 32) {
        throw ArgumentError('Invalid npub format: wrong key length');
      }

      return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    } catch (e) {
      throw ArgumentError('Failed to decode npub: $e');
    }
  }

  /// Converts hex format to npub
  String _hexToNpub(String hex) {
    try {
      // Convert hex string to bytes
      final bytes = <int>[];
      for (int i = 0; i < hex.length; i += 2) {
        bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }

      // Convert from 8-bit groups to 5-bit groups
      final converted = _convertBits(bytes, 8, 5, true);

      final bech32Codec = Bech32Codec();
      final encoded = bech32Codec.encode(Bech32('npub', converted));

      return encoded;
    } catch (e) {
      return 'Error converting to npub';
    }
  }

  /// Convert between bit groups
  List<int> _convertBits(List<int> data, int fromBits, int toBits, bool pad) {
    var acc = 0;
    var bits = 0;
    final result = <int>[];
    final maxV = (1 << toBits) - 1;
    final maxAcc = (1 << (fromBits + toBits - 1)) - 1;

    for (final value in data) {
      if (value < 0 || (value >> fromBits) != 0) {
        throw ArgumentError('Invalid data for base conversion');
      }
      acc = ((acc << fromBits) | value) & maxAcc;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        result.add((acc >> bits) & maxV);
      }
    }

    if (pad) {
      if (bits > 0) {
        result.add((acc << (toBits - bits)) & maxV);
      }
    } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxV) != 0) {
      throw ArgumentError('Invalid padding in base conversion');
    }

    return result;
  }

  bool _isValidHexPubkey(String pubkey) {
    return RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(pubkey);
  }
}
