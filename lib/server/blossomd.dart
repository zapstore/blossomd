import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:crypto/crypto.dart' as crypto;
// DigestSink is available from 'package:crypto/crypto.dart'
import 'package:path/path.dart' as path;
import 'package:bip340/bip340.dart' as bip340;
import 'package:http/http.dart' as http;

import '../config/blossom_config.dart';
import '../models/nostr_event.dart';
import '../models/blob_descriptor.dart';
import '../services/database_service.dart';
import '../services/pubkey_utils.dart';

// Local DigestSink implementation if not available from crypto package
class DigestSink implements Sink<crypto.Digest> {
  late crypto.Digest value;
  @override
  void add(crypto.Digest data) {
    value = data;
  }

  @override
  void close() {}
}

class BlossomServer {
  final BlossomConfig config;
  late final Database db;
  late final Router router;
  // Utilities

  BlossomServer(this.config) {
    _initializeDatabase();
    _setupRoutes();
  }

  void _initializeDatabase() {
    db = DatabaseService.initialize(config);
  }

  void _setupRoutes() {
    router = Router();

    // Core blob endpoints
    router.get('/<sha256|[a-fA-F0-9]{64}>', _handleGetBlob);
    router.get('/<sha256|[a-fA-F0-9]{64}>.<ext>', _handleGetBlobWithExt);
    router.head('/<sha256|[a-fA-F0-9]{64}>', _handleHeadBlob);
    router.head('/<sha256|[a-fA-F0-9]{64}>.<ext>', _handleHeadBlobWithExt);

    // Upload endpoints
    router.put('/upload', _handleUpload);
    router.head('/upload', _handleUploadOptions);

    // List endpoint
    router.get('/list/<pubkey>', _handleListBlobs);

    // Delete endpoint
    router.delete('/<sha256>', _handleDeleteBlob);

    print('[INFO] Routes configured');
  }

  // Authentication and authorization
  NostrEvent? _extractNostrEvent(Request request) {
    final auth = request.headers['authorization'];
    if (auth == null || !auth.startsWith('Nostr ')) {
      return null;
    }

    try {
      final base64Event = auth.substring(6); // Remove "Nostr " prefix
      final jsonString = utf8.decode(base64.decode(base64Event));
      final eventJson = jsonDecode(jsonString) as Map<String, dynamic>;
      return NostrEvent.fromJson(eventJson);
    } catch (e) {
      print('[ERROR] Failed to parse Nostr event: $e');
      return null;
    }
  }

  bool verifyNostrEvent(NostrEvent event) {
    try {
      // Verify event structure
      if (event.kind != 24242) return false;
      if (!event.hasTag('t', 'upload')) return false;

      // Check expiration
      final expirationStr = event.getTagValue('expiration');
      if (expirationStr.isNotEmpty) {
        final expiration = int.tryParse(expirationStr);
        if (expiration != null &&
            DateTime.now().millisecondsSinceEpoch ~/ 1000 > expiration) {
          print('[INFO] Event expired: $expiration');
          return false;
        }
      }

      // Verify signature using bip340
      bool verified = false;
      if (event.sig.isNotEmpty) {
        verified = bip340.verify(event.pubkey, event.id, event.sig);
        if (!verified) {
          print('[WARNING] Event ${event.id} has an invalid signature');
        }
      } else {
        print('[WARNING] Event ${event.id} has no signature');
      }

      return verified;
    } catch (e) {
      print('[ERROR] Event verification failed: $e');
      return false;
    }
  }

