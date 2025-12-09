import 'dart:io';
import 'package:dotenv/dotenv.dart';

const String version = '0.0.1';
const int maxUploadSize = 600 * 1024 * 1024; // 600MB in bytes

class BlossomConfig {
  final String workingDir;
  final int port;
  final String serverUrl;
  final bool disableRelayCheck;
  final Set<String> allowedPubkeys;

  BlossomConfig({
    required this.workingDir,
    required this.port,
    required this.serverUrl,
    this.disableRelayCheck = false,
    this.allowedPubkeys = const <String>{},
  });

  static BlossomConfig fromEnvironment() {
    final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();

    // Get values: system environment variables take precedence over .env file, then defaults
    final workingDir =
        Platform.environment['WORKING_DIR'] ?? env['WORKING_DIR'] ?? './data';
    final portStr = Platform.environment['PORT'] ?? env['PORT'] ?? '3334';
    final serverUrl =
        Platform.environment['SERVER_URL'] ??
        env['SERVER_URL'] ??
        'http://localhost:$portStr';
    final disableRelayCheck = _parseBool(
      Platform.environment['DISABLE_RELAY_CHECK'] ?? env['DISABLE_RELAY_CHECK'],
    );
    final allowedPubkeys = _parseAllowedPubkeys(
      Platform.environment['ALLOWED_PUBKEYS'] ?? env['ALLOWED_PUBKEYS'],
    );

    return BlossomConfig(
      workingDir: workingDir,
      port: int.parse(portStr),
      serverUrl: serverUrl,
      disableRelayCheck: disableRelayCheck,
      allowedPubkeys: allowedPubkeys,
    );
  }

  static bool _parseBool(String? value) {
    if (value == null) return false;
    final normalized = value.toLowerCase();
    return normalized == 'true' ||
        normalized == '1' ||
        normalized == 'yes' ||
        normalized == 'y';
  }

  static Set<String> _parseAllowedPubkeys(String? value) {
    if (value == null || value.trim().isEmpty) {
      return <String>{};
    }
    final entries = value
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty);
    return Set<String>.from(entries);
  }
}
