import 'models/result.dart';
import 'models/validation.dart';

/// Machine-readable reason attached to exceptions and failed operations.
enum IconShiftErrorCode {
  /// An IconShift method was called before [IconShift.initialize].
  notInitialized,

  /// The variant id is not part of the configuration.
  variantNotFound,

  /// The configuration has validation errors.
  invalidConfiguration,

  /// An argument (e.g. a display name) is invalid.
  invalidArgument,

  /// The platform cannot perform this operation.
  unsupportedOperation,

  /// A native resource the variant needs (activity-alias, alternate icon,
  /// asset) is missing from the build.
  missingNativeResource,

  /// The OS denied the operation.
  permissionDenied,

  /// The operation needs the app in the foreground (iOS).
  appNotActive,

  /// The native call failed; see the message for the OS error.
  nativeOperationFailed,

  /// Some operations of a combined update did not succeed.
  partialUpdate,
}

/// Base class of all exceptions thrown by IconShift.
abstract class IconShiftException implements Exception {
  const IconShiftException(this.code, this.message);

  final IconShiftErrorCode code;
  final String message;

  @override
  String toString() => '$runtimeType(${code.name}): $message';
}

/// Thrown when IconShift is used before [IconShift.initialize] completed.
class NotInitializedException extends IconShiftException {
  const NotInitializedException()
    : super(
        IconShiftErrorCode.notInitialized,
        'IconShift is not initialized. Await IconShift.initialize(config) '
        'before calling other IconShift methods.',
      );
}

/// Thrown when a variant id is not in the configuration.
class VariantNotFoundException extends IconShiftException {
  VariantNotFoundException(this.variantId, this.availableVariants)
    : super(
        IconShiftErrorCode.variantNotFound,
        'Unknown variant "$variantId". Configured variants: '
        '${availableVariants.join(', ')}.',
      );

  final String variantId;
  final List<String> availableVariants;
}

/// Thrown by [IconShift.initialize] when the configuration has errors.
class InvalidConfigurationException extends IconShiftException {
  InvalidConfigurationException(this.validation)
    : super(
        IconShiftErrorCode.invalidConfiguration,
        'Invalid IconShift configuration:\n'
        '${validation.errors.map((e) => '  - $e').join('\n')}',
      );

  final IconShiftValidationResult validation;
}

/// Thrown when an argument such as a display name is invalid.
class InvalidArgumentException extends IconShiftException {
  const InvalidArgumentException(String message)
    : super(IconShiftErrorCode.invalidArgument, message);
}

/// Thrown by [IconShiftResult.throwIfFailed] when an update was not fully
/// applied.
class IdentityUpdateException extends IconShiftException {
  IdentityUpdateException(this.result)
    : super(
        result.icon.isSuccessful || result.displayName.isSuccessful
            ? IconShiftErrorCode.partialUpdate
            : (result.icon.errorCode ??
                  result.displayName.errorCode ??
                  IconShiftErrorCode.nativeOperationFailed),
        'Identity update not fully applied: $result',
      );

  final IconShiftResult result;
}
