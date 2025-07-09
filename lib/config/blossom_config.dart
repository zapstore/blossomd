import 'dart:io';
import 'package:dotenv/dotenv.dart';

const String version = '0.0.1';
const int maxUploadSize = 600 * 1024 * 1024; // 600MB in bytes

class BlossomConfig {
  final String workingDir;
  final int port;
  final String serverUrl;

  BlossomConfig({
    required this.workingDir,
    required this.port,
    required this.serverUrl,
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

    return BlossomConfig(
      workingDir: workingDir,
      port: int.parse(portStr),
      serverUrl: serverUrl,
    );
  }
}
