import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'package:icon_shift_cli/icon_shift_cli.dart';

/// Exit codes: 0 ok · 1 validation errors · 2 refused (conflicts) ·
/// 64 usage · 66 configuration not found.
Future<void> main(List<String> arguments) async {
  final runner =
      CommandRunner<int>(
          'icon_shift_cli',
          'Build-time tooling for icon_shift: native resources, build identity, '
              'validation, preview, backups and rollback.\n\n'
              'Runtime changes (switching icons in an installed app) are done by the '
              'icon_shift plugin, not by this tool.',
        )
        ..argParser.addOption(
          'project',
          abbr: 'p',
          defaultsTo: '.',
          help: 'Flutter project directory.',
        )
        ..argParser.addOption(
          'config',
          abbr: 'c',
          help:
              'Config file (default: icon_shift.yaml, then pubspec.yaml "icon_shift:").',
        )
        ..addCommand(_DoctorCommand())
        ..addCommand(_ValidateCommand())
        ..addCommand(_GenerateCommand())
        ..addCommand(_PreviewCommand())
        ..addCommand(_CapabilitiesCommand())
        ..addCommand(_IdentityCommand())
        ..addCommand(_BrandCommand())
        ..addCommand(_AssetsCommand())
        ..addCommand(_RollbackCommand());
  try {
    exitCode = await runner.run(arguments) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  } on ConfigNotFoundException catch (e) {
    stderr.writeln('ERROR: $e');
    exitCode = 66;
  } on ConfigException catch (e) {
    stderr.writeln('ERROR: $e');
    exitCode = 1;
  }
}

abstract class _Command extends Command<int> {
  String get projectDir =>
      Directory(globalResults!.option('project')!).absolute.path;
  GeneratorConfig loadProjectConfig() =>
      loadConfig(projectDir, configPath: globalResults!.option('config'));

  /// [loadProjectConfig] with `remote:` variants merged and every https
  /// image downloaded into remote.assets_dir.
  Future<GeneratorConfig> loadResolvedConfig({bool refresh = false}) async {
    final resolution = await resolveRemote(
      projectDir,
      loadProjectConfig(),
      refresh: refresh,
    );
    for (final m in resolution.messages) {
      stdout.writeln('INFO: $m');
    }
    return resolution.config;
  }

  /// Prints messages; returns 1 if any is an error.
  int report(Plan plan, {bool showInfo = true}) {
    for (final m in plan.messages) {
      if (m.level == Level.info && !showInfo) continue;
      (m.level == Level.error ? stderr : stdout).writeln(m);
    }
    return plan.hasErrors ? 1 : 0;
  }

  /// Shows, and unless [dryRun] applies, [plan]. Returns the exit code.
  int applyOrPreview(
    Plan plan, {
    required bool dryRun,
    required String label,
    bool diffs = true,
  }) {
    if (report(plan) != 0) {
      stderr.writeln('\nNo files were changed because of the errors above.');
      return 1;
    }
    if (plan.isEmpty) {
      stdout.writeln('\nEverything is up to date.');
      return 0;
    }
    stdout.writeln(
      '\n${dryRun ? 'Dry run — would change' : 'Changing'}:\n${plan.describe(diffs: diffs)}',
    );
    if (!dryRun) {
      final backup = plan.apply(label: label);
      if (backup != null) {
        stdout.writeln(
          'Backup: $backupRoot/${backup.id} (undo with `rollback`).',
        );
      }
    }
    if (plan.nextSteps.isNotEmpty) {
      stdout.writeln('\nNext steps:');
      for (final s in plan.nextSteps) {
        stdout.writeln('  • $s');
      }
    }
    return 0;
  }
}

class _DoctorCommand extends _Command {
  @override
  final name = 'doctor';
  @override
  final description =
      'Check the project setup (platforms, config, Android/iOS integration, backups).';

  @override
  int run() {
    final result = doctor(
      projectDir,
      configPath: globalResults!.option('config'),
    );
    final code = report(result);
    stdout.writeln(
      code == 0 ? '\nNo blocking issues.' : '\nFix the errors above.',
    );
    return code;
  }
}

class _ValidateCommand extends _Command {
  _ValidateCommand() {
    argParser.addOption('profile', help: 'Also validate this build profile.');
  }
  @override
  final name = 'validate';
  @override
  final description =
      'Validate the configuration, images and build identity without writing anything.';

  @override
  Future<int> run() async {
    final config = await loadResolvedConfig();
    final resources = plan(projectDir, config);
    final identity = config.buildIdentity(argResults!.option('profile'));
    if (identity != null) planBuildIdentity(projectDir, identity, resources);
    final code = report(resources, showInfo: false);
    stdout.writeln(
      code == 0 ? 'Configuration is valid.' : '\nConfiguration has errors.',
    );
    return code;
  }
}

