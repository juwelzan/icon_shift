// The Linux embedder exposes no app version; Flutter writes version.json
// next to the bundled assets. dart:io is unavailable on web, hence the
// conditional import.
export 'version_json_stub.dart' if (dart.library.io) 'version_json_io.dart';
