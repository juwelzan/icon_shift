import 'dart:convert';
import 'dart:io';

/// `version`/`buildNumber` from `<exe dir>/data/flutter_assets/version.json`.
Map<String, String> readBundledVersionJson() {
  try {
    final file = File(
      '${File(Platform.resolvedExecutable).parent.path}/data/flutter_assets/version.json',
    );
    if (!file.existsSync()) return const {};
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    return {
      if (json['version'] case final String v) 'version': v,
      if (json['build_number'] case final String b) 'buildNumber': b,
    };
  } on Object {
    return const {};
  }
}
