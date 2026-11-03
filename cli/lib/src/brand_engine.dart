import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'branding.dart';
import 'config.dart';
import 'identity.dart';
import 'plan.dart';
import 'remote.dart' show RemoteFetch, resolveRemote;
// The generator entry point lives in the library root; Dart allows the
// cycle and it keeps the call sites direct.
import '../icon_shift_cli.dart' show plan;

/// Everything one institution's branded build needs, resolved from the
/// school's own branding plus the project's configuration.
class BrandPlan {
  BrandPlan({
    required this.branding,
    required this.slug,
    required this.config,
    required this.identity,
    required this.plan,
    required this.messages,
  });

  final InstitutionBranding branding;

  /// Identifier for this build: the institution slug, or the `--slug`
  /// override. Names the build profile, the artifact folder and `{slug}`.
  final String slug;

  /// The project configuration with this institution's name and icon.
  final GeneratorConfig config;

  /// The build identity (display name, application id, bundle id).
  final BuildIdentity identity;

  /// Every native file change: resources, labels, ids.
  final Plan plan;

  /// What the engine did, for the build log.
  final List<String> messages;

  /// A record of the build, for the pipeline that distributes it.
  Map<String, Object?> toJson() => {
    'branding': branding.toJson(),
    'slug': slug,
    'display_name': identity.displayName,
    'application_id': identity.androidApplicationId,
    'bundle_id': identity.iosBundleId,
    'files': plan.touchedPaths,
  };
}

