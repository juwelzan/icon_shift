import 'dart:io';

import 'package:args/args.dart';
import 'package:icon_shift_generator/icon_shift_generator.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'config',
      abbr: 'c',
      help:
          'Config file (default: icon_shift.yaml, then pubspec.yaml "icon_shift:").',
    )
    ..addOption(
      'project',
      abbr: 'p',
      defaultsTo: '.',
      help: 'Flutter project directory.',
    )
    ..addFlag(
      'dry-run',
      abbr: 'n',
      negatable: false,
      help: 'Show the changes without writing anything.',
    )
    ..addFlag(
      'check',
      negatable: false,
      help: 'Only validate; exit 1 if there are errors.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n${parser.usage}');
    exit(64);
  }
  if (args.flag('help')) {
    stdout.writeln(
      'Generates IconShift native resources (Android activity-alias icons and '
      'labels, iOS alternate app icon sets) and an optional Dart config.\n\n'
      'Usage: dart run icon_shift_generator [options]\n\n${parser.usage}',
    );
    return;
  }

  final projectDir = Directory(args.option('project')!).absolute.path;
  final GeneratorConfig config;
  try {
    config = loadConfig(projectDir, configPath: args.option('config'));
  } on ConfigException catch (e) {
    stderr.writeln('ERROR: $e');
    exit(1);
  }

  final result = plan(projectDir, config);
  for (final message in result.messages) {
    (message.level == Level.error ? stderr : stdout).writeln(message);
  }
  if (result.hasErrors) {
    stderr.writeln('\nNo files were changed because of the errors above.');
    exit(1);
  }
  if (args.flag('check')) {
    stdout.writeln('\nConfiguration is valid.');
    return;
  }

  final changes = [
    for (final path in result.writes.keys) '  write  $path',
    for (final path in result.deletes) '  delete $path',
  ];
  if (args.flag('dry-run')) {
    stdout.writeln(
      changes.isEmpty
          ? '\nDry run: everything is up to date.'
          : '\nDry run — would change:\n${changes.join('\n')}',
    );
    return;
  }
  result.apply();
  stdout.writeln(
    changes.isEmpty
        ? '\nEverything is up to date.'
        : '\nChanged:\n${changes.join('\n')}',
  );
}
