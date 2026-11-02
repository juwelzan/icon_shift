import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'config.dart';
import 'identity.dart';
import 'images.dart';
import 'ownership.dart';
import 'plan.dart';

/// Opt-in outputs that replace files the Flutter template owns (macOS
/// AppIcon, Windows app_icon.ico, web icons). They are generated from the
/// *default* identity — these are the icons the app ships with — and backed
/// up before writing like every other change.
void planPlatformIcons(
  GeneratorConfig config,
  Plan plan,
  Map<String, SourceIcon> icons,
  Set<String> svgIcons,
) {
  final o = config.outputs;
  if (o.macosAppIcon) _planMacos(config, plan, icons);
  if (o.windowsAppIcon) _planWindows(config, plan, icons);
  if (o.linuxIcons) _planLinux(config, plan, icons, svgIcons);
  if (o.webIcons) _planWeb(config, plan, icons);
}

SourceIcon? _source(
  GeneratorConfig config,
  Plan plan,
  Map<String, SourceIcon> icons,
  String platform,
  int minSize,
) {
  final path = config.resolve(defaultVariantId, platform).icon;
  if (path == null) {
    plan.error('$platform icons: the default identity has no icon.');
    return null;
  }
  final icon = icons[path];
  if (icon == null) {
    if (p.extension(path).toLowerCase() == '.svg') {
      plan.error(
        '$platform icons: "$path" is SVG; add a $platform override with a PNG.',
      );
    }
    return null;
  }
  if (icon.size < minSize) {
    plan.error(
      '$platform icons: "$path" is ${icon.size}px; at least ${minSize}px is needed. Refusing to upscale.',
    );
    return null;
  }
  return icon;
}

void _planMacos(
  GeneratorConfig config,
  Plan plan,
  Map<String, SourceIcon> icons,
) {
  final icon = _source(config, plan, icons, 'macos', 1024);
  if (icon == null) return;
  final dir = '${config.outputs.macosAssetCatalog}/AppIcon.appiconset';
  if (!Directory(
    p.join(plan.projectDir, config.outputs.macosAssetCatalog),
  ).existsSync()) {
    plan.error(
      'macOS asset catalog "${config.outputs.macosAssetCatalog}" not found.',
    );
    return;
  }
  // Same layout as the Flutter template; Xcode compiles it into the .icns.
  const entries = [
    (16, 1, 16),
    (16, 2, 32),
    (32, 1, 32),
    (32, 2, 64),
    (128, 1, 128),
    (128, 2, 256),
    (256, 1, 256),
    (256, 2, 512),
    (512, 1, 512),
    (512, 2, 1024),
  ];
  for (final px in {for (final e in entries) e.$3}) {
    plan.write('$dir/app_icon_$px.png', img.encodePng(resize(icon.image, px)));
  }
  plan.writeString(
    '$dir/Contents.json',
    '${const JsonEncoder.withIndent('  ').convert({
      'images': [
        for (final (size, scale, px) in entries) {'size': '${size}x$size', 'idiom': 'mac', 'filename': 'app_icon_$px.png', 'scale': '${scale}x'},
      ],
      'info': {'version': 1, 'author': 'xcode'},
    })}\n',
  );
  plan.step(
    'macOS: Finder and the Dock may cache the old icon; it refreshes after the rebuilt app is launched (or after `killall Dock`).',
  );
}

void _planWindows(
  GeneratorConfig config,
  Plan plan,
  Map<String, SourceIcon> icons,
) {
  final icon = _source(config, plan, icons, 'windows', 256);
  if (icon == null) return;
  final path = config.outputs.windowsIconPath;
  if (!Directory(p.join(plan.projectDir, p.dirname(path))).existsSync()) {
    plan.error('Windows icon folder "${p.dirname(path)}" not found.');
    return;
  }
  final images = [
    for (final s in const [16, 24, 32, 48, 64, 128, 256]) resize(icon.image, s),
  ];
  plan.write(path, img.IcoEncoder().encodeImages(images));
}