class _GenerateCommand extends _Command {
  _GenerateCommand() {
    argParser
      ..addMultiOption(
        'platform',
        allowed: resourceTargets,
        help: 'Only these targets (repeatable).',
      )
      ..addFlag(
        'dry-run',
        abbr: 'n',
        negatable: false,
        help: 'Show the changes without writing.',
      )
      ..addFlag(
        'diff',
        defaultsTo: true,
        help: 'Show line diffs of text files.',
      )
      ..addFlag(
        'refresh-remote',
        negatable: false,
        help:
            'Download https icons and the remote manifest again instead of '
            'reusing remote.assets_dir.',
      );
  }
  @override
  final name = 'generate';
  @override
  final description =
      'Generate native icon/label resources and the Dart config from icon_shift.yaml.';

  @override
  Future<int> run() async {
    final only = argResults!.multiOption('platform');
    final result = plan(
      projectDir,
      await loadResolvedConfig(refresh: argResults!.flag('refresh-remote')),
      only: only.isEmpty ? null : only.toSet(),
    );
    return applyOrPreview(
      result,
      dryRun: argResults!.flag('dry-run'),
      label: 'generate',
      diffs: argResults!.flag('diff'),
    );
  }
}

class _PreviewCommand extends _Command {
  _PreviewCommand() {
    argParser
      ..addOption('variant', help: 'Only this variant.')
      ..addOption('profile', help: 'Preview this build profile.');
  }
  @override
  final name = 'preview';
  @override
  final description =
      'Show how every variant resolves per platform and what a build identity would change.';

  @override
  Future<int> run() async {
    final config = await loadResolvedConfig();
    stdout.writeln('Runtime identities\n');
    stdout.write(preview(config, variant: argResults!.option('variant')));
    final identity = config.buildIdentity(argResults!.option('profile'));
    if (identity == null) return 0;
    stdout.writeln(
      '\nBuild identity${argResults!.option('profile') == null ? '' : ' (profile ${argResults!.option('profile')})'}\n',
    );
    final identityPlan = Plan(projectDir);
    planBuildIdentity(projectDir, identity, identityPlan);
    return applyOrPreview(identityPlan, dryRun: true, label: 'preview');
  }
}

class _CapabilitiesCommand extends _Command {
  _CapabilitiesCommand() {
    argParser.addOption('platform', allowed: platforms);
  }
  @override
  final name = 'capabilities';
  @override
  final description =
      'Which identity properties each platform can change at runtime or build time.';

  @override
  int run() {
    stdout.write(capabilitiesReport(platform: argResults!.option('platform')));
    return 0;
  }
}

class _IdentityCommand extends _Command {
  _IdentityCommand() {
    argParser
      ..addFlag(
        'show',
        negatable: false,
        help: 'Print the identity currently in the native project files.',
      )
      ..addFlag(
        'apply',
        negatable: false,
        help: 'Apply application: (and --profile) to the project files.',
      )
      ..addFlag(
        'reset',
        negatable: false,
        help: 'Undo the most recent --apply (same as rollback of that backup).',
      )
      ..addOption('profile', help: 'Build profile to merge over application:.')
      ..addFlag(
        'dry-run',
        abbr: 'n',
        negatable: false,
        help: 'With --apply: show the changes only.',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'With --reset: overwrite files edited since --apply.',
      );
  }
  @override
  final name = 'identity';
  @override
  final description =
      'Show, apply or reset the build-time identity (ids, names, executable metadata).';

  @override
  int run() {
    final a = argResults!;
    final modes = [
      a.flag('show'),
      a.flag('apply'),
      a.flag('reset'),
    ].where((m) => m).length;
    if (modes != 1) {
      usageException('Use exactly one of --show, --apply, --reset.');
    }
    if (a.flag('show')) {
      final current = readProjectIdentity(projectDir);
      current.values.forEach((platform, values) {
        stdout.writeln(platform);
        values.forEach(
          (k, v) => stdout.writeln('  ${k.padRight(16)} ${v ?? '(not found)'}'),
        );
      });
      return 0;
    }
    if (a.flag('reset')) {
      return _rollback(projectDir, label: 'identity', force: a.flag('force'));
    }
    final identity = loadProjectConfig().buildIdentity(a.option('profile'));
    if (identity == null) {
      stderr.writeln('ERROR: icon_shift.yaml has no "application:" section.');
      return 1;
    }
    final result = Plan(projectDir);
    planBuildIdentity(projectDir, identity, result);
    return applyOrPreview(result, dryRun: a.flag('dry-run'), label: 'identity');
  }
}

