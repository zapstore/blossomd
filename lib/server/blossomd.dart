import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:bip340/bip340.dart' as bip340;

import '../config/blossom_config.dart';
import '../models/nostr_event.dart';
import '../models/blob_descriptor.dart';
import '../services/database_service.dart';
import '../services/whitelist_manager.dart';

class BlossomServer {
  final BlossomConfig config;
  late final Database db;
  late final Router router;
  late final WhitelistManager whitelistManager;

  BlossomServer(this.config) {
    _initializeDatabase();
    _setupRoutes();
  }

  void _initializeDatabase() {
    db = DatabaseService.initialize(config);
    whitelistManager = WhitelistManager(db);
  }

  void _setupRoutes() {
    router = Router();

    // Core blob endpoints
    router.get('/<sha256>', _handleGetBlob);
    router.head('/<sha256>', _handleHeadBlob);

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

  // File operations
  String _getBlobPath(String sha256) {
    final prefix = sha256.substring(0, 2);
    final blobsDir = path.join(config.workingDir, 'blobs', prefix);
    return path.join(blobsDir, sha256);
  }

  void _storeBlobFile(String sha256, Uint8List data) {
    final filePath = _getBlobPath(sha256);
    final dir = Directory(path.dirname(filePath));
    dir.createSync(recursive: true);

    final file = File(filePath);
    file.writeAsBytesSync(data);

    print('[INFO] Stored blob: $sha256 (${data.length} bytes)');
  }

  Future<Response> _handleGetBlob(Request request) async {
    final sha256 = request.params['sha256']!;

    // Validate SHA-256 format
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256)) {
      return Response.notFound('Invalid hash format');
    }

    final filePath = _getBlobPath(sha256.toLowerCase());
    final file = File(filePath);

    if (!file.existsSync()) {
      return Response.notFound('Blob not found');
    }

    final data = file.readAsBytesSync();
    return Response.ok(
      data,
      headers: {
        'content-type': 'application/octet-stream',
        'content-length': data.length.toString(),
      },
    );
  }

  Future<Response> _handleHeadBlob(Request request) async {
    final sha256 = request.params['sha256']!;

    // Validate SHA-256 format
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256)) {
      return Response.notFound('Invalid hash format');
    }

    final filePath = _getBlobPath(sha256.toLowerCase());
    final file = File(filePath);

    if (!file.existsSync()) {
      return Response.notFound('Blob not found');
    }

    final size = file.lengthSync();
    return Response.ok(
      null,
      headers: {
        'content-type': 'application/octet-stream',
        'content-length': size.toString(),
      },
    );
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

      // Check whitelist authorization
      if (!whitelistManager.isWhitelisted(event.pubkey)) {
        return Response.forbidden('blocked: you are not whitelisted');
      }

      // Read file data
      final fileData = await _readRequestBody(request);

      // Check file size limit
      if (fileData.length > maxUploadSize) {
        return Response(400, body: 'blocked: max upload limit is 600MB');
      }

      // Calculate and verify SHA-256
      final calculatedHash = sha256.convert(fileData).toString();
      final expectedHash = event.getTagValue('x');

      if (calculatedHash != expectedHash) {
        return Response(
          400,
          body:
              'Hash mismatch: calculated $calculatedHash, expected $expectedHash',
        );
      }

      // Store the file
      _storeBlobFile(calculatedHash, fileData);
      _storeBlobMetadata(
        calculatedHash,
        event.pubkey,
        fileData.length,
        event.getTagValue('m'),
      );

      // Create blob descriptor response
      final descriptor = BlobDescriptor(
        sha256: calculatedHash,
        size: fileData.length,
        type: event.getTagValue('m'),
        uploaded: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        url: '${config.serverUrl}/$calculatedHash',
      );

      print(
        '[INFO] Upload successful: ${event.pubkey} uploaded $calculatedHash (${fileData.length} bytes)',
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
    return whitelistManager.normalizePubkey(pubkey);
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

  // Helper method to read request body
  Future<Uint8List> _readRequestBody(Request request) async {
    final List<int> bytes = [];
    await for (final chunk in request.read()) {
      bytes.addAll(chunk);
    }
    return Uint8List.fromList(bytes);
  }

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

      // Check whitelist authorization
      if (!whitelistManager.isWhitelisted(event.pubkey)) {
        return Response.forbidden('blocked: you are not whitelisted');
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
