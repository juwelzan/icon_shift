import 'package:flutter_test/flutter_test.dart';
import 'package:icon_shift/icon_shift.dart';

// The CLI's copy of the table (plain data, no imports). Keeping a typed copy
// in the plugin avoids a dependency from icon_shift_cli on Flutter; this
// test makes sure the two never drift apart.
// ignore: avoid_relative_lib_imports
import '../cli/lib/src/property_table.dart' as cli;

void main() {
  const runtime = {
    'yes': RuntimeSupport.anyValue,
    'preconfigured': RuntimeSupport.preconfigured,
    'session': RuntimeSupport.sessionOnly,
    'no': RuntimeSupport.none,
  };

  test('plugin and CLI property tables are identical', () {
    expect(
      identityPropertyTable.keys.map((p) => p.name).toSet(),
      cli.propertyTable.keys.toSet(),
    );
    cli.propertyTable.forEach((property, byPlatform) {
      final typed =
          identityPropertyTable[IdentityProperty.values.byName(property)]!;
      expect(typed.keys.map((p) => p.name).toSet(), byPlatform.keys.toSet());
      byPlatform.forEach((platform, e) {
        final s = typed[IconShiftPlatform.values.byName(platform)]!;
        final where = '$property/$platform';
        expect(s.runtime, runtime[e['runtime']], reason: where);
        expect(s.buildTime, e['buildTime'], reason: where);
        expect(s.requiresReinstall, e['reinstall'], reason: where);
        expect(s.requiresNewSigningIdentity, e['resign'], reason: where);
        expect(s.preservesData, e['dataKept'], reason: where);
        expect(s.note, e['note'], reason: where);
      });
    });
  });

  test('the table encodes the platform rules', () {
    final ios = identityPropertiesFor(IconShiftPlatform.ios);
    expect(ios[IdentityProperty.displayName]!.isBuildTimeOnly, isTrue);
    expect(
      ios[IdentityProperty.launcherIcon]!.runtime,
      RuntimeSupport.preconfigured,
    );
    final appId = ios[IdentityProperty.applicationId]!;
    expect(appId.isBuildTimeOnly, isTrue);
    expect(appId.requiresReinstall, isTrue);
    expect(appId.preservesData, isFalse);

    for (final platform in IconShiftPlatform.values) {
      final props = identityPropertiesFor(platform);
      expect(
        props[IdentityProperty.applicationId]!.isRuntimeChangeable,
        isFalse,
        reason: 'no platform changes its installed identity at runtime',
      );
      expect(
        props[IdentityProperty.signingIdentity]!.isRuntimeChangeable,
        isFalse,
      );
    }
    expect(
      identityPropertiesFor(
        IconShiftPlatform.android,
      )[IdentityProperty.displayName]!.runtime,
      RuntimeSupport.preconfigured,
    );
    expect(
      identityPropertiesFor(
        IconShiftPlatform.macos,
      )[IdentityProperty.runningAppIcon]!.runtime,
      RuntimeSupport.sessionOnly,
    );
  });
}
