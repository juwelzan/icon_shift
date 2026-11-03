// Checks a real tenant endpoint through the package's own provider:
//
//   flutter test tool/branding_live_check.dart \
//     --dart-define=url=https://<tenant-host>/api/v1/branding
//
// It talks to the network, so it is not part of `flutter test`.
//
// ignore_for_file: avoid_print — this is a command-line report.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icon_shift/icon_shift.dart';

const _url = String.fromEnvironment(
  'url',
  defaultValue: 'https://amena-baki.digiedu.online/api/v1/branding',
);

void main() {
  test('the tenant endpoint serves usable branding', () async {
    final provider = HttpBrandingProvider(url: Uri.parse(_url));
    print('tenant id : ${provider.tenantId}');
    print('endpoint  : ${provider.url}');

    final profile = await provider.fetch();

    String? colour(int? argb) => argb == null ? null : hexColor(argb);
    print('app name  : ${profile.displayName}');
    print('primary   : ${colour(profile.primaryColor)}');
    print('secondary : ${colour(profile.secondaryColor)}');
    print('code      : ${profile.appCode}');
    print('logo      : ${profile.logoUrl}');
    print('launcher  : ${profile.launcherIconUrl}');
    print('version   : ${profile.version}');
    print('extras    : ${profile.extras.keys.toList()}');
    print('cached as : ${jsonEncode(profile.toJson())}');

    expect(profile.isEmpty, isFalse, reason: 'the server sent no branding');
    expect(profile.tenantId, provider.tenantId);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
