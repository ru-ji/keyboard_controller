#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint keyboard_controller.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'keyboard_controller'
  s.version          = '0.1.0'
  s.summary          = 'Frame-synced keyboard tracking and interactive dismiss for Flutter.'
  s.description      = <<-DESC
Frame-synced keyboard tracking, keyboard-aware layout and scrolling, and
interactive drag-to-dismiss. A Flutter port of react-native-keyboard-controller.
                       DESC
  s.homepage         = 'https://github.com/kirillzyusko/react-native-keyboard-controller'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'keyboard_controller' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'keyboard_controller/Sources/keyboard_controller/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'keyboard_controller_privacy' => ['keyboard_controller/Sources/keyboard_controller/PrivacyInfo.xcprivacy']}
end