class _BrandCommand extends _Command {
  _BrandCommand() {
    argParser
      ..addOption(
        'host',
        help:
            'School host serving GET /api/v1/branding, e.g. '
            'https://abc.digiedu.online.',
      )
      ..addOption('name', help: 'Institution name, instead of --host.')
      ..addOption('icon', help: 'Icon path or https URL, instead of --host.')
      ..addOption(
        'branding-path',
        defaultsTo: '/api/v1/branding',
        help: 'Branding endpoint path on the school host.',
      )
      ..addOption(
        'application-id',
        help: 'Android applicationId; {slug} becomes the school slug.',
      )
      ..addOption('bundle-id', help: 'Apple bundle id; {slug} is expanded.')
      ..addOption(
        'slug',
        help:
            'Identifier for this build (default: from the school host). '
            'Lowercase letters, digits and "_".',
      )
      ..addMultiOption(
        'build',
        allowed: ['apk', 'appbundle', 'ios', 'ios-simulator'],
        help: 'Run this Flutter build after branding (repeatable).',
      )
      ..addFlag(
        'verify',
        defaultsTo: true,
        help: 'Check the built artifact really carries the institution name.',
      )
      ..addFlag(
        'revert',
        defaultsTo: true,
        help:
            'Restore the working tree after building, so the next '
            'institution starts from the shared codebase.',
      )
      ..addOption(
        'artifacts',
        help: 'Directory to copy the branded artifacts and build record into.',
      )
      ..addOption('aapt2', help: 'aapt2 binary used to verify APKs.')
      ..addFlag(
        'refresh-remote',
        negatable: false,
        help: 'Download the icon again instead of reusing the cache.',
      )
      ..addFlag(
        'dry-run',
        abbr: 'n',
        negatable: false,
        help: 'Show what would change without writing or building.',
      );
  }

  @override
  final name = 'brand';
  @override
  final description =
      'Build one institution\'s branded app: fetch its branding, generate the '
      'native name/icon/ids, build, verify the artifact, and restore the '
      'shared codebase.';

  @override
  Future<int> run() async {
    final a = argResults!;
    final host = a.option('host');
    final manual = a.option('name');
    if ((host == null) == (manual == null)) {
      usageException('Pass --host <school url>, or --name (with --icon).');
    }

    // --icon takes a project path or an https URL; planBranding downloads
    // the remote ones before generating.
    final branding = host != null
        ? await InstitutionBranding.fetch(
            Uri.parse(host),
            path: a.option('branding-path')!,
          )
        : InstitutionBranding(
            tenantId: manual!,
            appName: manual,
            logoUrl: a.option('icon'),
          );

    final branded = await planBranding(
      projectDir: projectDir,
      base: loadProjectConfig(),
      branding: branding,
      applicationIdTemplate: a.option('application-id'),
      bundleIdTemplate: a.option('bundle-id'),
      slug: a.option('slug'),
      refreshAssets: a.flag('refresh-remote'),
    );
    for (final m in branded.messages) {
      stdout.writeln('INFO: $m');
    }

    final dryRun = a.flag('dry-run');
    final code = applyOrPreview(
      branded.plan,
      dryRun: dryRun,
      label: 'brand ${branded.slug}',
    );
    if (code != 0 || dryRun) return code;

    final builds = a.multiOption('build');
    final checks = <ArtifactCheck>[];
    var failed = false;
    try {
      for (final target in builds) {
        final built = await _runBuild(target);
        if (built == null) {
          failed = true;
          continue;
        }
        final check = target == 'ios' || target == 'ios-simulator'
            ? inspectAppBundle(built)
            : inspectApk(built, aapt2: a.option('aapt2'));
        checks.add(check);
        stdout.writeln('ARTIFACT: $check');
        if (a.flag('verify') &&
            !check.matches(
              branded.identity.displayName!,
              expectedId: target.startsWith('ios')
                  ? branded.identity.iosBundleId
                  : branded.identity.androidApplicationId,
            )) {
          stderr.writeln(
            'ERROR: ${check.artifact} does not carry '
            '"${branded.identity.displayName}".',
          );
          failed = true;
        }
        _collect(a.option('artifacts'), built, branded, checks);
      }
    } finally {
      if (a.flag('revert')) _revert(branded);
    }
    return failed ? 1 : 0;
  }

