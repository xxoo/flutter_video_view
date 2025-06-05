#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint video_view.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'video_view'
  s.version          = '1.0.5'
  s.summary          = 'A lightweight media player for Flutter.'
  s.description      = <<-DESC
A lightweight media player with subtitle rendering and audio track switching support, leveraging system or app-level components for seamless playback.
                       DESC
  s.homepage         = 'http://github.com/xxoo/video_view'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'xxoo' => 'http://github.com/xxoo' }

  s.source           = { :path => '.' }
  s.source_files     = 'video_view/Sources/video_view/**/*.swift'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
