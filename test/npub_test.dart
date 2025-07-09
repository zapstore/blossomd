import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:bip340/bip340.dart' as bip340;

void main() {
  group('Pubkey Format Tests', () {
    late Process serverProcess;
    const String baseUrl = 'http://localhost:3337';
    const String testWorkingDir = './test_data_npub';

    // Test keypair (private key in hex)
    const String testPrivateKey =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    const String testPublicKey =
        '4646ae5047316b4230d0086c8acec687f00b1cd9d1dc634f6cb358ac0a9a8fff';
    const String testNpubKey =
        'npub1ger2u5z8x945yvxsppkg4nkxslcqk8xe68wxxnmvkdv2cz563lls9fwehy';

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
          'PORT': '3337',
          'SERVER_URL': baseUrl,
        },
      );

      // Wait for server to start
      await Future.delayed(Duration(seconds: 3));

      // Add test pubkey to whitelist
      final addWhitelistProcess = await Process.run(
        'dart',
        ['run', 'bin/blossomd.dart', 'whitelist', 'add', testPublicKey],
        workingDirectory: Directory.current.path,
        environment: {
          'WORKING_DIR': testWorkingDir,
          'PORT': '3337',
          'SERVER_URL': baseUrl,
        },
      );

      expect(addWhitelistProcess.exitCode, 0);
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

    test('List endpoint works with both hex and npub formats', () async {
      // Test file content
      final testContent = Uint8List.fromList(
        utf8.encode('Test file for pubkey format testing'),
      );
      final testHash = sha256.convert(testContent).toString();

      // Upload the file
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
      print('✅ Upload successful');

      // Test list with hex format
      final listHexResponse = await http.get(
        Uri.parse('$baseUrl/list/$testPublicKey'),
      );
      expect(listHexResponse.statusCode, 200);
      final listHexResult = jsonDecode(listHexResponse.body) as List;
      expect(listHexResult.length, 1);

      final blobHex = listHexResult[0];
      expect(blobHex['sha256'], testHash);
      expect(blobHex['size'], testContent.length);

      print(
        '✅ List endpoint works with hex format - found ${listHexResult.length} blob(s)',
      );

      // Test list with npub format
      final listNpubResponse = await http.get(
        Uri.parse('$baseUrl/list/$testNpubKey'),
      );
      expect(listNpubResponse.statusCode, 200);
      final listNpubResult = jsonDecode(listNpubResponse.body) as List;
      expect(listNpubResult.length, 1);

      final blobNpub = listNpubResult[0];
      expect(blobNpub['sha256'], testHash);
      expect(blobNpub['size'], testContent.length);

      print(
        '✅ List endpoint works with npub format - found ${listNpubResult.length} blob(s)',
      );

      // Test list with uppercase hex format
      final listUpperHexResponse = await http.get(
        Uri.parse('$baseUrl/list/${testPublicKey.toUpperCase()}'),
      );
      expect(listUpperHexResponse.statusCode, 200);
      final listUpperHexResult = jsonDecode(listUpperHexResponse.body) as List;
      expect(listUpperHexResult.length, 1);

      final blobUpperHex = listUpperHexResult[0];
      expect(blobUpperHex['sha256'], testHash);
      expect(blobUpperHex['size'], testContent.length);

      print(
        '✅ List endpoint works with uppercase hex format - found ${listUpperHexResult.length} blob(s)',
      );

      // Test with invalid pubkey format
      final listInvalidResponse = await http.get(
        Uri.parse('$baseUrl/list/invalid-pubkey'),
      );
      expect(listInvalidResponse.statusCode, 400);
      expect(listInvalidResponse.body, 'Invalid pubkey format');

      print('✅ List endpoint correctly rejects invalid pubkey format');
    });
  });
}

Future<Map<String, dynamic>> createNostrEvent({
  required int kind,
  required String content,
  required List<List<String>> tags,
  required String privateKey,
  required String publicKey,
}) async {
  final createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // Create the event data for hashing
  final eventData = [
    0, // Reserved
    publicKey,
    createdAt,
    kind,
    tags,
    content,
  ];

  // Serialize and hash
  final serialized = jsonEncode(eventData);
  final hash = sha256.convert(utf8.encode(serialized));
  final eventId = hash.toString();

  // Sign the event ID
  final signature = bip340.sign(privateKey, eventId, '');

  return {
    'id': eventId,
    'pubkey': publicKey,
    'created_at': createdAt,
    'kind': kind,
    'tags': tags,
    'content': content,
    'sig': signature,
  };
}
