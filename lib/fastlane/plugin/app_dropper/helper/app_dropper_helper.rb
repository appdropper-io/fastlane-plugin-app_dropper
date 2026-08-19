require 'fastlane_core/ui/ui'
require 'net/http'
require 'json'
require 'uri'

module Fastlane
  UI = FastlaneCore::UI unless Fastlane.const_defined?(:UI)

  module Helper
    # Talks to the App Dropper REST API over Ruby's standard library only.
    #
    # Binaries never pass through the API: `create_upload` returns a Google
    # Cloud Storage resumable session, `send_binary` streams the file straight
    # there, and `await_upload` waits for the server to parse it. That is what
    # keeps a 500 MB .ipa clear of the request-size ceilings every HTTP API has.
    class AppDropperHelper
      DEFAULT_API_URL = "https://appdropper.io/api/v1".freeze
      # Matches the CLI: long enough for a large build to be parsed, short
      # enough that a wedged lane eventually fails instead of hanging a CI job.
      DEFAULT_TIMEOUT = 600

      def initialize(api_token:, api_url: nil)
        @api_token = api_token
        @api_url = (api_url || ENV['APPDROPPER_API_URL'] || DEFAULT_API_URL).chomp('/')
      end

      def create_upload(file_name:, file_size:, release_notes:, tag:)
        body = {
          file_name: file_name,
          file_size: file_size,
          release_notes: release_notes.to_s,
          tag: tag.to_s
        }
        ci = self.class.ci_info
        body[:ci] = ci unless ci.empty?
        post('/uploads', body)
      end

      # Which pipeline this lane is running in, read off the runner's
      # environment. App Dropper quotes it back in the "a new version is
      # available" email its testers and managers get, so they can see the
      # branch and commit the build in their hands came from. Empty on a
      # developer's machine, and suppressed entirely by APPDROPPER_NO_CI_INFO.
      def self.ci_info
        return {} if present(ENV['APPDROPPER_NO_CI_INFO'])

        info =
          if present(ENV['GITHUB_ACTIONS'])
            repo = ENV['GITHUB_REPOSITORY']
            run = ENV['GITHUB_RUN_ID']
            server = present(ENV['GITHUB_SERVER_URL']) || 'https://github.com'
            {
              provider: 'GitHub Actions',
              repo: repo,
              branch: branch_name(ENV['GITHUB_HEAD_REF'] || ENV['GITHUB_REF_NAME'] || ENV['GITHUB_REF']),
              commit: ENV['GITHUB_SHA'],
              actor: ENV['GITHUB_ACTOR'],
              run_url: repo && run ? "#{server}/#{repo}/actions/runs/#{run}" : nil
            }
          elsif present(ENV['GITLAB_CI'])
            {
              provider: 'GitLab CI',
              repo: ENV['CI_PROJECT_PATH'],
              branch: ENV['CI_COMMIT_BRANCH'] || ENV['CI_COMMIT_REF_NAME'],
              commit: ENV['CI_COMMIT_SHA'],
              actor: ENV['GITLAB_USER_LOGIN'],
              run_url: ENV['CI_JOB_URL'] || ENV['CI_PIPELINE_URL']
            }
          elsif present(ENV['BITRISE_IO'])
            {
              provider: 'Bitrise',
              repo: repo_slug(ENV['GIT_REPOSITORY_URL']) || ENV['BITRISE_APP_TITLE'],
              branch: ENV['BITRISE_GIT_BRANCH'],
              commit: ENV['BITRISE_GIT_COMMIT'],
              run_url: ENV['BITRISE_BUILD_URL']
            }
          elsif present(ENV['CIRCLECI'])
            owner = ENV['CIRCLE_PROJECT_USERNAME']
            name = ENV['CIRCLE_PROJECT_REPONAME']
            {
              provider: 'CircleCI',
              repo: owner && name ? "#{owner}/#{name}" : name,
              branch: ENV['CIRCLE_BRANCH'],
              commit: ENV['CIRCLE_SHA1'],
              actor: ENV['CIRCLE_USERNAME'],
              run_url: ENV['CIRCLE_BUILD_URL']
            }
          elsif present(ENV['BITBUCKET_BUILD_NUMBER'])
            repo = ENV['BITBUCKET_REPO_FULL_NAME']
            build = ENV['BITBUCKET_BUILD_NUMBER']
            {
              provider: 'Bitbucket Pipelines',
              repo: repo,
              branch: ENV['BITBUCKET_BRANCH'],
              commit: ENV['BITBUCKET_COMMIT'],
              run_url: repo && build ? "https://bitbucket.org/#{repo}/pipelines/results/#{build}" : nil
            }
          elsif present(ENV['CM_BUILD_ID'])
            {
              provider: 'Codemagic',
              repo: ENV['CM_REPO_SLUG'] || ENV['FCI_REPO_SLUG'],
              branch: ENV['CM_BRANCH'] || ENV['FCI_BRANCH'],
              commit: ENV['CM_COMMIT'] || ENV['FCI_COMMIT'],
              run_url: ENV['CM_BUILD_URL'] || ENV['FCI_BUILD_URL']
            }
          elsif present(ENV['JENKINS_URL'])
            {
              provider: 'Jenkins',
              repo: repo_slug(ENV['GIT_URL']) || ENV['JOB_NAME'],
              branch: branch_name(ENV['BRANCH_NAME'] || ENV['GIT_BRANCH']),
              commit: ENV['GIT_COMMIT'],
              run_url: ENV['BUILD_URL']
            }
          elsif present(ENV['CI'])
            { provider: 'CI' }
          else
            {}
          end

        info.reject { |_k, v| present(v).nil? }
      end

      def self.present(value)
        return nil if value.nil?

        stripped = value.to_s.strip
        stripped.empty? ? nil : stripped
      end

      # "refs/heads/main" -> "main", and Jenkins' "origin/main" -> "main".
      def self.branch_name(ref)
        present(ref)&.sub(%r{\Arefs/(heads|tags)/}, '')&.sub(%r{\Aorigin/}, '')
      end

      # "git@github.com:acme/app.git" -> "acme/app"
      def self.repo_slug(url)
        match = present(url)&.match(%r{[:/]([^/:]+/[^/]+?)(?:\.git)?/?\z})
        match && match[1]
      end

      # A single PUT of the whole file. Net::HTTP streams from the IO rather
      # than reading the build into memory, which matters when the build is
      # bigger than the runner's RAM budget.
      def send_binary(session_url, path, content_type)
        uri = URI.parse(session_url)
        size = File.size(path)

        File.open(path, 'rb') do |io|
          request = Net::HTTP::Put.new(uri)
          request['Content-Type'] = content_type
          request['Content-Length'] = size.to_s
          request.body_stream = io

          response = http_for(uri, read_timeout: 900).request(request)
          unless response.is_a?(Net::HTTPSuccess)
            UI.user_error!("App Dropper: storage rejected the upload (HTTP #{response.code}). #{response.body.to_s[0, 300]}")
          end
        end
      end

      # Long-polls the upload until it is parsed. The server holds the
      # connection for `wait` seconds, so this is normally one request.
      def await_upload(upload_id, timeout: DEFAULT_TIMEOUT)
        deadline = Time.now + timeout
        loop do
          remaining = (deadline - Time.now).to_i
          wait = [[remaining, 120].min, 0].max
          result = get("/uploads/#{upload_id}?wait=#{wait}")
          status = result['status']
          return result if status == 'ready' || status == 'error'
          return result if Time.now >= deadline
        end
      end

      def whoami
        get('/me')
      end

      private

      def http_for(uri, read_timeout: 60)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 30
        http.read_timeout = read_timeout
        http
      end

      def get(path)
        uri = URI.parse("#{@api_url}#{path}")
        request = Net::HTTP::Get.new(uri)
        apply_headers(request)
        # Generously past the server's own hold, so the client isn't what gives
        # up on a request the server is still honouring.
        parse(http_for(uri, read_timeout: 180).request(request))
      end

      def post(path, body)
        uri = URI.parse("#{@api_url}#{path}")
        request = Net::HTTP::Post.new(uri)
        apply_headers(request)
        request['Content-Type'] = 'application/json'
        request.body = body.to_json
        parse(http_for(uri).request(request))
      end

      def apply_headers(request)
        request['Authorization'] = "Bearer #{@api_token}"
        request['Accept'] = 'application/json'
        request['User-Agent'] = "fastlane-plugin-app_dropper/#{Fastlane::AppDropper::VERSION}"
      end

      def parse(response)
        parsed = begin
          response.body.to_s.empty? ? {} : JSON.parse(response.body)
        rescue JSON::ParserError
          {}
        end

        return parsed if response.is_a?(Net::HTTPSuccess)

        message = parsed.dig('error', 'message') || "HTTP #{response.code}"
        # The API answers 401/403 for a token problem; naming it here saves the
        # usual round of "is the secret even set?" debugging.
        case response.code.to_i
        when 401, 403
          UI.user_error!("App Dropper: #{message} Check that APPDROPPER_TOKEN is set and scoped to this app.")
        when 402
          UI.user_error!("App Dropper: #{message}")
        when 429
          UI.user_error!("App Dropper: #{message}")
        else
          UI.user_error!("App Dropper: #{message}")
        end
      end
    end
  end
end