  /// Runs `flutter build <target>` and returns the artifact path.
  Future<String?> _runBuild(String target) async {
    final args = switch (target) {
      'apk' => ['build', 'apk', '--release'],
      'appbundle' => ['build', 'appbundle', '--release'],
      'ios' => ['build', 'ios', '--release'],
      _ => ['build', 'ios', '--simulator', '--debug'],
    };
    stdout.writeln('\nflutter ${args.join(' ')}');
    final result = await Process.start(
      'flutter',
      args,
      workingDirectory: projectDir,
      mode: ProcessStartMode.inheritStdio,
    );
    if (await result.exitCode != 0) {
      stderr.writeln('ERROR: flutter ${args.join(' ')} failed.');
      return null;
    }
    final path = switch (target) {
      'apk' => 'build/app/outputs/flutter-apk/app-release.apk',
      'appbundle' => 'build/app/outputs/bundle/release/app-release.aab',
      'ios' => 'build/ios/iphoneos/Runner.app',
      _ => 'build/ios/iphonesimulator/Runner.app',
    };
    return p.join(projectDir, path);
  }

  void _collect(
    String? dir,
    String artifact,
    BrandPlan branded,
    List<ArtifactCheck> checks,
  ) {
    if (dir == null) return;
    final target = p.isAbsolute(dir) ? dir : p.join(projectDir, dir);
    final slug = branded.slug;
    final destination = p.join(target, slug, p.basename(artifact));
    Directory(p.dirname(destination)).createSync(recursive: true);
    final type = FileSystemEntity.typeSync(artifact);
    if (type == FileSystemEntityType.directory) {
      for (final f in Directory(
        artifact,
      ).listSync(recursive: true).whereType<File>()) {
        final relative = p.relative(f.path, from: artifact);
        final out = File(p.join(destination, relative))
          ..parent.createSync(recursive: true);
        f.copySync(out.path);
      }
    } else {
      File(artifact).copySync(destination);
    }
    writeBuildRecord(p.join(target, slug, 'build.json'), branded, checks);
    stdout.writeln('COLLECTED: $destination');
  }

  /// Puts the shared codebase back, so the next institution starts clean.
  void _revert(BrandPlan branded) {
    final backups = Backup.list(projectDir);
    final mine = backups.where((b) => b.label == 'brand ${branded.slug}');
    if (mine.isEmpty) return;
    final (:restored, :conflicts) = mine.last.restore(force: true);
    stdout.writeln('REVERTED: ${restored.length} file(s) restored.');
    if (conflicts.isNotEmpty) {
      stderr.writeln('WARNING: not restored: ${conflicts.join(', ')}');
    }
  }
}

class _AssetsCommand extends _Command {
  _AssetsCommand() {
    argParser.addFlag(
      'check',
      negatable: false,
      defaultsTo: true,
      help: 'Check icon images (existence, format, size).',
    );
  }
  @override
  final name = 'assets';
  @override
  final description =
      'Check the source images referenced by the configuration.';

  @override
  Future<int> run() async =>
      report(checkAssets(projectDir, await loadResolvedConfig()));
}

class _RollbackCommand extends _Command {
  _RollbackCommand() {
    argParser
      ..addFlag('list', negatable: false, help: 'List backups.')
      ..addOption('id', help: 'Backup to restore (default: the most recent).')
      ..addFlag(
        'force',
        negatable: false,
        help: 'Also overwrite files edited after the backup was made.',
      );
  }
  @override
  final name = 'rollback';
  @override
  final description =
      'Restore files from a backup made by generate / identity --apply.';

  @override
  int run() {
    final a = argResults!;
    if (a.flag('list')) {
      final backups = Backup.list(projectDir);
      if (backups.isEmpty) stdout.writeln('No backups.');
      for (final b in backups) {
        stdout.writeln(
          '${b.id}  ${b.label.padRight(9)} ${b.entries.length} file(s)',
        );
      }
      return 0;
    }
    return _rollback(projectDir, id: a.option('id'), force: a.flag('force'));
  }
}

int _rollback(
  String projectDir, {
  String? id,
  String? label,
  bool force = false,
}) {
  final backups = Backup.list(projectDir)
      .where(
        (b) =>
            (id == null || b.id == id) && (label == null || b.label == label),
      )
      .toList();
  if (backups.isEmpty) {
    stderr.writeln(
      'No matching backup found${id == null ? '' : ' with id $id'}.',
    );
    return 1;
  }
  final backup = backups.last;
  final (:restored, :conflicts) = backup.restore(force: force);
  for (final path in restored) {
    stdout.writeln('restored $path');
  }
  if (conflicts.isNotEmpty) {
    stderr.writeln(
      '\nNot restored (changed since ${backup.label} ran; use --force to overwrite):\n'
      '${conflicts.map((c) => '  $c').join('\n')}',
    );
    return 2;
  }
  stdout.writeln('\nRolled back ${backup.label} backup ${backup.id}.');
  return 0;
}