void _planLinux(
  GeneratorConfig config,
  Plan plan,
  Map<String, SourceIcon> icons,
  Set<String> svgIcons,
) {
  final current = readProjectIdentity(plan.projectDir);
  final identity = config.application;
  final appId =
      identity?.linuxApplicationId ?? current.get('linux', 'applicationId');
  final binary =
      identity?.linuxBinaryName ?? current.get('linux', 'binaryName');
  if (appId == null || binary == null) {
    plan.error(
      'linux icons: APPLICATION_ID/BINARY_NAME not found in linux/CMakeLists.txt and not set in application.linux.',
    );
    return;
  }
  final out = config.outputs.linuxOutputDir;
  final desktopPath = '$out/$appId.desktop';
  final existing = File(p.join(plan.projectDir, desktopPath));
  if (existing.existsSync() &&
      !hasGeneratedMarker(existing.readAsStringSync())) {
    plan.error(
      'linux: "$desktopPath" exists and was not created by $toolName; refusing to overwrite it.',
    );
    return;
  }

  final resolved = config.resolve(defaultVariantId, 'linux');
  final source = resolved.icon;
  if (source != null && svgIcons.contains(source)) {
    plan.write(
      '$out/icons/hicolor/scalable/apps/$appId.svg',
      File(p.join(plan.projectDir, source)).readAsBytesSync(),
    );
  } else {
    final icon = _source(config, plan, icons, 'linux', 256);
    if (icon == null) return;
    for (final s in const [16, 32, 48, 64, 128, 256, 512]) {
      if (s > icon.size) continue;
      plan.write(
        '$out/icons/hicolor/${s}x$s/apps/$appId.png',
        img.encodePng(resize(icon.image, s)),
      );
    }
  }

  final name = identity?.displayName ?? resolved.name ?? binary;
  final b = StringBuffer()
    ..writeln(
      '# $generatedMarker. Install as $appId.desktop (see docs/build_time_identity.md).',
    )
    ..writeln('[Desktop Entry]')
    ..writeln('Type=Application')
    ..writeln('Name=${_desktopValue(name)}');
  resolved.names.forEach(
    (locale, n) => b.writeln('Name[$locale]=${_desktopValue(n)}'),
  );
  b
    ..writeln('Icon=$appId')
    ..writeln('Exec=$binary')
    ..writeln('Terminal=false')
    ..writeln('Categories=Utility;')
    ..writeln('StartupWMClass=$binary');
  plan.writeString(desktopPath, b.toString());
  plan.step(
    'Linux: package $out/ with your app (deb/rpm: /usr/share; Flatpak: /app/share; AppImage: the AppDir). IconShift never installs launchers system-wide.',
  );
}

String _desktopValue(String v) =>
    v.replaceAll(r'\', r'\\').replaceAll('\n', r'\n');

void _planWeb(
  GeneratorConfig config,
  Plan plan,
  Map<String, SourceIcon> icons,
) {
  final icon = _source(config, plan, icons, 'web', 512);
  if (icon == null) return;
  final dir = config.outputs.webDir;
  if (!Directory(p.join(plan.projectDir, dir)).existsSync()) {
    plan.error('Web folder "$dir" not found.');
    return;
  }
  plan.write('$dir/favicon.png', img.encodePng(resize(icon.image, 32)));
  for (final s in const [192, 512]) {
    plan.write('$dir/icons/Icon-$s.png', img.encodePng(resize(icon.image, s)));
    // Maskable icons keep content inside the 80% safe zone.
    final masked = flatten(
      inset(icon.image, s, (s * 0.8).round()),
      config.outputs.webMaskableBackground,
    );
    plan.write('$dir/icons/Icon-maskable-$s.png', img.encodePng(masked));
  }
  final manifestPath = '$dir/manifest.json';
  final raw =
      plan.pendingContent(manifestPath) ??
      (File(p.join(plan.projectDir, manifestPath)).existsSync()
          ? File(p.join(plan.projectDir, manifestPath)).readAsStringSync()
          : null);
  if (raw == null) {
    plan.warn(
      'web: $manifestPath not found; icons written but not listed in a manifest.',
    );
    return;
  }
  try {
    final json = jsonDecode(raw) as Map<String, Object?>;
    json['icons'] = [
      for (final s in const [192, 512])
        {'src': 'icons/Icon-$s.png', 'sizes': '${s}x$s', 'type': 'image/png'},
      for (final s in const [192, 512])
        {
          'src': 'icons/Icon-maskable-$s.png',
          'sizes': '${s}x$s',
          'type': 'image/png',
          'purpose': 'maskable',
        },
    ];
    plan.writeString(
      manifestPath,
      '${const JsonEncoder.withIndent('    ').convert(json)}\n',
    );
  } on FormatException catch (e) {
    plan.error('$manifestPath is not valid JSON: ${e.message}');
  }
}
