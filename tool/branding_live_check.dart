// Checks a real school host against the package's own fetch-and-parse path:
//
//   flutter test tool/branding_live_check.dart --dart-define=host=https://<school>
//
// It talks to the network, so it is not part of `flutter test`.
//
// ignore_for_file: avoid_print — this is a command-line report.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icon_shift/icon_shift.dart';
import 'package:icon_shift/src/platform/http_fetch.dart';

const _host = String.fromEnvironment(
  'host',
  defaultValue: 'https://amena-baki.digiedu.online',
);

void main() {
  test('the school host serves usable branding', () async {
    final tenant = BrandingTenant(host: Uri.parse(_host));
    print('tenant id : ${tenant.id}');
    print('endpoint  : ${tenant.url}');

    final bytes = await httpGetBytes(
      tenant.url,
      maxBytes: BrandingController.maxDocumentBytes,
      headers: const {'Accept': 'application/json'},
    );
    final profile = BrandingProfile.decode(
      utf8.decode(bytes),
      tenantId: tenant.id,
    );

    String? colour(int? argb) => argb == null ? null : hexColor(argb);
    print('app name  : ${profile.displayName}');
    print('primary   : ${colour(profile.primaryColor)}');
    print('secondary : ${colour(profile.secondaryColor)}');
    print('app code  : ${profile.appCode}');
    print('logo      : ${profile.logoUrl}');
    print('launcher  : ${profile.launcherIconUrl}');
    print('version   : ${profile.version}');
    print('cached as : ${jsonEncode(profile.toJson())}');

    expect(profile.isEmpty, isFalse, reason: 'the server sent no branding');
    expect(profile.tenantId, tenant.id);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
