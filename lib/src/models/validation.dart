import 'package:flutter/foundation.dart';

import '../config/platform.dart';

enum ValidationSeverity { error, warning, info }

/// One finding of configuration validation.
@immutable
class ValidationIssue {
  const ValidationIssue({
    required this.severity,
    required this.code,
    required this.message,
    this.variantId,
    this.platform,
  });

  final ValidationSeverity severity;

  /// Stable snake_case identifier, e.g. `missing_asset`, `missing_alias`.
  final String code;

  /// Human-readable explanation including how to fix it.
  final String message;

  /// The variant the issue is about, if any.
  final String? variantId;

  /// The platform the issue is about, if any.
  final IconShiftPlatform? platform;

  @override
  bool operator ==(Object other) =>
      other is ValidationIssue &&
      other.severity == severity &&
      other.code == code &&
      other.message == message &&
      other.variantId == variantId &&
      other.platform == platform;

  @override
  int get hashCode => Object.hash(severity, code, message, variantId, platform);

  @override
  String toString() {
    final where = [
      if (variantId != null) 'variant "$variantId"',
      if (platform != null) platform!.name,
    ];
    final prefix = where.isEmpty ? '' : '[${where.join(', ')}] ';
    return '${severity.name}: $prefix$message ($code)';
  }
}

/// All findings of a validation run.
@immutable
class IconShiftValidationResult {
  const IconShiftValidationResult(this.issues);

  final List<ValidationIssue> issues;

  /// `true` when there are no [ValidationSeverity.error] issues.
  bool get isValid => errors.isEmpty;

  List<ValidationIssue> get errors =>
      issues.where((i) => i.severity == ValidationSeverity.error).toList();

  List<ValidationIssue> get warnings =>
      issues.where((i) => i.severity == ValidationSeverity.warning).toList();

  List<ValidationIssue> issuesFor(String variantId) =>
      issues.where((i) => i.variantId == variantId).toList();

  @override
  String toString() => issues.isEmpty
      ? 'IconShiftValidationResult(no issues)'
      : 'IconShiftValidationResult(\n${issues.map((i) => '  $i').join('\n')}\n)';
}
