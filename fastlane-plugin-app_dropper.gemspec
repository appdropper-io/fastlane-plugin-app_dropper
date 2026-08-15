lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'fastlane/plugin/app_dropper/version'

Gem::Specification.new do |spec|
  spec.name = 'fastlane-plugin-app_dropper'
  spec.version = Fastlane::AppDropper::VERSION
  spec.author = 'App Dropper'
  spec.email = 'support@appdropper.io'

  spec.summary = 'Upload .apk and .ipa builds to App Dropper and get a shareable install link'
  spec.description = 'A fastlane action that sends the build your lane just produced to App Dropper, ' \
                     'then returns a public install link and QR code for your testers.'
  spec.homepage = 'https://appdropper.io/help/fastlane-plugin'
  spec.license = 'MIT'
  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'documentation_uri' => 'https://appdropper.io/help/fastlane-plugin',
    'source_code_uri' => 'https://github.com/appdropper-io/fastlane-plugin-app_dropper',
    'bug_tracker_uri' => 'https://appdropper.io/contact'
  }

  spec.files = Dir['lib/**/*'] + %w[README.md LICENSE]
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 2.6'

  # Deliberately no runtime dependencies: the action talks to the API with
  # Ruby's standard library, so adding this plugin can't drag a conflicting
  # HTTP gem into someone's Gemfile.lock.

  spec.add_development_dependency('bundler', '~> 2.0')
  spec.add_development_dependency('fastlane', '>= 2.170.0')
  spec.add_development_dependency('rake', '~> 13.0')
  spec.add_development_dependency('rspec', '~> 3.10')
  spec.add_development_dependency('rubocop', '~> 1.12.1')
end
