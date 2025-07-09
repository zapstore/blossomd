import 'dart:io';
import 'package:args/args.dart';
import '../config/blossom_config.dart';
import '../services/database_service.dart';
import '../services/whitelist_manager.dart';

ArgParser buildParser() {
  return ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Show additional command output.',
    )
    ..addFlag('version', negatable: false, help: 'Print the tool version.');
}

ArgParser buildWhitelistParser() {
  return ArgParser()
    ..addCommand('add')
    ..addCommand('remove')
    ..addCommand('list')
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print whitelist command usage information.',
    );
}

void printUsage(ArgParser argParser) {
  print('Usage: dart blossomd.dart [options] [command]');
  print('');
  print('Commands:');
  print('  (none)                    Start the Blossom server (default)');
  print('  whitelist <subcommand>    Manage whitelisted pubkeys');
  print('');
  print('Whitelist subcommands:');
  print(
    '  add <pubkey>              Add pubkey to whitelist (hex or npub format)',
  );
  print(
    '  remove <pubkey>           Remove pubkey from whitelist (hex or npub format)',
  );
  print('  list                      List all whitelisted pubkeys');
  print('');
  print('Authorization:');
  print('  Pubkeys in the whitelist are allowed to upload blobs');
  print('  Pubkeys not in the whitelist are denied access');
  print('  Supports both hex format and npub (bech32) format');
  print('');
  print('Configuration:');
  print(
    '  Uses .env file if available, then environment variables, then defaults',
  );
  print('  WORKING_DIR  Base directory for data storage (default: ./data)');
  print('  PORT         HTTP server port (default: 3334)');
  print('  SERVER_URL   Public server URL (default: http://localhost:PORT)');
  print('');
  print('Setup:');
  print('  cp env.example .env  # Copy example configuration');
  print('  # Edit .env with your settings');
  print('');
  print('Options:');
  print(argParser.usage);
  print('');
  print('Examples:');
  print('  dart run bin/blossomd.dart');
  print('  dart run bin/blossomd.dart whitelist add abc123...def');
  print('  dart run bin/blossomd.dart whitelist add npub1...');
  print('  dart run bin/blossomd.dart whitelist list');
  print('  dart run bin/blossomd.dart whitelist remove abc123...def');
  print('  dart run bin/blossomd.dart whitelist remove npub1...');
}

void printWhitelistUsage() {
  print('Usage: dart blossomd.dart whitelist <subcommand> [arguments]');
  print('');
  print('Subcommands:');
  print(
    '  add <pubkey>              Add pubkey to whitelist (hex or npub format)',
  );
  print(
    '  remove <pubkey>           Remove pubkey from whitelist (hex or npub format)',
  );
  print('  list                      List all whitelisted pubkeys');
  print('');
  print('Authorization:');
  print('  Pubkeys in the whitelist are allowed to upload blobs');
  print('  Pubkeys not in the whitelist are denied access');
  print('  Supports both hex format and npub (bech32) format');
  print('');
  print('Pubkey formats:');
  print('  Hex:  64-character lowercase hex string');
  print(
    '        Example: abc123def456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  );
  print('  Npub: bech32-encoded public key starting with npub1');
  print(
    '        Example: npub1xyz123abc456def789ghi012jkl345mno678pqr901stu234vwx567yza890',
  );
  print('');
  print('Examples:');
  print('  dart run bin/blossomd.dart whitelist add abc123...def456');
  print('  dart run bin/blossomd.dart whitelist add npub1xyz123...abc456');
  print('  dart run bin/blossomd.dart whitelist remove abc123...def456');
  print('  dart run bin/blossomd.dart whitelist remove npub1xyz123...abc456');
  print('  dart run bin/blossomd.dart whitelist list');
}

void handleWhitelistCommand(List<String> arguments, BlossomConfig config) {
  if (arguments.isEmpty) {
    printWhitelistUsage();
    exit(1);
  }

  final subcommand = arguments[0];
  final db = DatabaseService.initialize(config);
  final manager = WhitelistManager(db);

  try {
    switch (subcommand) {
      case 'add':
        if (arguments.length != 2) {
          print('Error: add command requires pubkey argument');
          print('Usage: dart run bin/blossomd.dart whitelist add <pubkey>');
          print('       pubkey can be 64-char hex or npub format');
          exit(1);
        }
        final pubkey = arguments[1];
        manager.addPubkey(pubkey);
        break;

      case 'remove':
        if (arguments.length != 2) {
          print('Error: remove command requires pubkey argument');
          print('Usage: dart run bin/blossomd.dart whitelist remove <pubkey>');
          print('       pubkey can be 64-char hex or npub format');
          exit(1);
        }
        final pubkey = arguments[1];
        manager.removePubkey(pubkey);
        break;

      case 'list':
        manager.listPubkeys();
        break;

      default:
        print('Error: unknown whitelist subcommand: $subcommand');
        printWhitelistUsage();
        exit(1);
    }
  } catch (e) {
    print('Error: $e');
    exit(1);
  } finally {
    db.dispose();
  }
}
