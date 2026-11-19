#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_amap_map.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_amap_map'
  s.version          = '0.0.1'
  s.summary          = 'Native AMap maps, overlays and search for Flutter.'
  s.homepage         = "https://pub.dev/packages/#{s.name}"
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = 'flutter_amap_map contributors'
  s.source           = { :path => '.' }
  s.source_files = 'flutter_amap_map/Sources/flutter_amap_map/**/*'
  s.static_framework = true
  s.dependency 'Flutter'
  s.dependency 'AMap3DMap', '11.3.100'
  s.dependency 'AMapFoundation', '1.9.1'
  s.dependency 'AMapSearch', '9.8.1'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'flutter_amap_map_privacy' => ['flutter_amap_map/Sources/flutter_amap_map/PrivacyInfo.xcprivacy']}
end
