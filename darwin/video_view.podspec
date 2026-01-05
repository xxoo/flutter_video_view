#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint video_view.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'video_view'
  s.version          = '1.2.6'
  s.summary          = 'A lightweight media player for Flutter.'
  s.description      = <<-DESC
A lightweight media player with subtitle rendering and audio track switching support, leveraging system or app-level components for seamless playback.
                       DESC
  s.homepage         = 'http://github.com/xxoo/video_view'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Xiao Shen' => 'http://github.com/xxoo' }

  s.source           = { :path => '.' }
  s.source_files     = 'video_view/Sources/video_view/**/*.swift'
  s.swift_version    = '5.0'

  s.ios.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.osx.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }

  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'

  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
end
