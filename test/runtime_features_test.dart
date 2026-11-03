import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_shift/icon_shift.dart';
import 'package:icon_shift/icon_shift_platform_interface.dart';
import 'package:icon_shift/src/validation/config_validator.dart';

import 'fakes.dart';

const localizedConfig = IconShiftConfig(
  defaultIdentity: AppIdentity(
    name: 'Notes',
    localizedNames: {'de': 'Notizen', 'pt_BR': 'Notas'},
    icon: AppIcon.asset('assets/default.png'),
    platforms: {
      IconShiftPlatform.web: IdentityOverride(
        localizedNames: {'de': 'Notizen (Web)'},
      ),
    },
  ),
  variants: {
    'dark': AppIdentity(
      name: 'Notes Dark',
      localizedNames: {'de': 'Notizen Dunkel'},
      appearance: IdentityAppearance.dark,
      themeColor: 0xFF101010,
      icon: AppIcon.asset('assets/dark.png'),
    ),
    'business': AppIdentity(name: 'Notes for Work'),
  },
  renamedVariants: {'night': 'dark', 'old_red': 'default', 'gone': 'missing'},
);

/// FakePlatform plus theme color and application info.
class RichFakePlatform extends FakePlatform {
  RichFakePlatform(super.capabilities, {super.selection});

  final themeColors = <int?>[];
  ApplicationInfo info = const ApplicationInfo(
    platform: IconShiftPlatform.macos,
    displayName: 'Notes',
    applicationId: 'com.acme.notes',
    version: '1.2.0',
    buildNumber: '7',
    installationType: InstallationType.standard,
  );

  @override
  Future<NativeOperationResult> setThemeColor(int? argb) async {
    themeColors.add(argb);
    return const NativeOperationResult('applied');
  }

  @override
  Future<ApplicationInfo> getApplicationInfo() async => info;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('localized names', () {
    test('resolution prefers locale, then language, at each level', () {
      // The renamed target "missing" is invalid on purpose for another test;
      // resolution itself does not care.
      expect(
        localizedConfig.resolve('default', null, locale: 'de').name,
        'Notizen',
      );
      expect(
        localizedConfig.resolve('default', null, locale: 'de_AT').name,
        'Notizen',
      );
      expect(
        localizedConfig.resolve('default', null, locale: 'pt-BR').name,
        'Notas',
      );
      expect(
        localizedConfig.resolve('default', null, locale: 'fr').name,
        'Notes',
      );
      expect(
        localizedConfig
            .resolve('default', IconShiftPlatform.web, locale: 'de')
            .name,
        'Notizen (Web)',
      );
      expect(
        localizedConfig
            .resolve('dark', IconShiftPlatform.web, locale: 'de')
            .name,
        'Notizen Dunkel',
        reason: 'variant level wins over the default platform override',
      );
      final business = localizedConfig.resolve('business', null, locale: 'de');
      expect(
        business.name,
        'Notes for Work',
        reason: 'own name beats inherited translation',
      );
      expect(business.usesDefaultName, isFalse);
    });

    test('engine applies the localized name on desktop', () async {
      final native = FakePlatform(desktopLike);
      final engine = IconShiftEngine(
        platform: native,
        targetPlatform: IconShiftPlatform.macos,
        assetBundle: FakeAssetBundle({'assets/default.png', 'assets/dark.png'}),
        locale: 'de_DE',
      );
      await engine.initialize(_valid(localizedConfig));
      await engine.setIdentity('dark');
      expect(native.displayName, 'Notizen Dunkel');
    });
  });

  group('validation of new fields', () {
    test('bad locales and broken renames are errors', () {
      const config = IconShiftConfig(
        defaultIdentity: AppIdentity(
          name: 'A',
          localizedNames: {'Deutsch': 'B', 'de': ''},
        ),
        variants: {'dark': AppIdentity(name: 'D')},
        renamedVariants: {'dark': 'default', 'x': 'y'},
      );
      final codes = engineValidation(config);
      expect(
        codes,
        containsAll([
          'invalid_locale',
          'invalid_display_name',
          'renamed_variant_still_configured',
          'invalid_renamed_variant',
        ]),
      );
    });

    test('migrateVariantId follows renames and detects dead ends', () {
      expect(localizedConfig.migrateVariantId('night'), 'dark');
      expect(localizedConfig.migrateVariantId('old_red'), 'default');
      expect(localizedConfig.migrateVariantId('dark'), 'dark');
      expect(localizedConfig.migrateVariantId('gone'), isNull);
      expect(localizedConfig.migrateVariantId('never'), isNull);
      const cyclic = IconShiftConfig(
        defaultIdentity: AppIdentity(),
        renamedVariants: {'a': 'b', 'b': 'a'},
      );
      expect(cyclic.migrateVariantId('a'), isNull);
    });
  });

