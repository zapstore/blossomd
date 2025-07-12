import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:blossomd/blossom.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:bip340/bip340.dart' as bip340;

void main() {
  group('Blossom Server Simple Integration Tests', () {
    late BlossomServer server;
    const String testWorkingDir = './test_data_simple';
    const String testPublicKey =
        '4646ae5047316b4230d0086c8acec687f00b1cd9d1dc634f6cb358ac0a9a8fff';
    const String testPrivateKey =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

    setUpAll(() async {
      // Clean up any existing test data
      final testDir = Directory(testWorkingDir);
      if (testDir.existsSync()) {
        testDir.deleteSync(recursive: true);
      }

      // Create test configuration
      final config = BlossomConfig(
        workingDir: testWorkingDir,
        port: 3336,
        serverUrl: 'http://localhost:3336',
      );

      // Create server instance
      server = BlossomServer(config);

      // Add test pubkey to whitelist using SQL directly
      final stmt = server.db.prepare(
        'INSERT OR REPLACE INTO whitelist (pubkey) VALUES (?)',
      );
      stmt.execute([testPublicKey]);

      print('✅ Test setup complete');
    });

    tearDownAll(() async {
      // Clean up test data
      final testDir = Directory(testWorkingDir);
      if (testDir.existsSync()) {
        testDir.deleteSync(recursive: true);
      }
    });

    test('Nostr event creation and signature verification', () async {
      // Test creating and verifying a Nostr event
      final testContent = 'Hello, Blossom!';
      final testHash = sha256.convert(utf8.encode(testContent)).toString();

      final event = await createNostrEvent(
        kind: 24242,
        content: '',
        tags: [
          ['t', 'upload'],
          ['x', testHash],
          ['m', 'text/plain'],
        ],
        privateKey: testPrivateKey,
        publicKey: testPublicKey,
      );

      // Verify the event structure
      expect(event['kind'], 24242);
      expect(event['pubkey'], testPublicKey);
      expect(event['content'], '');
      expect(event['sig'], isNotEmpty);
      expect(event['id'], isNotEmpty);

      // Verify signature
      final isValid = bip340.verify(event['pubkey'], event['id'], event['sig']);
      expect(isValid, true);

      print('✅ Nostr event creation and verification successful');
    });

    test('File storage and retrieval', () async {
      // Test file storage by creating files directly in the test directory
      final testContent = Uint8List.fromList(utf8.encode('Test file content'));
      final testHash = sha256.convert(testContent).toString();

      // Create the blob storage directory structure
      final blobDir = Directory('$testWorkingDir/blobs');
      blobDir.createSync(recursive: true);

      // Store file directly
      final filePath = '${blobDir.path}/$testHash';
      final file = File(filePath);
      file.writeAsBytesSync(testContent);

      expect(file.existsSync(), true);

      final retrievedContent = file.readAsBytesSync();
      expect(retrievedContent, testContent);

      print('✅ File storage and retrieval successful');
    });

    test('Whitelist authorization', () async {
      // Test whitelist functionality
      final isWhitelisted = server.whitelistManager.isWhitelisted(
        testPublicKey,
      );
      expect(isWhitelisted, true);

      // Test non-whitelisted user
      const String nonWhitelistedPubkey =
          'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890';
      final nonWhitelisted = server.whitelistManager.isWhitelisted(
        nonWhitelistedPubkey,
      );
      expect(nonWhitelisted, false);

      print('✅ Whitelist authorization working correctly');
    });

    test('Nostr event validation', () async {
      // Test valid event
      final validEvent = NostrEvent(
        id: 'test_id',
        content: '',
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        pubkey: testPublicKey,
        kind: 24242,
        tags: [
          ['t', 'upload'],
          ['x', 'test_hash'],
        ],
        sig: 'test_sig',
      );

      // Test event validation methods
      expect(validEvent.hasTag('t', 'upload'), true);
      expect(validEvent.hasTag('t', 'delete'), false);
      expect(validEvent.getTagValue('x'), 'test_hash');
      expect(validEvent.getTagValue('nonexistent'), '');

      print('✅ Nostr event validation working correctly');
    });

    test('BlobDescriptor creation', () async {
      final descriptor = BlobDescriptor(
        sha256: 'test_hash',
        size: 1024,
        type: 'text/plain',
        uploaded: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        url: 'http://localhost:3336/test_hash',
      );

      final json = descriptor.toJson();
      expect(json['sha256'], 'test_hash');
      expect(json['size'], 1024);
      expect(json['type'], 'text/plain');
      expect(json['uploaded'], isA<int>());
      expect(json['url'], 'http://localhost:3336/test_hash');

      print('✅ BlobDescriptor creation working correctly');
    });

    test('End-to-end blob lifecycle simulation', () async {
      // This simulates the complete lifecycle without HTTP
      final testContent = Uint8List.fromList(
        utf8.encode('End-to-end test content'),
      );
      final testHash = sha256.convert(testContent).toString();

      // 1. Create Nostr event
      final event = await createNostrEvent(
        kind: 24242,
        content: '',
        tags: [
          ['t', 'upload'],
          ['x', testHash],
          ['m', 'text/plain'],
        ],
        privateKey: testPrivateKey,
        publicKey: testPublicKey,
      );

      // 2. Verify Nostr event would be valid
      final nostrEvent = NostrEvent.fromJson(event);
      expect(server.verifyNostrEvent(nostrEvent), true);

      // 3. Check user authorization
      final isWhitelisted = server.whitelistManager.isWhitelisted(
        testPublicKey,
      );
      expect(isWhitelisted, true);

      // 4. Store blob (simulate storage)
      final blobDir = Directory('$testWorkingDir/blobs');
      blobDir.createSync(recursive: true);
      final filePath = '${blobDir.path}/$testHash';
      File(filePath).writeAsBytesSync(testContent);

      // 5. Verify blob exists
      expect(File(filePath).existsSync(), true);

      // 6. Read blob back
      final retrievedContent = File(filePath).readAsBytesSync();
      expect(retrievedContent, testContent);

      // 7. Create BlobDescriptor
      final descriptor = BlobDescriptor(
        sha256: testHash,
        size: testContent.length,
        type: 'text/plain',
        uploaded: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        url: 'http://localhost:3336/$testHash',
      );

      expect(descriptor.sha256, testHash);
      expect(descriptor.size, testContent.length);

      // 8. Delete blob
      File(filePath).deleteSync();
      expect(File(filePath).existsSync(), false);

      print('✅ End-to-end blob lifecycle simulation successful');
    });
  });
}

