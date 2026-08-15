require 'fastlane/plugin/app_dropper/version'

module Fastlane
  module AppDropper
    # Returns all .rb files inside the "actions" and "helper" directory, which
    # is how fastlane discovers what a plugin provides.
    def self.all_classes
      Dir[File.expand_path('**/{actions,helper}/*.rb', File.dirname(__FILE__))]
    end
  end
end

# By default we want to import all available actions and helpers.
Fastlane::AppDropper.all_classes.each do |current|
  require current
end