  group('selection recovery', () {
    test(
      'renamed variants migrate, removed ones and junk are dropped',
      () async {
        final native = FakePlatform(
          desktopLike,
          selection: {
            'identity': 'night',
            'icon': 'night',
            'name': 'bad\nname',
            'mystery': 'x',
          },
        );
        final engine = IconShiftEngine(
          platform: native,
          targetPlatform: IconShiftPlatform.macos,
          assetBundle: FakeAssetBundle({
            'assets/default.png',
            'assets/dark.png',
          }),
        );
        await engine.initialize(
          _valid(localizedConfig),
          restoreSelection: false,
        );
        expect(native.savedSelection, {'identity': 'dark', 'icon': 'dark'});
      },
    );

    test('a variant renamed to default clears the icon', () async {
      final native = FakePlatform(
        iosLike,
        selection: {'icon': 'old_red', 'identity': 'old_red'},
      );
      final engine = IconShiftEngine(
        platform: native,
        targetPlatform: IconShiftPlatform.ios,
      );
      await engine.initialize(_valid(localizedConfig), restoreSelection: false);
      expect(native.savedSelection, isEmpty);
    });

    test('clearSavedSelection forgets without touching native', () async {
      final native = FakePlatform(desktopLike);
      final engine = IconShiftEngine(
        platform: native,
        targetPlatform: IconShiftPlatform.macos,
        assetBundle: FakeAssetBundle(demoAssets),
      );
      await engine.initialize(demoConfig);
      await engine.setIdentity('dark');
      native.calls.clear();
      await engine.clearSavedSelection();
      expect(native.savedSelection, isEmpty);
      expect(native.calls, isEmpty);
      expect(native.iconKey, 'dark');
    });
  });

  group('structured errors', () {
    test('results carry operation, platform and suggestions', () async {
      final native = FakePlatform(androidLike)
        ..iconError = PlatformException(
          code: 'missing_resource',
          message: 'no alias',
        );
      final engine = IconShiftEngine(
        platform: native,
        targetPlatform: IconShiftPlatform.android,
      );
      await engine.initialize(demoConfig);
      final result = await engine.setIdentity('dark');
      expect(result.operation, IconShiftOperation.setIdentity);
      expect(result.platform, IconShiftPlatform.android);
      expect(result.icon.suggestion, contains('icon_shift_cli generate'));
      void error() => result.throwIfFailed();
      expect(
        error,
        throwsA(
          isA<IdentityUpdateException>()
              .having((e) => e.platform, 'platform', IconShiftPlatform.android)
              .having(
                (e) => e.operation,
                'operation',
                IconShiftOperation.setIdentity,
              )
              .having((e) => e.suggestion, 'suggestion', contains('generate')),
        ),
      );
    });

    test(
      'iOS display name is buildRequired with a build-time suggestion',
      () async {
        final engine = IconShiftEngine(
          platform: FakePlatform(iosLike),
          targetPlatform: IconShiftPlatform.ios,
        );
        await engine.initialize(demoConfig);
        final result = await engine.setDisplayName('X');
        expect(result.displayName.status, OperationStatus.unsupported);
        expect(result.displayName.errorCode, IconShiftErrorCode.buildRequired);
        expect(result.displayName.suggestion, contains('icon_shift_cli generate'));
      },
    );

    test('missing asset uses missingAsset', () async {
      final engine = IconShiftEngine(
        platform: FakePlatform(desktopLike),
        targetPlatform: IconShiftPlatform.macos,
        assetBundle: FakeAssetBundle({}),
      );
      await engine.initialize(demoConfig);
      final result = await engine.setIcon('dark');
      expect(result.icon.errorCode, IconShiftErrorCode.missingAsset);
      expect(result.icon.suggestion, contains('pubspec.yaml'));
    });

    test('exception toString includes context', () {
      final e = VariantNotFoundException(
        'x',
        ['default'],
        operation: IconShiftOperation.setIcon,
        platform: IconShiftPlatform.web,
      );
      expect('$e', contains('setIcon on web'));
      expect('$e', contains('Suggestion:'));
    });
  });

