import 'package:flutter/foundation.dart';

import '../config/platform.dart';
import '../exceptions.dart';

/// What happened to one operation (icon or display name) of an update.
enum OperationStatus {
  /// The change was made.
  applied,

  /// Nothing to do: the requested value was already active.
  unchanged,

  /// Accepted, but the OS applies it later.
  pending,

  /// The caller did not ask for this operation.
  notRequested,

  /// The platform cannot do this; see [OperationOutcome.message].
  unsupported,

  /// The platform tried and failed; see [OperationOutcome.message].
  failed,

  /// Not attempted because an earlier operation of the same update failed.
  skipped,
}

/// The outcome of one operation.
@immutable
class OperationOutcome {
  const OperationOutcome(
    this.status, {
    this.errorCode,
    this.message,
    this.suggestion,
  });

  const OperationOutcome.applied({String? message})
    : this(OperationStatus.applied, message: message);
  const OperationOutcome.notRequested() : this(OperationStatus.notRequested);
  const OperationOutcome.unsupported(
    String message, {
    IconShiftErrorCode code = IconShiftErrorCode.unsupportedOperation,
    String? suggestion,
  }) : this(
         OperationStatus.unsupported,
         errorCode: code,
         message: message,
         suggestion: suggestion,
       );
  const OperationOutcome.failed(
    IconShiftErrorCode code,
    String message, {
    String? suggestion,
  }) : this(
         OperationStatus.failed,
         errorCode: code,
         message: message,
         suggestion: suggestion,
       );
  const OperationOutcome.skipped(String message)
    : this(OperationStatus.skipped, message: message);

  final OperationStatus status;
  final IconShiftErrorCode? errorCode;
  final String? message;

  /// How to fix an unsupported or failed operation, if known.
  final String? suggestion;

  /// A copy with [suggestion] (unless one is already set).
  OperationOutcome withSuggestion(String? suggestion) =>
      this.suggestion != null || suggestion == null
      ? this
      : OperationOutcome(
          status,
          errorCode: errorCode,
          message: message,
          suggestion: suggestion,
        );

  /// `true` unless the operation is [OperationStatus.unsupported],
  /// [OperationStatus.failed] or [OperationStatus.skipped].
  bool get isSuccessful => switch (status) {
    OperationStatus.applied ||
    OperationStatus.unchanged ||
    OperationStatus.pending ||
    OperationStatus.notRequested => true,
    OperationStatus.unsupported ||
    OperationStatus.failed ||
    OperationStatus.skipped => false,
  };

  /// `true` when the operation changed (or will change) something.
  bool get didChange =>
      status == OperationStatus.applied || status == OperationStatus.pending;

  @override
  bool operator ==(Object other) =>
      other is OperationOutcome &&
      other.status == status &&
      other.errorCode == errorCode &&
      other.message == message &&
      other.suggestion == suggestion;

  @override
  int get hashCode => Object.hash(status, errorCode, message, suggestion);

  @override
  String toString() =>
      message == null ? status.name : '${status.name} ($message)';
}

/// Result of an IconShift update, reported separately for the icon and the
/// display name because platforms support them independently.
@immutable
class IconShiftResult {
  const IconShiftResult({
    required this.icon,
    required this.displayName,
    this.operation,
    this.platform,
  });

  final OperationOutcome icon;
  final OperationOutcome displayName;

  /// The call that produced this result.
  final IconShiftOperation? operation;

  /// The platform it ran on.
  final IconShiftPlatform? platform;

  /// Every requested operation succeeded (or was already in effect).
  bool get isComplete => icon.isSuccessful && displayName.isSuccessful;

  /// At least one operation failed or was skipped. Unsupported operations
  /// are not failures; check [isComplete] to include them.
  bool get hasFailures =>
      icon.status == OperationStatus.failed ||
      icon.status == OperationStatus.skipped ||
      displayName.status == OperationStatus.failed ||
      displayName.status == OperationStatus.skipped;

  /// Something was changed, but not everything that was requested.
  bool get isPartial =>
      (icon.didChange || displayName.didChange) && !isComplete;

  /// Throws [IdentityUpdateException] unless [isComplete].
  void throwIfFailed() {
    if (!isComplete) throw IdentityUpdateException(this);
  }

  @override
  bool operator ==(Object other) =>
      other is IconShiftResult &&
      other.icon == icon &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(icon, displayName);

  @override
  String toString() =>
      'IconShiftResult(icon: $icon, displayName: $displayName)';
}
