$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'simplecov' if ENV['COVERAGE']
require 'fastlane'
require 'fastlane/plugin/app_dropper'

# fastlane's own spec helper wires up the action collector and UI stubs that
# every plugin's tests expect to be in place.
require 'fastlane/boolean'

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
