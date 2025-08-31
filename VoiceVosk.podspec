require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "VoiceVosk"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.description  = <<-DESC
                  React Native library for offline speech recognition using Vosk
                   DESC
  s.homepage     = "https://github.com/deepanshucse/react-native-voice-vosk"
  s.license      = "MIT"
  s.authors      = package["author"]

  s.platforms    = { :ios => "11.0" }
  s.source       = { :git => "https://github.com/deepanshucse/react-native-voice-vosk.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,swift}"

  s.dependency "React-Core"
  s.dependency "React-RCTTurboModule"
  
  # Add Vosk dependency
  s.vendored_frameworks = "ios/Frameworks/vosk.framework"
  
  # Compiler flags
  s.compiler_flags = '-DFOLLY_NO_CONFIG -DFOLLY_MOBILE=1 -DFOLLY_USE_LIBCPP=1'
  s.xcconfig = {
    'HEADER_SEARCH_PATHS' => '"$(PODS_ROOT)/vosk-ios/include"',
    'LIBRARY_SEARCH_PATHS' => '"$(PODS_ROOT)/vosk-ios/lib"'
  }
  
  # Language standard
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17'
  }
end