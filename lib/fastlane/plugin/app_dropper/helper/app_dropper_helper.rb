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
        post('/uploads', {
          file_name: file_name,
          file_size: file_size,
          release_notes: release_notes.to_s,
          tag: tag.to_s
        })
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