/// Builds the plan that turns the shared codebase into [branding]'s branded
/// app: launcher name, launcher icon, application label, iOS display name,
/// and — when ids are given — a per-institution application id and bundle id.
///
/// Nothing is written; the caller applies [BrandPlan.plan], builds, and
/// restores the working tree from the backup afterwards.
///
/// [applicationIdTemplate] and [bundleIdTemplate] may contain `{slug}`, e.g.
/// `com.digiedu.{slug}`. Without them the app keeps its own ids, which means
/// one school's build replaces another's on the same device — fine for Mode
/// A testing, wrong for store distribution.
Future<BrandPlan> planBranding({
  required String projectDir,
  required GeneratorConfig base,
  required InstitutionBranding branding,
  String? applicationIdTemplate,
  String? bundleIdTemplate,
  String? slug,
  bool refreshAssets = false,
  RemoteFetch? fetch,
}) async {
  final effectiveSlug = slug ?? branding.slug;
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(effectiveSlug)) {
    throw ConfigException(
      'The slug "$effectiveSlug" must be lowercase letters, digits and "_", '
      'starting with a letter. Pass --slug to choose one.',
    );
  }
  final messages = <String>[];
  final name = branding.appName;
  if (name == null) {
    throw ConfigException(
      'The branding of "${branding.tenantId}" has no app_name, so there is '
      'nothing to brand the build with.',
    );
  }
  messages.add('institution: ${branding.tenantId} ("$name")');

  // A platform override that names the shared app would beat the
  // institution's name on that platform.
  final overridden = [
    for (final MapEntry(key: platform, value: o)
        in base.defaultIdentity.platforms.entries)
      if (o.name != null || o.names.isNotEmpty) platform,
  ];
  if (overridden.isNotEmpty) {
    messages.add(
      'name: dropped the shared per-platform names for '
      '${overridden.join(', ')} so "$name" shows everywhere.',
    );
  }

  final icon = branding.iconSource;
  if (icon == null) {
    messages.add(
      'icon: the server sent neither launcher_icon_url nor logo_url; '
      'keeping the shared app icon.',
    );
  } else {
    messages.add('icon: $icon (also the primary iOS app icon)');
  }

  // The institution's name and icon replace the shared defaults; everything
  // else in icon_shift.yaml (variants, platform options) is untouched.
  final branded = GeneratorConfig(
    defaultIdentity: IdentitySpec(
      name: name,
      icon: icon ?? base.defaultIdentity.icon,
      // The shared app's translations would otherwise keep showing its name
      // on devices in those languages; this schema carries no per-locale
      // institution names.
      names: const {},
      appearance: base.defaultIdentity.appearance,
      themeColor: branding.primaryColor ?? base.defaultIdentity.themeColor,
      platforms: icon == null
          ? {
              for (final MapEntry(key: platform, value: o)
                  in base.defaultIdentity.platforms.entries)
                platform: OverrideSpec(
                  icon: o.icon,
                  monochrome: o.monochrome,
                  adaptiveForeground: o.adaptiveForeground,
                  dark: o.dark,
                  tinted: o.tinted,
                  clear: o.clear,
                ),
            }
          // A per-platform icon would otherwise win over the school's.
          : {
              for (final MapEntry(key: platform, value: o)
                  in base.defaultIdentity.platforms.entries)
                platform: OverrideSpec(
                  monochrome: o.monochrome,
                  adaptiveForeground: o.adaptiveForeground,
                  dark: o.dark,
                  tinted: o.tinted,
                  clear: o.clear,
                ),
            },
    ),
    variants: base.variants,
    android: AndroidOptions(
      enabled: base.android.enabled,
      resDir: base.android.resDir,
      manifest: base.android.manifest,
      targetActivity: base.android.targetActivity,
      adaptiveBackground:
          base.android.adaptiveBackground ?? branding.primaryColor,
      setDisplayName: base.android.setDisplayName,
    ),
    // The institution's icon has to become the *primary* iOS icon; an
    // alternate icon set would leave the home screen on the shared one.
    ios: icon == null
        ? base.ios
        : IosOptions(
            enabled: base.ios.enabled,
            assetCatalog: base.ios.assetCatalog,
            backgroundColor: base.ios.backgroundColor,
            projectDir: base.ios.projectDir,
            primaryIcon: true,
            setDisplayName: base.ios.setDisplayName,
          ),
    outputs: base.outputs,
    renamed: base.renamed,
    dartOutput: base.dartOutput,
    // The institution's name wins over the shared application.display_name,
    // so `generate` and the build identity agree on one name.
    application: (base.application ?? BuildIdentity()).merge(
      BuildIdentity(displayName: name),
    ),
    buildProfiles: base.buildProfiles,
    remote: base.remote,
  );

  // Downloads the school's https icon into remote.assets_dir and rewrites
  // the paths, so the rest of the generator only sees local files.
  final resolved = await resolveRemote(
    projectDir,
    branded,
    refresh: refreshAssets,
    fetch: fetch,
  );
  messages.addAll(resolved.messages);

  // Apple bundle ids reject "_", Android applicationIds reject "-", so
  // {slug} expands to the form each platform accepts.
  String? expand(String? template, String slug) =>
      template?.replaceAll('{slug}', slug);
  final bundleId = expand(bundleIdTemplate, effectiveSlug.replaceAll('_', '-'));
  final identity = BuildIdentity(
    displayName: name,
    androidApplicationId: expand(applicationIdTemplate, effectiveSlug),
    iosBundleId: bundleId,
    macosBundleId: bundleId,
  );
  if (identity.androidApplicationId case final id?) {
    final problem = androidApplicationIdProblem(id);
    if (problem != null) {
      throw ConfigException('application id "$id": $problem');
    }
    messages.add('application id: $id');
  }
  if (identity.iosBundleId case final id?) {
    final problem = appleBundleIdProblem(id);
    if (problem != null) {
      throw ConfigException('bundle id "$id": $problem');
    }
    messages.add('bundle id: $id');
  }

  final changes = plan(projectDir, resolved.config);
  planBuildIdentity(projectDir, identity, changes);
  return BrandPlan(
    branding: branding,
    slug: effectiveSlug,
    config: resolved.config,
    identity: identity,
    plan: changes,
    messages: messages,
  );
}