  // External authorization via Zapstore relay
  Future<bool> _isAcceptedByRelay(String pubkey) async {
    try {
      // Ensure npub format for the API
      String npub;
      if (pubkey.startsWith('npub1')) {
        npub = pubkey;
      } else {
        final normalizedHex = PubkeyUtils.normalizePubkey(pubkey);
        if (normalizedHex == null) {
          return false;
        }
        npub = PubkeyUtils.hexToNpub(normalizedHex);
      }

      final uri = Uri.parse(
        'https://relay.zapstore.dev/api/v1/accept',
      ).replace(queryParameters: {'pubkey': npub});
      final resp = await http.get(uri);
      if (resp.statusCode != 200) {
        print('[WARNING] Relay accept check failed (${resp.statusCode})');
        return false;
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final accept = body['accept'] == true;
      if (!accept) {
        print('[INFO] Relay rejected pubkey: $npub');
      }
      return accept;
    } catch (e) {
      print('[ERROR] Relay accept check error: $e');
      return false;
    }
  }

  // File operations
  String _getBlobPath(String sha256) {
    final blobsDir = path.join(config.workingDir, 'blobs');
    return path.join(blobsDir, sha256);
  }

  // removed unused _storeBlobFile

  // Unified blob response logic
  Future<Response> _serveBlob(String sha256, {bool headOnly = false}) async {
    // Validate SHA-256 format
    if (!RegExp(r'^[a-fA-F0-9]{64}').hasMatch(sha256)) {
      return Response.notFound('Invalid hash format');
    }

    final filePath = _getBlobPath(sha256.toLowerCase());
    final file = File(filePath);

    if (!file.existsSync()) {
      return Response.notFound('Blob not found');
    }

    // Query content-type from database
    String? contentType = 'application/octet-stream';
    try {
      final stmt = db.prepare(
        'SELECT type FROM blobs WHERE sha256 = ? LIMIT 1',
      );
      final result = stmt.select([sha256.toLowerCase()]);
      if (result.isNotEmpty && result.first['type'] != null) {
        contentType = result.first['type'] as String;
      }
    } catch (e) {
      print('[ERROR] Failed to query blob type: $e');
    }
    final safeContentType = contentType ?? 'application/octet-stream';

    if (headOnly) {
      final size = file.lengthSync();
      return Response.ok(
        null,
        headers: {
          'content-type': safeContentType,
          'content-length': size.toString(),
        },
      );
    } else {
      final data = file.readAsBytesSync();
      return Response.ok(
        data,
        headers: {
          'content-type': safeContentType,
          'content-length': data.length.toString(),
        },
      );
    }
  }

  // Handler for /<sha256>
  Future<Response> _handleGetBlob(Request request) async {
    final sha256 = request.params['sha256']!;
    return _serveBlob(sha256, headOnly: false);
  }

  // Handler for /<sha256>.<ext>
  Future<Response> _handleGetBlobWithExt(Request request) async {
    final sha256 = request.params['sha256']!;
    // Extension is ignored for lookup, but could be used for logging if desired
    return _serveBlob(sha256, headOnly: false);
  }

  // Handler for HEAD /<sha256>
  Future<Response> _handleHeadBlob(Request request) async {
    final sha256 = request.params['sha256']!;
    return _serveBlob(sha256, headOnly: true);
  }

  // Handler for HEAD /<sha256>.<ext>
  Future<Response> _handleHeadBlobWithExt(Request request) async {
    final sha256 = request.params['sha256']!;
    return _serveBlob(sha256, headOnly: true);
  }

  // Helper to stream upload to disk and calculate hash as we go
  Future<(String tempPath, int size, crypto.Digest hash)>
  _streamUploadToDiskAndHash(Request request) async {
    // Prepare temp file in blobs dir
    final blobsDir = path.join(config.workingDir, 'blobs');
    Directory(blobsDir).createSync(recursive: true);
    final tempFile = File(
      path.join(
        blobsDir,
        '.upload_${DateTime.now().microsecondsSinceEpoch}_$pid',
      ),
    );
    final sink = tempFile.openWrite();

    final digestSink = DigestSink();
    final hasher = crypto.sha256.startChunkedConversion(digestSink);
    int total = 0;
    await for (final chunk in request.read()) {
      total += chunk.length;
      if (total > maxUploadSize) {
        await sink.close();
        await tempFile.delete();
        throw Exception('blocked: max upload limit is 600MB');
      }
      sink.add(chunk);
      hasher.add(chunk);
    }
    await sink.close();
    hasher.close();
    final digest = digestSink.value;
    return (tempFile.path, total, digest);
  }

  Future<Response> _handleUpload(Request request) async {
    try {
      // Extract and verify Nostr authentication
      final event = _extractNostrEvent(request);
      if (event == null) {
        return Response.forbidden('Missing or invalid Nostr authorization');
      }

      if (!verifyNostrEvent(event)) {
        return Response.forbidden('Invalid Nostr event or signature');
      }

      // External authorization check
      if (!(await _isAcceptedByRelay(event.pubkey))) {
        return Response.forbidden('blocked: not accepted by relay');
      }

      // Stream upload to disk and hash as we go
      String tempPath;
      int fileSize;
      crypto.Digest digest;
      try {
        (tempPath, fileSize, digest) = await _streamUploadToDiskAndHash(
          request,
        );
      } catch (e) {
        return Response(400, body: e.toString());
      }

      final calculatedHash = digest.toString();
      final expectedHash = event.getTagValue('x');

      if (calculatedHash != expectedHash) {
        // Delete temp file
        try {
          await File(tempPath).delete();
        } catch (_) {}
        return Response(
          400,
          body:
              'Hash mismatch: calculated $calculatedHash, expected $expectedHash',
        );
      }

      // Move temp file to final location
      final finalPath = _getBlobPath(calculatedHash);
      final finalFile = File(finalPath);
      if (!finalFile.existsSync()) {
        await File(tempPath).rename(finalPath);
      } else {
        // If file already exists, just delete temp
        await File(tempPath).delete();
      }

      _storeBlobMetadata(
        calculatedHash,
        event.pubkey,
        fileSize,
        event.getTagValue('m'),
      );

      // Create blob descriptor response
      final descriptor = BlobDescriptor(
        sha256: calculatedHash,
        size: fileSize,
        type: event.getTagValue('m'),
        uploaded: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        url: '${config.serverUrl}/$calculatedHash',
      );

      print(
        '[INFO] Upload successful: ${event.pubkey} uploaded $calculatedHash ($fileSize bytes)',
      );

      return Response.ok(
        jsonEncode(descriptor.toJson()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[ERROR] Upload failed: $e');
      return Response.internalServerError();
    }
  }

  Future<Response> _handleUploadOptions(Request request) async {
    return Response.ok(
      null,
      headers: {
        'accept': 'application/octet-stream',
        'x-max-upload-size': maxUploadSize.toString(),
      },
    );
  }

  Future<Response> _handleListBlobs(Request request) async {
    try {
      final pubkey = request.params['pubkey']!;

      // Normalize pubkey to match database format
      final normalizedPubkey = _normalizeToHex(pubkey);
      if (normalizedPubkey == null) {
        return Response(400, body: 'Invalid pubkey format');
      }

      // Query blobs owned by this pubkey
      final stmt = db.prepare('''
        SELECT sha256, size, type, uploaded FROM blobs 
        WHERE pubkey = ? 
        ORDER BY uploaded DESC
      ''');
      final results = stmt.select([normalizedPubkey]);

      final blobs = results.map((row) {
        final sha256 = row['sha256'] as String;
        final size = row['size'] as int;
        final type = row['type'] as String?;
        final uploaded = row['uploaded'] as int;

        return BlobDescriptor(
          sha256: sha256,
          size: size,
          type: type,
          uploaded: uploaded,
          url: '${config.serverUrl}/$sha256',
        );
      }).toList();

      return Response.ok(
        jsonEncode(blobs.map((b) => b.toJson()).toList()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[ERROR] List blobs failed: $e');
      return Response.internalServerError();
    }
  }

  // Helper method to normalize pubkey to hex format
  String? _normalizeToHex(String pubkey) {
    // Use the existing WhitelistManager's normalization logic
    return PubkeyUtils.normalizePubkey(pubkey);
  }

  void _storeBlobMetadata(
    String sha256,
    String pubkey,
    int size,
    String? type,
  ) {
    final uploaded = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Normalize pubkey for consistent storage
    final normalizedPubkey = _normalizeToHex(pubkey) ?? pubkey.toLowerCase();

    try {
      final stmt = db.prepare('''
        INSERT OR REPLACE INTO blobs (sha256, pubkey, size, type, uploaded)
        VALUES (?, ?, ?, ?, ?)
      ''');
      stmt.execute([sha256, normalizedPubkey, size, type, uploaded]);
      print('[INFO] Stored blob metadata: $sha256 for $normalizedPubkey');
    } catch (e) {
      print('[ERROR] Failed to store blob metadata: $e');
    }
  }

  // removed unused _readRequestBody

  Future<Response> _handleDeleteBlob(Request request) async {
    try {
      final sha256 = request.params['sha256']!;

      // Extract and verify Nostr authentication
      final event = _extractNostrEvent(request);
      if (event == null) {
        return Response.forbidden('Missing or invalid Nostr authorization');
      }

      if (!verifyNostrEvent(event)) {
        return Response.forbidden('Invalid Nostr event or signature');
      }

      // External authorization check
      if (!(await _isAcceptedByRelay(event.pubkey))) {
        return Response.forbidden('blocked: not accepted by relay');
      }

      // Check if user owns this blob
      final normalizedPubkey =
          _normalizeToHex(event.pubkey) ?? event.pubkey.toLowerCase();
      final stmt = db.prepare('''
        SELECT COUNT(*) as count FROM blobs 
        WHERE sha256 = ? AND pubkey = ?
      ''');
      final result = stmt.select([sha256.toLowerCase(), normalizedPubkey]);
      final count = result.first['count'] as int;

      if (count == 0) {
        return Response.notFound('Blob not found or you do not own it');
      }

      // Delete the file
      final filePath = _getBlobPath(sha256.toLowerCase());
      final file = File(filePath);

      if (file.existsSync()) {
        // Check if other users also uploaded this file
        final otherOwnersStmt = db.prepare('''
          SELECT COUNT(*) as count FROM blobs 
          WHERE sha256 = ? AND pubkey != ?
        ''');
        final otherOwnersResult = otherOwnersStmt.select([
          sha256.toLowerCase(),
          normalizedPubkey,
        ]);
        final otherOwnersCount = otherOwnersResult.first['count'] as int;

        if (otherOwnersCount == 0) {
          // Only this user owns the file, safe to delete from disk
          file.deleteSync();
          print('[INFO] Deleted blob file: $sha256');
        } else {
          print(
            '[INFO] Kept blob file: $sha256 (other users still reference it)',
          );
        }
      }

      // Remove from database for this user
      final deleteStmt = db.prepare('''
        DELETE FROM blobs WHERE sha256 = ? AND pubkey = ?
      ''');
      deleteStmt.execute([sha256.toLowerCase(), normalizedPubkey]);

      print('[INFO] Deleted blob metadata: $sha256 by $normalizedPubkey');

      return Response.ok('Blob deleted successfully');
    } catch (e) {
      print('[ERROR] Delete failed: $e');
      return Response.internalServerError();
    }
  }

  // Logging middleware
  Handler _logRequests(Handler innerHandler) {
    return (Request request) async {
      final start = DateTime.now();
      print(
        '[${start.toIso8601String()}] ${request.method} ${request.requestedUri}',
      );

      final response = await innerHandler(request);

      final duration = DateTime.now().difference(start);
      print(
        '[${DateTime.now().toIso8601String()}] ${response.statusCode} ${request.method} ${request.requestedUri} (${duration.inMilliseconds}ms)',
      );

      return response;
    };
  }

  Future<void> start() async {
    final handler = Pipeline()
        .addMiddleware(_logRequests)
        .addHandler(router.call);

    final server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      config.port,
    );
    print(
      '[INFO] Blossom server v$version started on ${server.address.host}:${server.port}',
    );
    print('[INFO] Working directory: ${config.workingDir}');
    print('[INFO] Server URL: ${config.serverUrl}');
  }

  void dispose() {
    db.dispose();
  }
}
