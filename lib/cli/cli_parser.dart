import 'package:args/args.dart';

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
  print('');
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
}
