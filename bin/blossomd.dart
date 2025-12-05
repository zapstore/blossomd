import 'dart:io';
import 'package:args/args.dart';
import 'package:blossomd/blossom.dart';

void main(List<String> arguments) async {
  final ArgParser argParser = buildParser();

  try {
    final ArgResults results = argParser.parse(arguments);

    if (results.flag('help')) {
      printUsage(argParser);
      return;
    }

    if (results.flag('version')) {
      print('blossomd version: $version');
      return;
    }

    final config = BlossomConfig.fromEnvironment();

    // Whitelist commands removed; external authorization is used now

    // Default: start the server
    final server = BlossomServer(config);

    // Handle graceful shutdown
    ProcessSignal.sigint.watch().listen((signal) {
      print('\n[INFO] Received SIGINT, shutting down gracefully...');
      server.dispose();
      exit(0);
    });

    ProcessSignal.sigterm.watch().listen((signal) {
      print('\n[INFO] Received SIGTERM, shutting down gracefully...');
      server.dispose();
      exit(0);
    });

    await server.start();
  } on FormatException catch (e) {
    print(e.message);
    print('');
    printUsage(argParser);
    exit(1);
  } catch (e) {
    print('[ERROR] Failed to start server: $e');
    exit(1);
  }
}
