import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:bip340/bip340.dart' as bip340;

void main() {
  group('Blossom Server Roundtrip Tests', () {
    late Process serverProcess;
    const String baseUrl = 'http://localhost:3335';
    const String testWorkingDir = './test_data';

    // Test keypair (private key in hex)
    const String testPrivateKey =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    const String testPublicKey =
        '4646ae5047316b4230d0086c8acec687f00b1cd9d1dc634f6cb358ac0a9a8fff';

    setUpAll(() async {
      // Clean up any existing test data
      final testDir = Directory(testWorkingDir);
      if (testDir.existsSync()) {
        testDir.deleteSync(recursive: true);
      }

      // Start the server in a separate process with test environment
      serverProcess = await Process.start(
        'dart',
        ['run', 'bin/blossomd.dart'],
        workingDirectory: Directory.current.path,
        environment: {
          'WORKING_DIR': testWorkingDir,
          'PORT': '3335',
          'SERVER_URL': baseUrl,
          'DISABLE_RELAY_CHECK': 'true',
          'ALLOWED_PUBKEYS': testPublicKey,
        },
      );

      // Wait for server to start
      await Future.delayed(Duration(seconds: 3));

      // No whitelist setup required
    });

    tearDownAll(() async {
      serverProcess.kill();
      await serverProcess.exitCode;

      // Clean up test data
      final testDir = Directory(testWorkingDir);
      if (testDir.existsSync()) {
        testDir.deleteSync(recursive: true);
      }
    });

    test('Complete roundtrip: upload, list, and get file', () async {
      // Test file content
      final testContent = Uint8List.fromList(
        utf8.encode('Hello, Blossom Server! This is a test file.'),
      );
      final testHash = sha256.convert(testContent).toString();

      // Step 1: Upload the file
      print('Step 1: Uploading file...');

      final uploadEvent = await createNostrEvent(
        kind: 24242,
        content: '',
        tags: [
          ['t', 'upload'],
          ['x', testHash],
          ['m', 'text/plain'],
          [
            'expiration',
            (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600).toString(),
          ],
        ],
        privateKey: testPrivateKey,
        publicKey: testPublicKey,
      );

      final uploadResponse = await http.put(
        Uri.parse('$baseUrl/upload'),
        headers: {
          'Authorization':
              'Nostr ${base64.encode(utf8.encode(jsonEncode(uploadEvent)))}',
          'Content-Type': 'application/octet-stream',
        },
        body: testContent,
      );

      expect(uploadResponse.statusCode, 200);

      final uploadResult = jsonDecode(uploadResponse.body);
      expect(uploadResult['sha256'], testHash);
      expect(uploadResult['size'], testContent.length);
      expect(uploadResult['url'], '$baseUrl/$testHash');

      print('✅ Upload successful: ${uploadResult['url']}');

      // Step 2: Get the file back
      print('Step 2: Getting file back...');

      final getResponse = await http.get(Uri.parse('$baseUrl/$testHash'));
      expect(getResponse.statusCode, 200);
      expect(getResponse.bodyBytes, testContent);

      print('✅ File retrieved successfully');

      // Step 3: Test HEAD request
      print('Step 3: Testing HEAD request...');

      final headResponse = await http.head(Uri.parse('$baseUrl/$testHash'));
      expect(headResponse.statusCode, 200);
      expect(
        headResponse.headers['content-length'],
        testContent.length.toString(),
      );

      print('✅ HEAD request successful');

      // Step 4: List files (should now return the uploaded blob)
      print('Step 4: Testing list endpoint...');

      final listResponse = await http.get(
        Uri.parse('$baseUrl/list/$testPublicKey'),
      );
      expect(listResponse.statusCode, 200);
      final listResult = jsonDecode(listResponse.body) as List;

      // Now the list should contain the uploaded blob
      expect(listResult.length, 1);

      final blob = listResult[0];
      expect(blob['sha256'], testHash);
      expect(blob['size'], testContent.length);
      expect(blob['url'], '$baseUrl/$testHash');

      print('✅ List endpoint working - found ${listResult.length} blob(s)');

      // Step 5: Delete the file
      print('Step 5: Deleting file...');

      final deleteEvent = await createNostrEvent(
        kind: 24242,
        content: '',
        tags: [
          ['t', 'upload'], // Delete uses same tag structure
          ['x', testHash],
          [
            'expiration',
            (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600).toString(),
          ],
        ],
        privateKey: testPrivateKey,
        publicKey: testPublicKey,
      );

      final deleteResponse = await http.delete(
        Uri.parse('$baseUrl/$testHash'),
        headers: {
          'Authorization':
              'Nostr ${base64.encode(utf8.encode(jsonEncode(deleteEvent)))}',
        },
      );

      expect(deleteResponse.statusCode, 200);

      print('✅ File deleted successfully');

      // Step 6: Verify file is gone
      print('Step 6: Verifying file is deleted...');

      final getAfterDeleteResponse = await http.get(
        Uri.parse('$baseUrl/$testHash'),
      );
      expect(getAfterDeleteResponse.statusCode, 404);

      print('✅ File successfully deleted - returns 404');

      // Step 7: Verify list is empty after deletion
      print('Step 7: Verifying list is empty after deletion...');

      final listAfterDeleteResponse = await http.get(
        Uri.parse('$baseUrl/list/$testPublicKey'),
      );
      expect(listAfterDeleteResponse.statusCode, 200);
      final listAfterDeleteResult =
          jsonDecode(listAfterDeleteResponse.body) as List;
      expect(listAfterDeleteResult.length, 0);

      print(
        '✅ List endpoint empty after deletion - found ${listAfterDeleteResult.length} blob(s)',
      );

      print('🎉 Complete roundtrip test passed!');
    });

    test('Upload with invalid signature should fail', () async {
      final testContent = Uint8List.fromList(utf8.encode('Test content'));
      final testHash = sha256.convert(testContent).toString();

      // Create event with invalid signature
      final invalidEvent = {
        'id': 'invalid_id',
        'pubkey': testPublicKey,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'kind': 24242,
        'tags': [
          ['t', 'upload'],
          ['x', testHash],
          ['m', 'text/plain'],
        ],
        'content': '',
        'sig': 'invalid_signature',
      };

      final uploadResponse = await http.put(
        Uri.parse('$baseUrl/upload'),
        headers: {
          'Authorization':
              'Nostr ${base64.encode(utf8.encode(jsonEncode(invalidEvent)))}',
          'Content-Type': 'application/octet-stream',
        },
        body: testContent,
      );

      expect(uploadResponse.statusCode, 403);
      print('✅ Invalid signature correctly rejected');
    });

    test('Upload not accepted by relay should fail', () async {
      final testContent = Uint8List.fromList(utf8.encode('Test content'));
      final testHash = sha256.convert(testContent).toString();

      // Use different keypair not in whitelist
      const String nonWhitelistedPrivateKey =
          'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';
      const String nonWhitelistedPublicKey =
          '88e2ddeb04657dbd0edadf9c1f98da3b3895faa1f00527934dd35d17542ffe9b';

      final uploadEvent = await createNostrEvent(
        kind: 24242,
        content: '',
        tags: [
          ['t', 'upload'],
          ['x', testHash],
          ['m', 'text/plain'],
        ],
        privateKey: nonWhitelistedPrivateKey,
        publicKey: nonWhitelistedPublicKey,
      );

      final uploadResponse = await http.put(
        Uri.parse('$baseUrl/upload'),
        headers: {
          'Authorization':
              'Nostr ${base64.encode(utf8.encode(jsonEncode(uploadEvent)))}',
          'Content-Type': 'application/octet-stream',
        },
        body: testContent,
      );

      expect(uploadResponse.statusCode, 403);
      print('✅ Not accepted by relay correctly rejected');
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

  // Sign the event ID (with auxiliary randomness)
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
