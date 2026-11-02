import 'package:flutter_test/flutter_test.dart';
import 'package:icon_shift/icon_shift.dart';
import 'package:icon_shift/src/validation/config_validator.dart';

import 'fakes.dart';

List<String> codes(IconShiftConfig c) =>
    validateConfig(c).issues.map((i) => i.code).toList();

void main() {
  test('demo config is valid', () {
    final result = validateConfig(demoConfig);
    expect(result.isValid, isTrue, reason: '$result');
  });

  test('reserved and malformed variant ids are errors', () {
    const config = IconShiftConfig(
      defaultIdentity: AppIdentity(name: 'A'),
      variants: {
        'default': AppIdentity(name: 'B'),
        'Dark-Mode': AppIdentity(name: 'C'),
        '1st': AppIdentity(name: 'D'),
      },
    );
    final result = validateConfig(config);
    expect(result.isValid, isFalse);
    expect(codes(config), contains('reserved_variant_id'));
    expect(
      result.errors
          .where((e) => e.code == 'invalid_variant_id')
          .map((e) => e.variantId),
      ['Dark-Mode', '1st'],
    );
  });

  test('invalid display names are errors with the location', () {
    const config = IconShiftConfig(
      defaultIdentity: AppIdentity(
        name: '  ',
        platforms: {IconShiftPlatform.web: IdentityOverride(name: 'a\nb')},
      ),
    );
    final errors = validateConfig(config).errors;
    expect(errors, hasLength(2));
    expect(errors.every((e) => e.code == 'invalid_display_name'), isTrue);
    expect(errors.last.platform, IconShiftPlatform.web);
  });

  test('non-image and svg desktop icons are rejected', () {
    const config = IconShiftConfig(
      defaultIdentity: AppIdentity(
        name: 'A',
        icon: AppIcon.asset('assets/icon.svg'),
        platforms: {
          IconShiftPlatform.macos: IdentityOverride(
            icon: AppIcon.asset('assets/mac.png'),
          ),
        },
      ),
      variants: {'x': AppIdentity(icon: AppIcon.asset('assets/readme.txt'))},
    );
    final result = validateConfig(config);
    expect(codes(config), contains('invalid_icon_path'));
    final svg = result.errors.where((e) => e.code == 'unsupported_icon_format');
    expect(svg.map((e) => e.platform).toSet(), {
      IconShiftPlatform.windows,
      IconShiftPlatform.linux,
    }, reason: 'macOS has a PNG override');
  });

  test('warnings and infos do not make a config invalid', () {
    const config = IconShiftConfig(
      defaultIdentity: AppIdentity(),
      variants: {
        'empty': AppIdentity(),
        'ios_name': AppIdentity(
          platforms: {
            IconShiftPlatform.ios: IdentityOverride(name: 'iOS name'),
            IconShiftPlatform.web: IdentityOverride(),
          },
        ),
        'long': AppIdentity(
          name: 'A really very long application display name',
        ),
      },
    );
    final result = validateConfig(config);
    expect(result.isValid, isTrue);
    expect(
      codes(config),
      containsAll([
        'missing_default_name',
        'missing_default_icon',
        'variant_has_no_effect',
        'name_not_switchable',
        'empty_override',
        'long_display_name',
      ]),
    );
  });

  test('displayNameProblem', () {
    expect(displayNameProblem('Fine'), isNull);
    expect(displayNameProblem(''), isNotNull);
    expect(displayNameProblem('x' * 256), isNotNull);
    expect(displayNameProblem('tab\there'), isNotNull);
  });
}
