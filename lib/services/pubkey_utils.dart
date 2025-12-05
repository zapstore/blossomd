import 'package:bech32/bech32.dart';

class PubkeyUtils {
  static String? normalizePubkey(String pubkey) {
    if (_isValidHexPubkey(pubkey)) {
      return pubkey.toLowerCase();
    }
    try {
      return _npubToHex(pubkey);
    } catch (_) {
      return null;
    }
  }

  static String hexToNpub(String hex) {
    try {
      final bytes = <int>[];
      for (int i = 0; i < hex.length; i += 2) {
        bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }

      final converted = _convertBits(bytes, 8, 5, true);
      final bech32Codec = Bech32Codec();
      final encoded = bech32Codec.encode(Bech32('npub', converted));
      return encoded;
    } catch (e) {
      return 'Error converting to npub';
    }
  }

  static String _npubToHex(String npub) {
    if (!npub.startsWith('npub1')) {
      throw ArgumentError('Invalid npub format: must start with npub1');
    }
    final bech32Codec = Bech32Codec();
    final decoded = bech32Codec.decode(npub);
    if (decoded.hrp != 'npub') {
      throw ArgumentError('Invalid npub format: wrong HRP');
    }
    final bytes = _convertBits(decoded.data, 5, 8, false);
    if (bytes.length != 32) {
      throw ArgumentError('Invalid npub format: wrong key length');
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static List<int> _convertBits(
    List<int> data,
    int fromBits,
    int toBits,
    bool pad,
  ) {
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

  static bool _isValidHexPubkey(String pubkey) {
    return RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(pubkey);
  }
}
