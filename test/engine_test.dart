import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_shift/icon_shift.dart';
import 'package:icon_shift/icon_shift_platform_interface.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePlatform native;

  Future<IconShiftEngine> engineFor(
    IconShiftCapabilities caps,
    IconShiftPlatform platform, {
    Map<String, String>? selection,
    IconShiftConfig config = demoConfig,
    bool restore = true,
  }) async {
    native = FakePlatform(caps, selection: selection);
    final engine = IconShiftEngine(
      platform: native,
      targetPlatform: platform,
      assetBundle: FakeAssetBundle(demoAssets),
    );
    await engine.initialize(config, restoreSelection: restore);
    native.calls.clear();
    return engine;
  }

  group('initialization', () {
    test('methods throw before initialize', () {
      final engine = IconShiftEngine(
        platform: FakePlatform(desktopLike),
        targetPlatform: IconShiftPlatform.macos,
      );
      expect(
        () => engine.setIdentity('dark'),
        throwsA(isA<NotInitializedException>()),
      );
      expect(() => engine.config, throwsA(isA<NotInitializedException>()));
      expect(engine.isInitialized, isFalse);
    });

    test('invalid config throws InvalidConfigurationException', () async {
      final engine = IconShiftEngine(
        platform: FakePlatform(desktopLike),
        targetPlatform: IconShiftPlatform.macos,
      );
      await expectLater(
        engine.initialize(
          const IconShiftConfig(
            defaultIdentity: AppIdentity(name: 'A'),
            variants: {'Bad Id': AppIdentity(name: 'B')},
          ),
        ),
        throwsA(
          isA<InvalidConfigurationException>().having(
            (e) => e.validation.errors.single.code,
            'code',
            'invalid_variant_id',
          ),
        ),
      );
      expect(engine.isInitialized, isFalse);
    });

    test('unsupported platform reports no capabilities', () async {
      final engine = IconShiftEngine(
        platform: FakePlatform(desktopLike),
        targetPlatform: null,
      );
      await engine.initialize(demoConfig);
      final caps = await engine.getCapabilities();
      expect(caps.supportsRuntimeChanges, isFalse);
      final result = await engine.setIdentity('dark');
      expect(result.icon.status, OperationStatus.unsupported);
      expect(result.displayName.status, OperationStatus.unsupported);
      expect(result.isComplete, isFalse);
      expect(result.hasFailures, isFalse);
    });

    test('desktop re-applies the saved selection on launch', () async {
      final engine = IconShiftEngine(
        platform: native = FakePlatform(
          desktopLike,
          selection: {
            'identity': 'dark',
            'icon': 'dark',
            'name': 'My App Dark',
          },
        ),
        targetPlatform: IconShiftPlatform.macos,
        assetBundle: FakeAssetBundle(demoAssets),
      );
      await engine.initialize(demoConfig);
      expect(
        native.calls,
        containsAllInOrder(['setIcon:dark', 'setDisplayName:My App Dark']),
      );
      expect(native.iconRequests.single.bytes, isNotNull);
      expect(engine.restoreResult!.isComplete, isTrue);
    });

    test('restoreSelection: false does not touch native state', () async {
      await engineFor(
        desktopLike,
        IconShiftPlatform.macos,
        selection: {'icon': 'dark'},
        restore: false,
      );
      expect(native.iconRequests, isEmpty);
    });

    test('platforms that persist natively are not re-applied', () async {
      final engine = IconShiftEngine(
        platform: native = FakePlatform(iosLike, selection: {'icon': 'dark'}),
        targetPlatform: IconShiftPlatform.ios,
      );
      await engine.initialize(demoConfig);
      expect(native.iconRequests, isEmpty);
      expect(engine.restoreResult, isNull);
    });

    test('saved variants that no longer exist are forgotten', () async {
      final engine = await engineFor(
        desktopLike,
        IconShiftPlatform.macos,
        selection: {'identity': 'removed', 'icon': 'removed', 'name': 'X'},
        restore: false,
      );
      expect(native.savedSelection, {'name': 'X'});
      expect((await engine.getCurrentIdentity()).requestedIconVariant, isNull);
    });
  });

  group('desktop-like platform', () {
    late IconShiftEngine engine;
    setUp(
      () async =>
          engine = await engineFor(desktopLike, IconShiftPlatform.macos),
    );

    test('setIdentity applies icon bytes and name, then persists', () async {
      final result = await engine.setIdentity('dark');
      expect(result.isComplete, isTrue);
      expect(result.icon.status, OperationStatus.applied);
      expect(result.displayName.status, OperationStatus.applied);
      expect(native.calls, ['setIcon:dark', 'setDisplayName:My App Dark']);
      expect(native.iconRequests.single.assetKey, 'assets/dark.png');
      expect(
        String.fromCharCodes(native.iconRequests.single.bytes!),
        'assets/dark.png',
      );
      expect(native.savedSelection, {
        'icon': 'dark',
        'name': 'My App Dark',
        'identity': 'dark',
      });

      final state = await engine.getCurrentIdentity();
      expect(state.requestedIdentity, 'dark');
      expect(state.nativeIconVariant, 'dark');
      expect(state.isIconInSync, isTrue);
      expect(state.isDisplayNameInSync, isTrue);
    });

    test('icon-only variant restores the shipped name', () async {
      await engine.setIdentity('dark');
      final result = await engine.setIdentity('blue');
      expect(result.displayName.status, OperationStatus.applied);
      expect(native.displayName, 'Shipped');
      expect(native.savedSelection.containsKey('name'), isFalse);
    });

    test('name-only variant restores the shipped icon without bytes', () async {
      await engine.setIdentity('dark');
      native.iconRequests.clear();
      final result = await engine.setIdentity('pro');
      expect(result.isComplete, isTrue);
      expect(native.iconRequests.single.key, 'default');
      expect(native.iconRequests.single.bytes, isNull);
      expect(native.displayName, 'My App Pro');
    });

    test('setIcon changes only the icon', () async {
      final result = await engine.setIcon('blue');
      expect(result.displayName.status, OperationStatus.notRequested);
      expect(native.calls, ['setIcon:blue']);
      expect(native.savedSelection, {'icon': 'blue'});
    });

    test('setDisplayName accepts arbitrary names', () async {
      final result = await engine.setDisplayName('Anything');
      expect(result.isComplete, isTrue);
      expect(result.icon.status, OperationStatus.notRequested);
      expect(native.displayName, 'Anything');
      expect(native.savedSelection, {'name': 'Anything'});
    });

    test('re-applying the same identity reports unchanged', () async {
      await engine.setIdentity('dark');
      final again = await engine.setIdentity('dark');
      expect(again.icon.status, OperationStatus.unchanged);
      expect(again.displayName.status, OperationStatus.unchanged);
      expect(again.isComplete, isTrue);
    });

    test('setCustomIdentity applies both after validating both', () async {
      final result = await engine.setCustomIdentity(
        iconVariant: 'blue',
        displayName: 'Blue Edition',
      );
      expect(result.isComplete, isTrue);
      expect(native.calls, ['setIcon:blue', 'setDisplayName:Blue Edition']);

      expect(
        () => engine.setCustomIdentity(iconVariant: 'blue', displayName: ''),
        throwsA(isA<InvalidArgumentException>()),
      );
      expect(
        () => engine.setCustomIdentity(iconVariant: 'nope', displayName: 'X'),
        throwsA(isA<VariantNotFoundException>()),
      );
      expect(
        () => engine.setCustomIdentity(),
        throwsA(isA<InvalidArgumentException>()),
      );
      expect(native.calls, hasLength(2), reason: 'nothing applied on errors');
    });

    test('icon failure skips the name to stay consistent', () async {
      native.iconError = PlatformException(
        code: 'native_failure',
        message: 'decode failed',
      );
      final result = await engine.setIdentity('dark');
      expect(result.icon.status, OperationStatus.failed);
      expect(result.icon.errorCode, IconShiftErrorCode.nativeOperationFailed);
      expect(result.icon.message, 'decode failed');
      expect(result.displayName.status, OperationStatus.skipped);
      expect(result.hasFailures, isTrue);
      expect(native.calls, ['setIcon:dark'], reason: 'name not attempted');
      expect(native.savedSelection, isEmpty, reason: 'nothing persisted');
      expect(
        () => result.throwIfFailed(),
        throwsA(isA<IdentityUpdateException>()),
      );
    });

    test('name failure after icon success is a partial result', () async {
      native.nameError = PlatformException(code: 'native_failure');
      final result = await engine.setIdentity('dark');
      expect(result.icon.status, OperationStatus.applied);
      expect(result.displayName.status, OperationStatus.failed);
      expect(result.isPartial, isTrue);
      expect(native.savedSelection, {'icon': 'dark', 'identity': 'dark'});
      expect(
        () => result.throwIfFailed(),
        throwsA(
          isA<IdentityUpdateException>().having(
            (e) => e.code,
            'code',
            IconShiftErrorCode.partialUpdate,
          ),
        ),
      );
    });

    test('missing asset fails without calling native', () async {
      final engine = IconShiftEngine(
        platform: native = FakePlatform(desktopLike),
        targetPlatform: IconShiftPlatform.macos,
        assetBundle: FakeAssetBundle({}),
      );
      await engine.initialize(demoConfig);
      native.calls.clear();
      final result = await engine.setIcon('dark');
      expect(result.icon.errorCode, IconShiftErrorCode.missingAsset);
      expect(native.calls, isEmpty);
    });

    test(
      'restoreDefault resets icon and name and clears the selection',
      () async {
        await engine.setIdentity('dark');
        native.iconRequests.clear();
        final result = await engine.restoreDefault();
        expect(result.isComplete, isTrue);
        expect(native.iconRequests.single.key, 'default');
        expect(native.calls.last, 'setDisplayName:null');
        expect(native.savedSelection, isEmpty);
      },
    );

    test('platform error codes map to IconShiftErrorCode', () async {
      final cases = {
        'missing_resource': IconShiftErrorCode.missingNativeResource,
        'permission_denied': IconShiftErrorCode.permissionDenied,
        'not_active': IconShiftErrorCode.appNotActive,
        'invalid_argument': IconShiftErrorCode.invalidArgument,
        'weird': IconShiftErrorCode.nativeOperationFailed,
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        native.iconError = PlatformException(code: key);
        expect(
          (await engine.setIcon('dark')).icon.errorCode,
          value,
          reason: key,
        );
      }
      native.iconError = PlatformException(code: 'unsupported', message: 'no');
      expect(
        (await engine.setIcon('dark')).icon.status,
        OperationStatus.unsupported,
      );
    });

    test('operations are serialized', () async {
      final results = await Future.wait([
        engine.setIdentity('dark'),
        engine.setIdentity('blue'),
        engine.setDisplayName('Last'),
      ]);
      expect(results.every((r) => r.isComplete), isTrue);
      expect(native.calls, [
        'setIcon:dark',
        'setDisplayName:My App Dark',
        'setIcon:blue',
        'setDisplayName:null',
        'setDisplayName:Last',
      ]);
    });

    test('invalid names and unknown variants throw', () {
      expect(
        () => engine.setDisplayName('a\nb'),
        throwsA(isA<InvalidArgumentException>()),
      );
      expect(
        () => engine.setIcon('nope'),
        throwsA(isA<VariantNotFoundException>()),
      );
    });
  });

  group('android-like platform (linked icon and label)', () {
    late IconShiftEngine engine;
    setUp(() async {
      engine = await engineFor(androidLike, IconShiftPlatform.android);
      native.aliasLabels = {
        'default': 'My App',
        'dark': 'My App Dark',
        'blue': 'My App',
        'pro': 'My App Pro',
      };
    });

    test(
      'setIdentity switches the alias and reports the linked label',
      () async {
        final result = await engine.setIdentity('dark');
        expect(native.calls, ['setIcon:dark']);
        expect(
          native.iconRequests.single.bytes,
          isNull,
          reason: 'Android uses compiled resources',
        );
        expect(result.icon.status, OperationStatus.applied);
        expect(result.displayName.status, OperationStatus.applied);
        expect(result.displayName.message, contains('"My App Dark"'));
        expect(result.isComplete, isTrue);
      },
    );

    test('every variant has its own alias, even name-only ones', () async {
      await engine.setIdentity('pro');
      expect(native.iconRequests.single.key, 'pro');
    });

    test('setIcon behaves like setIdentity', () async {
      final result = await engine.setIcon('pro');
      expect(result.displayName.status, OperationStatus.applied);
      expect(native.savedSelection['identity'], 'pro');
    });

    test('arbitrary display names are unsupported', () async {
      final result = await engine.setDisplayName('Custom');
      expect(result.displayName.status, OperationStatus.unsupported);
      expect(result.displayName.message, contains('setIdentity'));
      expect(native.calls, isEmpty);
    });

    test('batch: icon applies, arbitrary name is unsupported', () async {
      final result = await engine.setCustomIdentity(
        iconVariant: 'blue',
        displayName: 'Custom',
      );
      expect(result.icon.status, OperationStatus.applied);
      expect(result.displayName.status, OperationStatus.unsupported);
      expect(result.isPartial, isTrue);
      expect(result.hasFailures, isFalse);
    });

    test('missing alias fails and the label is skipped', () async {
      native.iconError = PlatformException(
        code: 'missing_resource',
        message: 'No activity-alias for "dark"',
      );
      final result = await engine.setIdentity('dark');
      expect(result.icon.errorCode, IconShiftErrorCode.missingNativeResource);
      expect(result.displayName.status, OperationStatus.skipped);
    });
  });

  group('ios-like platform (name unsupported)', () {
    late IconShiftEngine engine;
    setUp(() async => engine = await engineFor(iosLike, IconShiftPlatform.ios));

    test('named variant: icon applied, name unsupported → partial', () async {
      final result = await engine.setIdentity('dark');
      expect(result.icon.status, OperationStatus.applied);
      expect(result.displayName.status, OperationStatus.unsupported);
      expect(result.isPartial, isTrue);
      expect(native.calls, ['setIcon:dark']);
    });

    test('icon-only variant is complete', () async {
      final result = await engine.setIdentity('blue');
      expect(result.isComplete, isTrue);
      expect(result.displayName.status, OperationStatus.notRequested);
    });

    test('name-only variant maps to the primary icon', () async {
      final result = await engine.setIdentity('pro');
      expect(native.iconRequests.single.key, 'default');
      expect(result.icon.status, OperationStatus.unchanged);
      expect(native.savedSelection.containsKey('icon'), isFalse);
      expect((await engine.getCurrentIdentity()).isIconInSync, isTrue);
    });

    test('state reports divergence between requested and native', () async {
      await engine.setIcon('dark');
      native.iconKey = 'default'; // e.g. reinstalled
      final state = await engine.getCurrentIdentity();
      expect(state.requestedIconVariant, 'dark');
      expect(state.nativeIconVariant, 'default');
      expect(state.isIconInSync, isFalse);
    });
  });

  group('queries', () {
    test(
      'getVariants resolves per platform and reports availability',
      () async {
        final engine = await engineFor(iosLike, IconShiftPlatform.ios);
        native.inspectionIssues = const [
          ValidationIssue(
            severity: ValidationSeverity.error,
            code: 'missing_alternate_icon',
            message: 'No alternate icon "blue"',
            variantId: 'blue',
          ),
        ];
        native.iconKey = 'dark';
        final variants = await engine.getVariants();
        expect(variants.map((v) => v.id), ['default', 'dark', 'blue', 'pro']);
        final byId = {for (final v in variants) v.id: v};
        expect(byId['default']!.isDefault, isTrue);
        expect(byId['dark']!.isCurrentIcon, isTrue);
        expect(
          byId['dark']!.previewIcon,
          const AppIcon.asset('assets/dark.png'),
        );
        expect(byId['blue']!.isAvailable, isFalse);
        expect(byId['blue']!.unavailableReason, 'No alternate icon "blue"');
        expect(byId['pro']!.displayName, 'My App Pro');
        expect(byId['pro']!.isCurrentIcon, isFalse);
      },
    );

    test('variants are unavailable where nothing can change', () async {
      final engine = await engineFor(
        IconShiftCapabilities.none(IconShiftPlatform.linux, 'Wayland'),
        IconShiftPlatform.linux,
      );
      final variants = await engine.getVariants();
      expect(variants.every((v) => !v.isAvailable), isTrue);
      expect(variants.first.unavailableReason, 'Wayland');
    });

    test(
      'validateConfiguration reports missing assets and native issues',
      () async {
        native = FakePlatform(androidLike)
          ..inspectionIssues = const [
            ValidationIssue(
              severity: ValidationSeverity.warning,
              code: 'duplicate_launcher',
              message: 'MainActivity still has a LAUNCHER intent filter',
            ),
          ];
        final engine = IconShiftEngine(
          platform: native,
          targetPlatform: IconShiftPlatform.android,
          assetBundle: FakeAssetBundle({'assets/default.png'}),
        );
        await engine.initialize(demoConfig);
        final result = await engine.validateConfiguration();
        final missing = result.errors
            .where((e) => e.code == 'missing_asset')
            .map((e) => e.variantId)
            .toList();
        expect(missing, ['default', 'dark', 'blue']);
        expect(
          result.issues.map((i) => i.code),
          contains('duplicate_launcher'),
        );
      },
    );

    test('diagnostics report contains platform facts', () async {
      final engine = await engineFor(desktopLike, IconShiftPlatform.macos);
      final report = (await engine.getDiagnostics()).toReport();
      expect(report, contains('platform: macos'));
      expect(report, contains('native.fake: true'));
      expect(report, contains('validation: no issues'));
    });
  });

  group('IconShift facade', () {
    tearDown(() => IconShift.debugEngine = null);

    test('delegates to the engine', () async {
      final engine = await engineFor(desktopLike, IconShiftPlatform.macos);
      IconShift.debugEngine = engine;
      expect(IconShift.isInitialized, isTrue);
      expect(IconShift.config, demoConfig);
      final result = await IconShift.setIdentity('dark');
      expect(result.isComplete, isTrue);
      expect((await IconShift.getCurrentIdentity()).nativeIconVariant, 'dark');
    });

    test('throws before initialize', () {
      expect(IconShift.isInitialized, isFalse);
      expect(
        () => IconShift.setIcon('x'),
        throwsA(isA<NotInitializedException>()),
      );
    });

    test('initialize uses the registered platform instance', () async {
      final fake = FakePlatform(desktopLike);
      IconShiftPlatformInterface.instance = fake;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await IconShift.initialize(demoConfig);
        expect(
          (await IconShift.getCapabilities()).platform,
          IconShiftPlatform.macos,
          reason: 'from the fake',
        );
        final result = await IconShift.setDisplayName('Hi');
        expect(result.isComplete, isTrue);
        expect(fake.displayName, 'Hi');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
