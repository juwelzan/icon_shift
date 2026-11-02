#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint icon_shift.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'icon_shift'
  s.version          = '0.2.0'
  s.summary          = 'Runtime app icon and display name switching for Flutter.'
  s.description      = <<-DESC
Switches the app icon (and, where the OS allows, the display name) at runtime.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  s.source           = { :path => '.' }
  s.source_files = 'icon_shift/Sources/icon_shift/**/*'

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'icon_shift_privacy' => ['icon_shift/Sources/icon_shift/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
