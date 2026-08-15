require 'fastlane/action'
require_relative '../helper/app_dropper_helper'

module Fastlane
  module Actions
    module SharedValues
      APP_DROPPER_INSTALL_URL = :APP_DROPPER_INSTALL_URL
      APP_DROPPER_BUILD_ID = :APP_DROPPER_BUILD_ID
      APP_DROPPER_QR_URL = :APP_DROPPER_QR_URL
      APP_DROPPER_VERSION = :APP_DROPPER_VERSION
    end

    class AppDropperAction < Action
      def self.run(params)
        path = File.expand_path(params[:file])
        UI.user_error!("App Dropper: no such file — #{path}") unless File.exist?(path)

        extension = File.extname(path).downcase
        unless ['.apk', '.ipa'].include?(extension)
          UI.user_error!("App Dropper: only .apk and .ipa builds can be uploaded (got '#{extension}').")
        end

        file_name = File.basename(path)
        file_size = File.size(path)
        helper = Helper::AppDropperHelper.new(
          api_token: params[:api_token],
          api_url: params[:api_url]
        )

        UI.message("Uploading #{file_name} (#{format_size(file_size)}) to App Dropper…")

        ticket = helper.create_upload(
          file_name: file_name,
          file_size: file_size,
          release_notes: params[:release_notes],
          tag: params[:tag]
        )

        helper.send_binary(ticket['upload_url'], path, ticket['content_type'])
        UI.message("Upload finished — waiting for App Dropper to process the build…")

        result = helper.await_upload(ticket['upload_id'], timeout: params[:timeout])

        if result['status'] == 'error'
          UI.user_error!("App Dropper: #{result.dig('error', 'message') || 'the build could not be processed.'}")
        end
        unless result['status'] == 'ready'
          UI.user_error!("App Dropper: the build is still processing after #{params[:timeout]}s. Nothing was lost — check your dashboard.")
        end

        install_url = result['install_url']
        Actions.lane_context[SharedValues::APP_DROPPER_INSTALL_URL] = install_url
        Actions.lane_context[SharedValues::APP_DROPPER_BUILD_ID] = result['build_id']
        Actions.lane_context[SharedValues::APP_DROPPER_QR_URL] = result['qr_url']
        Actions.lane_context[SharedValues::APP_DROPPER_VERSION] = result['version']

        UI.success("#{result['app_name']} #{result['version']} is live: #{install_url}")
        install_url
      end

      def self.format_size(bytes)
        bytes >= 1024 * 1024 ? "#{(bytes / 1024.0 / 1024.0).round(1)} MB" : "#{(bytes / 1024.0).round} KB"
      end

      def self.description
        "Upload an .apk or .ipa to App Dropper and get a shareable install link"
      end

      def self.details
        [
          "Sends a build to App Dropper and returns its public install link.",
          "",
          "The binary goes straight to storage on a resumable session rather than",
          "through the API, so build size is bounded only by your plan.",
          "",
          "Generate a token under Settings → API tokens in your App Dropper",
          "dashboard. Each token is scoped to one app and can only upload builds."
        ].join("\n")
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :api_token,
            env_name: "APPDROPPER_TOKEN",
            description: "Your App Dropper API token",
            sensitive: true,
            verify_block: proc do |value|
              UI.user_error!("No API token — set APPDROPPER_TOKEN or pass api_token:") if value.to_s.empty?
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :file,
            env_name: "APPDROPPER_FILE",
            description: "Path to the .apk or .ipa to upload",
            # Whichever of the two the lane just produced. Both are set by the
            # standard build actions, so the common case needs no `file:` at all.
            default_value: Actions.lane_context[SharedValues::IPA_OUTPUT_PATH] ||
                           Actions.lane_context[SharedValues::GRADLE_APK_OUTPUT_PATH],
            default_value_dynamic: true,
            verify_block: proc do |value|
              UI.user_error!("Couldn't find a build to upload — pass file:") if value.to_s.empty?
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :release_notes,
            env_name: "APPDROPPER_RELEASE_NOTES",
            description: "Release notes shown to testers on the install page",
            optional: true,
            default_value: ""
          ),
          FastlaneCore::ConfigItem.new(
            key: :tag,
            env_name: "APPDROPPER_TAG",
            description: "Label for this build, e.g. 'beta' or 'nightly'",
            optional: true,
            default_value: ""
          ),
          FastlaneCore::ConfigItem.new(
            key: :timeout,
            env_name: "APPDROPPER_TIMEOUT",
            description: "Seconds to wait for the build to finish processing",
            optional: true,
            type: Integer,
            default_value: Helper::AppDropperHelper::DEFAULT_TIMEOUT
          ),
          FastlaneCore::ConfigItem.new(
            key: :api_url,
            env_name: "APPDROPPER_API_URL",
            description: "API base URL — only needed for a self-hosted deployment",
            optional: true
          )
        ]
      end

      def self.output
        [
          ['APP_DROPPER_INSTALL_URL', 'Public install link for the uploaded build'],
          ['APP_DROPPER_BUILD_ID', 'Identifier of the build that was created'],
          ['APP_DROPPER_QR_URL', 'PNG QR code pointing at the install link'],
          ['APP_DROPPER_VERSION', 'Version string parsed out of the binary']
        ]
      end

      def self.return_value
        "The public install link"
      end

      def self.authors
        ["App Dropper"]
      end

      def self.is_supported?(platform)
        [:ios, :android].include?(platform)
      end

      def self.example_code
        [
          'app_dropper(
            api_token: ENV["APPDROPPER_TOKEN"],
            file: lane_context[SharedValues::IPA_OUTPUT_PATH]
          )',
          '# Android, with the last commit message as release notes
          app_dropper(
            file: lane_context[SharedValues::GRADLE_APK_OUTPUT_PATH],
            release_notes: last_git_commit[:message],
            tag: "nightly"
          )',
          '# The install link is both the return value and a lane_context entry
          url = app_dropper
          slack(message: "New build ready: #{url}")'
        ]
      end

      def self.category
        :beta
      end
    end
  end
end