/// Checks a built artifact really carries [expectedName].
///
/// Android reads the compiled manifest and resources with `aapt2 dump
/// badging`; iOS reads `Info.plist` from the built `.app`. Returns the
/// values found, so a pipeline can fail the build when they do not match.
class ArtifactCheck {
  ArtifactCheck({
    required this.artifact,
    required this.displayName,
    required this.applicationId,
    this.problem,
  });

  final String artifact;
  final String? displayName;
  final String? applicationId;
  final String? problem;

  bool matches(String expectedName, {String? expectedId}) =>
      problem == null &&
      displayName == expectedName &&
      (expectedId == null || applicationId == expectedId);

  @override
  String toString() => problem != null
      ? '$artifact: $problem'
      : '$artifact: name "$displayName", id "$applicationId"';
}

/// Reads the launcher label and application id out of an APK or AAB.
ArtifactCheck inspectApk(String apkPath, {String? aapt2}) {
  final tool = aapt2 ?? _findAapt2();
  if (tool == null) {
    return ArtifactCheck(
      artifact: apkPath,
      displayName: null,
      applicationId: null,
      problem:
          'aapt2 not found; set --aapt2 or add Android build-tools to PATH.',
    );
  }
  if (!File(apkPath).existsSync()) {
    return ArtifactCheck(
      artifact: apkPath,
      displayName: null,
      applicationId: null,
      problem: 'not found',
    );
  }
  final result = Process.runSync(tool, ['dump', 'badging', apkPath]);
  if (result.exitCode != 0) {
    return ArtifactCheck(
      artifact: apkPath,
      displayName: null,
      applicationId: null,
      problem: 'aapt2 failed: ${result.stderr}',
    );
  }
  final out = '${result.stdout}';
  return ArtifactCheck(
    artifact: apkPath,
    displayName: RegExp(
      r"application-label:'([^']*)'",
    ).firstMatch(out)?.group(1),
    applicationId: RegExp(r"package: name='([^']*)'").firstMatch(out)?.group(1),
  );
}

/// Reads `CFBundleDisplayName` and `CFBundleIdentifier` from a built `.app`.
ArtifactCheck inspectAppBundle(String appPath) {
  final plist = p.join(appPath, 'Info.plist');
  if (!File(plist).existsSync()) {
    return ArtifactCheck(
      artifact: appPath,
      displayName: null,
      applicationId: null,
      problem: 'Info.plist not found',
    );
  }
  String? read(String key) {
    final r = Process.runSync('/usr/libexec/PlistBuddy', [
      '-c',
      'Print :$key',
      plist,
    ]);
    return r.exitCode == 0 ? '${r.stdout}'.trim() : null;
  }

  return ArtifactCheck(
    artifact: appPath,
    displayName: read('CFBundleDisplayName') ?? read('CFBundleName'),
    applicationId: read('CFBundleIdentifier'),
  );
}

String? _findAapt2() {
  final home =
      Platform.environment['ANDROID_HOME'] ??
      Platform.environment['ANDROID_SDK_ROOT'] ??
      p.join(Platform.environment['HOME'] ?? '', 'Library/Android/sdk');
  final buildTools = Directory(p.join(home, 'build-tools'));
  if (!buildTools.existsSync()) return null;
  final versions = buildTools.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final dir in versions.reversed) {
    final tool = File(p.join(dir.path, 'aapt2'));
    if (tool.existsSync()) return tool.path;
  }
  return null;
}

/// Writes a build record next to the artifact, so the distribution step
/// knows which institution a file belongs to.
void writeBuildRecord(String path, BrandPlan plan, List<ArtifactCheck> checks) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({
        ...plan.toJson(),
        'artifacts': [
          for (final c in checks) {'path': c.artifact, 'display_name': c.displayName, 'application_id': c.applicationId, 'problem': ?c.problem},
        ],
        'built_at': DateTime.now().toIso8601String(),
      })}\n',
    );
}
