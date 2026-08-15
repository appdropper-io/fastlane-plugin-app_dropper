require 'spec_helper'

describe Fastlane::Actions::AppDropperAction do
  describe 'the action itself' do
    it 'is registered under the beta category' do
      expect(described_class.category).to eq(:beta)
    end

    it 'supports both mobile platforms' do
      expect(described_class.is_supported?(:ios)).to be(true)
      expect(described_class.is_supported?(:android)).to be(true)
      expect(described_class.is_supported?(:mac)).to be(false)
    end

    it 'marks the API token as sensitive so it is redacted from logs' do
      token = described_class.available_options.find { |o| o.key == :api_token }
      expect(token.sensitive).to be(true)
    end
  end

  describe 'input validation' do
    it 'refuses a file that does not exist' do
      expect do
        described_class.run(file: '/definitely/not/here.ipa', api_token: 'adp_a_b')
      end.to raise_error(FastlaneCore::Interface::FastlaneError, /no such file/i)
    end

    it 'refuses anything that is not an .apk or .ipa' do
      Tempfile.create(['build', '.zip']) do |file|
        expect do
          described_class.run(file: file.path, api_token: 'adp_a_b')
        end.to raise_error(FastlaneCore::Interface::FastlaneError, /only \.apk and \.ipa/i)
      end
    end
  end
end
