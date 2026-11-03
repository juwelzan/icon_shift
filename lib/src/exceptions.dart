import 'config/platform.dart';
import 'models/result.dart';
import 'models/validation.dart';

/// Machine-readable reason attached to exceptions and failed operations.
enum IconShiftErrorCode {
  /// An IconShift method was called before [IconShift.initialize].
  notInitialized,

  /// No configuration was given or found.
  configurationNotFound,

  /// The variant id is not part of the configuration.
  variantNotFound,

  /// The configuration has validation errors.
  invalidConfiguration,

  /// An argument (e.g. a display name) is invalid.
  invalidArgument,

  /// The platform cannot perform this operation at all.
  unsupportedOperation,

  /// The OS only allows this change at build time (e.g. the iOS display
  /// name); rebuild with the new value.
  buildRequired,

  /// An icon asset is not bundled with the app (pubspec.yaml assets).
  missingAsset,

  /// A native resource the variant needs (activity-alias, alternate icon)
  /// is missing from the build.
  missingNativeResource,

  /// An application/bundle/package identifier is invalid (icon_shift_cli).
  invalidApplicationIdentifier,

  /// The change would require a different signing identity or provisioning
  /// (icon_shift_cli); IconShift never handles signing.
  signingRestriction,

  /// The OS denied the operation.
  permissionDenied,

  /// The operation needs the app in the foreground (iOS).
  appNotActive,

  /// The native call failed; see the message for the OS error.
  nativeOperationFailed,

  /// A remote icon could not be downloaded or is not an image.
  downloadFailed,

  /// Some operations of a combined update did not succeed.
  partialUpdate,
}

/// The IconShift operation an error or result belongs to.
enum IconShiftOperation {
  initialize,
  setIdentity,
  setIcon,
  setDisplayName,
  setCustomIdentity,
  setRemoteIcon,
  restoreDefault,
  query,
}

/// Base class of all exceptions thrown by IconShift.
abstract class IconShiftException implements Exception {
  const IconShiftException(
    this.code,
    this.message, {
    this.operation,
    this.platform,
    this.suggestion,
  });

  final IconShiftErrorCode code;
  final String message;

  /// The operation that failed, if known.
  final IconShiftOperation? operation;

  /// The platform the app runs on, if known.
  final IconShiftPlatform? platform;

  /// How to fix it, if IconShift knows.
  final String? suggestion;

  @override
  String toString() {
    final where = [?operation?.name, ?platform?.name];
    return '$runtimeType(${code.name}${where.isEmpty ? '' : ', ${where.join(' on ')}'}): '
        '$message${suggestion == null ? '' : ' Suggestion: $suggestion'}';
  }
}

/// Thrown when IconShift is used before [IconShift.initialize] completed.
class NotInitializedException extends IconShiftException {
  const NotInitializedException({super.operation})
    : super(
        IconShiftErrorCode.notInitialized,
        'IconShift is not initialized.',
        suggestion:
            'Await IconShift.initialize(config) before calling other '
            'IconShift methods.',
      );
}

/// Thrown when a variant id is not in the configuration.
class VariantNotFoundException extends IconShiftException {
  VariantNotFoundException(
    this.variantId,
    this.availableVariants, {
    super.operation,
    super.platform,
  }) : super(
         IconShiftErrorCode.variantNotFound,
         'Unknown variant "$variantId". Configured variants: '
         '${availableVariants.join(', ')}.',
         suggestion:
             'Use one of the configured ids, or add "$variantId" to '
             'IconShiftConfig.variants (and regenerate native resources).',
       );

  final String variantId;
  final List<String> availableVariants;
}

/// Thrown by [IconShift.initialize] when the configuration has errors.
class InvalidConfigurationException extends IconShiftException {
  InvalidConfigurationException(this.validation, {super.platform})
    : super(
        IconShiftErrorCode.invalidConfiguration,
        'Invalid IconShift configuration:\n'
        '${validation.errors.map((e) => '  - $e').join('\n')}',
        operation: IconShiftOperation.initialize,
        suggestion:
            'Fix the listed errors; IconShift.validateConfiguration() '
            'and `icon_shift_cli validate` report the same checks.',
      );

  final IconShiftValidationResult validation;
}

/// Thrown when an argument such as a display name is invalid.
class InvalidArgumentException extends IconShiftException {
  const InvalidArgumentException(
    String message, {
    super.operation,
    super.platform,
    super.suggestion,
  }) : super(IconShiftErrorCode.invalidArgument, message);
}

/// Thrown by [IconShiftResult.throwIfFailed] when an update was not fully
/// applied.
class IdentityUpdateException extends IconShiftException {
  IdentityUpdateException(this.result)
    : super(
        result.icon.didChange || result.displayName.didChange
            ? IconShiftErrorCode.partialUpdate
            : (result.icon.errorCode ??
                  result.displayName.errorCode ??
                  IconShiftErrorCode.nativeOperationFailed),
        'Identity update not fully applied: $result',
        operation: result.operation,
        platform: result.platform,
        suggestion: result.icon.suggestion ?? result.displayName.suggestion,
      );

  final IconShiftResult result;
}
