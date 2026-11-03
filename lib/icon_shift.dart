/// Switch your app's icon and display name at runtime, across Android, iOS,
/// macOS, Windows, Linux and web, within what each OS allows.
library;

export 'src/branding/branding_controller.dart';
export 'src/branding/branding_provider.dart';
export 'src/branding/branding_profile.dart'
    show BrandingFieldMap, BrandingProfile, hexColor, parseHexColor;
export 'src/config/app_identity.dart';
export 'src/config/icon_shift_config.dart';
export 'src/config/platform.dart';
export 'src/exceptions.dart';
export 'src/icon_shift.dart';
export 'src/models/application_info.dart';
export 'src/models/capabilities.dart';
export 'src/models/diagnostics.dart';
export 'src/models/identity_properties.dart';
export 'src/models/identity_variant.dart';
export 'src/models/preview.dart';
export 'src/models/remote_icon.dart'
    show RemoteIcon, checkRemoteIconUrl, maxRemoteIconBytes;
export 'src/models/result.dart';
export 'src/models/shortcut_identity.dart';
export 'src/models/state.dart';
export 'src/models/validation.dart';
export 'src/theme_sync.dart';