  group('queries', () {
    test('getPlatformCapabilities combines live and static data', () async {
      final engine = IconShiftEngine(
        platform: FakePlatform(iosLike),
        targetPlatform: IconShiftPlatform.ios,
      );
      await engine.initialize(demoConfig);
      final caps = await engine.getPlatformCapabilities();
      expect(caps.runtime, iosLike);
      expect(
        caps.buildTimeOnly,
        containsAll([
          IdentityProperty.displayName,
          IdentityProperty.applicationId,
        ]),
      );
      expect(caps.runtimeChangeable, contains(IdentityProperty.launcherIcon));
      expect(caps.requiringReinstall, contains(IdentityProperty.applicationId));
      expect(
        caps.requiredConfiguration.join(),
        contains('ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS'),
      );
      expect(caps.requiredPermissions, isEmpty);
    });

    test('getApplicationInfo adds the current icon variant', () async {
      final native = RichFakePlatform(desktopLike);
      final engine = IconShiftEngine(
        platform: native,
        targetPlatform: IconShiftPlatform.macos,
        assetBundle: FakeAssetBundle(demoAssets),
      );
      await engine.initialize(demoConfig);
      await engine.setIcon('blue');
      final info = await engine.getApplicationInfo();
      expect(info.applicationId, 'com.acme.notes');
      expect(info.currentIconVariant, 'blue');
      expect(info.installationType, InstallationType.standard);
    });

    test('getApplicationInfo degrades instead of throwing', () async {
      final engine = IconShiftEngine(
        platform: FakePlatform(desktopLike),
        targetPlatform: IconShiftPlatform.macos,
      );
      await engine.initialize(demoConfig);
      final info = await engine.getApplicationInfo();
      expect(info.applicationId, isNull, reason: 'nothing invented');
    });

    test('previewIdentity lists every platform and local warnings', () async {
      final engine = IconShiftEngine(
        platform: FakePlatform(iosLike),
        targetPlatform: IconShiftPlatform.ios,
      );
      await engine.initialize(demoConfig);
      final preview = await engine.previewIdentity('dark');
      expect(preview.platforms.keys, IconShiftPlatform.values);
      expect(
        preview.platforms[IconShiftPlatform.ios]!.nameAppliesAtRuntime,
        isFalse,
      );
      expect(
        preview.platforms[IconShiftPlatform.android]!.nameAppliesAtRuntime,
        isTrue,
      );
      expect(
        preview.platforms[IconShiftPlatform.android]!.icon,
        const AppIcon.asset('assets/dark.png'),
      );
      expect(preview.warnings.map((w) => w.code), contains('name_not_applied'));
      expect(preview.isFullyApplicable, isFalse);
      expect(
        () => engine.previewIdentity('nope'),
        throwsA(isA<VariantNotFoundException>()),
      );
    });
  });

  group('web theme color', () {
    test('applied with the identity and restored for the default', () async {
      final native = RichFakePlatform(desktopLike);
      final engine = IconShiftEngine(
        platform: native,
        targetPlatform: IconShiftPlatform.web,
        assetBundle: FakeAssetBundle({'assets/default.png', 'assets/dark.png'}),
      );
      await engine.initialize(_valid(localizedConfig));
      await engine.setIdentity('dark');
      await engine.restoreDefault();
      expect(native.themeColors, [0xFF101010, null]);
    });

    test('not used on other platforms', () async {
      final native = RichFakePlatform(desktopLike);
      final engine = IconShiftEngine(
        platform: native,
        targetPlatform: IconShiftPlatform.macos,
        assetBundle: FakeAssetBundle({'assets/default.png', 'assets/dark.png'}),
      );
      await engine.initialize(_valid(localizedConfig));
      await engine.setIdentity('dark');
      expect(native.themeColors, isEmpty);
    });
  });

  group('theme sync', () {
    tearDown(() {
      IconShift.debugEngine = null;
      debugDefaultTargetPlatformOverride = null;
    });

    test('picks variants by appearance and skips iOS by default', () async {
      final engine = IconShiftEngine(
        platform: FakePlatform(desktopLike),
        targetPlatform: IconShiftPlatform.macos,
      );
      await engine.initialize(_valid(localizedConfig));
      IconShift.debugEngine = engine;
      final sync = IconShiftThemeSync();
      expect(sync.variantFor(Brightness.dark), 'dark');
      expect(sync.variantFor(Brightness.light), 'default');
      expect(
        IconShiftThemeSync(dark: 'business').variantFor(Brightness.dark),
        'business',
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      sync.start();
      expect(sync.isActive, isFalse, reason: 'iOS shows an alert per change');
    });

    test('switches when the platform brightness changes', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;
      final native = FakePlatform(desktopLike);
      final engine = IconShiftEngine(
        platform: native,
        targetPlatform: IconShiftPlatform.macos,
        assetBundle: FakeAssetBundle({'assets/default.png', 'assets/dark.png'}),
      );
      await engine.initialize(_valid(localizedConfig));
      IconShift.debugEngine = engine;
      final results = <IconShiftResult>[];
      dispatcher.platformBrightnessTestValue = Brightness.dark;
      final sync = IconShiftThemeSync(onResult: results.add)..start();
      Future<void> settle() =>
          Future<void>.delayed(const Duration(milliseconds: 50));
      await settle();
      expect(native.iconKey, 'dark');

      dispatcher.platformBrightnessTestValue = Brightness.light;
      sync.didChangePlatformBrightness();
      await settle();
      expect(native.iconKey, 'default');
      expect(results, hasLength(2));

      sync.didChangePlatformBrightness(); // same brightness: no new switch
      await settle();
      expect(results, hasLength(2));
      sync.stop();
      dispatcher.clearPlatformBrightnessTestValue();
    });
  });
}

/// [localizedConfig] without the deliberately broken rename.
IconShiftConfig _valid(IconShiftConfig c) => IconShiftConfig(
  defaultIdentity: c.defaultIdentity,
  variants: c.variants,
  renamedVariants: {...c.renamedVariants}..remove('gone'),
);

List<String> engineValidation(IconShiftConfig config) =>
    validateConfig(config).issues.map((i) => i.code).toList();
