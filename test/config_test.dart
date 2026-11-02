import 'package:flutter_test/flutter_test.dart';
import 'package:icon_shift/icon_shift.dart';

import 'fakes.dart';

void main() {
  const shared = AppIcon.asset('assets/shared.png');
  const android = AppIcon.asset('assets/android.png');
  const dark = AppIcon.asset('assets/dark.png');
  const darkAndroid = AppIcon.asset('assets/dark_android.png');

  const config = IconShiftConfig(
    defaultIdentity: AppIdentity(
      name: 'My App',
      icon: shared,
      platforms: {
        IconShiftPlatform.android: IdentityOverride(icon: android),
        IconShiftPlatform.web: IdentityOverride(name: 'My Web App'),
      },
    ),
    variants: {
      'dark': AppIdentity(
        name: 'My App Dark',
        icon: dark,
        platforms: {
          IconShiftPlatform.android: IdentityOverride(icon: darkAndroid),
        },
      ),
      'name_only': AppIdentity(name: 'Renamed'),
      'icon_only': AppIdentity(icon: dark),
    },
  );

  group('IconShiftConfig.resolve', () {
    test('one shared icon and name apply to every platform', () {
      for (final p in [IconShiftPlatform.ios, IconShiftPlatform.macos]) {
        final r = config.resolve('default', p);
        expect(r.name, 'My App');
        expect(r.icon, shared);
        expect(r.usesDefaultIcon, isTrue);
        expect(r.isDefault, isTrue);
      }
    });

    test('a platform override replaces only the field it sets', () {
      final a = config.resolve('default', IconShiftPlatform.android);
      expect(a.icon, android);
      expect(a.name, 'My App', reason: 'name is inherited');

      final w = config.resolve('default', IconShiftPlatform.web);
      expect(w.name, 'My Web App');
      expect(w.icon, shared, reason: 'icon is inherited');
    });

    test('variant platform override wins over variant and default', () {
      final r = config.resolve('dark', IconShiftPlatform.android);
      expect(r.icon, darkAndroid);
      expect(r.name, 'My App Dark');
      expect(r.usesDefaultIcon, isFalse);
      expect(r.usesDefaultName, isFalse);
    });

    test('variant fields win over default platform overrides', () {
      expect(config.resolve('dark', IconShiftPlatform.ios).icon, dark);
      expect(config.resolve('dark', IconShiftPlatform.web).name, 'My App Dark');
    });

    test('missing variant fields fall back to default platform override', () {
      final r = config.resolve('name_only', IconShiftPlatform.android);
      expect(r.name, 'Renamed');
      expect(r.icon, android);
      expect(r.usesDefaultIcon, isTrue);

      final w = config.resolve('icon_only', IconShiftPlatform.web);
      expect(w.name, 'My Web App');
      expect(w.usesDefaultName, isTrue);
      expect(w.icon, dark);
    });

    test('null platform skips platform overrides', () {
      expect(config.resolve('default', null).icon, shared);
      expect(config.resolve('dark', null).icon, dark);
    });

    test('unknown variant throws VariantNotFoundException', () {
      expect(
        () => config.resolve('nope', IconShiftPlatform.ios),
        throwsA(
          isA<VariantNotFoundException>()
              .having((e) => e.code, 'code', IconShiftErrorCode.variantNotFound)
              .having((e) => e.availableVariants, 'available', [
                'default',
                'dark',
                'name_only',
                'icon_only',
              ]),
        ),
      );
    });

    test('variantIds lists default first', () {
      expect(demoConfig.variantIds, ['default', 'dark', 'blue', 'pro']);
      expect(demoConfig.hasVariant('default'), isTrue);
      expect(demoConfig.hasVariant('red'), isFalse);
    });
  });

  test('config value equality', () {
    const a = IconShiftConfig(
      defaultIdentity: AppIdentity(name: 'A', icon: shared),
      variants: {'x': AppIdentity(name: 'X')},
    );
    const b = IconShiftConfig(
      defaultIdentity: AppIdentity(name: 'A', icon: shared),
      variants: {'x': AppIdentity(name: 'X')},
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(
      const AppIcon.asset('a.png', package: 'p').assetKey,
      'packages/p/a.png',
    );
  });
}
