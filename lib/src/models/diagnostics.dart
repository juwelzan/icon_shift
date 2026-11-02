import 'package:flutter/foundation.dart';

import '../config/platform.dart';
import 'capabilities.dart';
import 'result.dart';
import 'state.dart';
import 'validation.dart';

/// A snapshot of everything IconShift knows, for debugging and bug reports.
///
/// Contains no user data: only platform facts, configuration findings and
/// variant ids/names the app itself configured.
@immutable
class IconShiftDiagnostics {
  const IconShiftDiagnostics({
    required this.platform,
    required this.capabilities,
    required this.state,
    required this.validation,
    required this.nativeInfo,
    this.restoreResult,
  });

  final IconShiftPlatform? platform;
  final IconShiftCapabilities capabilities;
  final IconShiftState state;
  final IconShiftValidationResult validation;

  /// Platform facts reported by the native side (OS version, alias
  /// components found, display server, …).
  final Map<String, Object?> nativeInfo;

  /// Result of re-applying the saved selection during initialization, if
  /// that happened.
  final IconShiftResult? restoreResult;

  /// A multi-line, human-readable report.
  String toReport() {
    final b = StringBuffer()
      ..writeln('IconShift diagnostics')
      ..writeln('platform: ${platform?.name ?? 'unsupported'}')
      ..writeln('icon: ${capabilities.icon}')
      ..writeln('displayName: ${capabilities.displayName}')
      ..writeln('iconAndNameLinked: ${capabilities.iconAndNameLinked}');
    for (final note in capabilities.notes) {
      b.writeln('note: $note');
    }
    b.writeln('state: $state');
    if (restoreResult != null) b.writeln('restore on launch: $restoreResult');
    nativeInfo.forEach((k, v) => b.writeln('native.$k: $v'));
    if (validation.issues.isEmpty) {
      b.writeln('validation: no issues');
    } else {
      for (final issue in validation.issues) {
        b.writeln('validation: $issue');
      }
    }
    return b.toString();
  }

  @override
  String toString() => toReport();
}