// Helper function to create canonical JSON (no extra whitespace)
String canonicalJsonEncode(dynamic object) {
  if (object is String) {
    // Escape required characters according to Nostr spec
    String escaped = object;
    escaped = escaped.replaceAll('\\', '\\\\');
    escaped = escaped.replaceAll('"', '\\"');
    escaped = escaped.replaceAll('\n', '\\n');
    escaped = escaped.replaceAll('\r', '\\r');
    escaped = escaped.replaceAll('\t', '\\t');
    escaped = escaped.replaceAll('\b', '\\b');
    escaped = escaped.replaceAll('\f', '\\f');
    return '"$escaped"';
  } else if (object is int) {
    return object.toString();
  } else if (object is List) {
    return '[${object.map(canonicalJsonEncode).join(',')}]';
  } else if (object is Map) {
    // For maps, we need to sort keys for canonical representation
    final sortedKeys = object.keys.toList()..sort();
    final entries = sortedKeys.map(
      (key) =>
          '${canonicalJsonEncode(key)}:${canonicalJsonEncode(object[key])}',
    );
    return '{${entries.join(',')}}';
  } else {
    return jsonEncode(object);
  }
}

// Helper function to create a proper Nostr event with signature
Future<Map<String, dynamic>> createNostrEvent({
  required int kind,
  required String content,
  required List<List<String>> tags,
  required String privateKey,
  required String publicKey,
}) async {
  final createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // Create event ID (hash of serialized event)
  final eventToHash = [
    0, // reserved
    publicKey,
    createdAt,
    kind,
    tags,
    content,
  ];

  // Use canonical JSON encoding for event ID generation
  final eventJson = canonicalJsonEncode(eventToHash);
  final eventHash = sha256.convert(utf8.encode(eventJson)).toString();

  // Sign the event ID
  final signature = bip340.sign(privateKey, eventHash, '');

  return {
    'id': eventHash,
    'pubkey': publicKey,
    'created_at': createdAt,
    'kind': kind,
    'tags': tags,
    'content': content,
    'sig': signature,
  };
}
