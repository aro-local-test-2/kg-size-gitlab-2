# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::RateLimit::RequestClassification, feature_category: :rate_limiting do
  using RSpec::Parameterized::TableSyntax

  let(:request_class) do
    Class.new(::Rack::Request) do
      include ::Gitlab::RateLimit::RequestClassification
    end
  end

  let(:path) { '/' }
  let(:env) { {} }
  let(:request) do
    request_class.new(
      env.reverse_merge(
        'REQUEST_METHOD' => 'GET',
        'PATH_INFO' => path,
        'rack.input' => StringIO.new
      )
    )
  end

  describe '#api_request?' do
    subject { request.api_request? }

    where(:path, :expected) do
      '/-/cloud_connector/keys'       | true
      '/-/cloud_connector/keys_extra' | false
      '/-/cloud_connector/other'      | false
    end

    with_them do
      it { is_expected.to eq(expected) }
    end
  end

  describe '#geo_proxy_workhorse_request?' do
    subject { request.geo_proxy_workhorse_request? }

    let(:path) { '/api/v4/geo/proxy' }

    context 'with a valid Workhorse JWT' do
      let(:env) do
        { 'HTTP_GITLAB_WORKHORSE_API_REQUEST' =>
          JWT.encode({ 'iss' => 'gitlab-workhorse', 'iat' => Time.now.to_i },
            ::Gitlab::Workhorse.secret, 'HS256') }
      end

      it { is_expected.to be(true) }
    end

    context 'with no JWT header', :verify_workhorse_jwt do
      it { is_expected.to be(false) }
    end

    context 'with an invalid JWT', :verify_workhorse_jwt do
      let(:env) { { 'HTTP_GITLAB_WORKHORSE_API_REQUEST' => 'invalid-token' } }

      it 'rescues the JWT::DecodeError raised by verify_api_request!' do
        headers = ::ActionDispatch::Http::Headers.new(request)

        expect { ::Gitlab::Workhorse.verify_api_request!(headers) }.to raise_error(JWT::DecodeError)
        is_expected.to be(false)
      end
    end

    context 'with a JWT signed with the wrong key', :verify_workhorse_jwt do
      let(:env) do
        { 'HTTP_GITLAB_WORKHORSE_API_REQUEST' =>
          JWT.encode({ 'iss' => 'gitlab-workhorse' }, 'wrong-secret', 'HS256') }
      end

      it { is_expected.to be(false) }
    end

    context 'with a JWT with an incorrect issuer', :verify_workhorse_jwt do
      let(:env) do
        { 'HTTP_GITLAB_WORKHORSE_API_REQUEST' =>
          JWT.encode({ 'iss' => 'not-workhorse' }, ::Gitlab::Workhorse.secret, 'HS256') }
      end

      it { is_expected.to be(false) }
    end

    context 'when verify_api_request! raises an unexpected error' do
      let(:env) do
        { 'HTTP_GITLAB_WORKHORSE_API_REQUEST' =>
          JWT.encode({ 'iss' => 'gitlab-workhorse', 'iat' => Time.now.to_i },
            ::Gitlab::Workhorse.secret, 'HS256') }
      end

      before do
        allow(::Gitlab::Workhorse).to receive(:verify_api_request!).and_raise(RuntimeError, 'unexpected')
      end

      it 'does not rescue the error' do
        expect { request.geo_proxy_workhorse_request? }.to raise_error(RuntimeError, 'unexpected')
      end
    end

    context 'when the request is for a different path' do
      let(:path) { '/api/v4/geo/proxy_git_ssh' }
      let(:env) do
        { 'HTTP_GITLAB_WORKHORSE_API_REQUEST' =>
          JWT.encode({ 'iss' => 'gitlab-workhorse', 'iat' => Time.now.to_i },
            ::Gitlab::Workhorse.secret, 'HS256') }
      end

      it 'returns false without verifying the JWT' do
        expect(::Gitlab::Workhorse).not_to receive(:verify_api_request!)

        is_expected.to be(false)
      end
    end
  end

  describe '#geo?' do
    subject { request.geo? }

    where(:env, :geo_auth_attempt, :expected) do
      {}                                   | false | false
      {}                                   | true  | false
      { 'HTTP_AUTHORIZATION' => 'secret' } | false | false
      { 'HTTP_AUTHORIZATION' => 'secret' } | true  | true
    end

    with_them do
      before do
        allow(Gitlab::Geo::JwtRequestDecoder).to receive(:geo_auth_attempt?).and_return(geo_auth_attempt)
      end

      it { is_expected.to be(expected) }
    end
  end

  describe '#verified_geo_request?' do
    subject { request.verified_geo_request? }

    context 'when not a geo request' do
      before do
        allow(request).to receive(:geo?).and_return(false)
      end

      it { is_expected.to be(false) }
    end

    context 'when geo request with valid JWT' do
      let(:env) { { 'HTTP_AUTHORIZATION' => 'GL-Geo valid:token' } }
      let(:decoder) { instance_double(Gitlab::Geo::JwtRequestDecoder) }

      before do
        allow(Gitlab::Geo::JwtRequestDecoder).to receive(:new).and_return(decoder)
        allow(decoder).to receive(:decode).and_return({ data: 'valid' })
      end

      it { is_expected.to be(true) }
    end

    context 'when geo request with invalid JWT' do
      let(:env) { { 'HTTP_AUTHORIZATION' => 'GL-Geo invalid:token' } }
      let(:decoder) { instance_double(Gitlab::Geo::JwtRequestDecoder) }

      before do
        allow(Gitlab::Geo::JwtRequestDecoder).to receive(:new).and_return(decoder)
        allow(decoder).to receive(:decode).and_return(nil)
      end

      it { is_expected.to be(false) }
    end

    context 'when JWT decoding raises an error' do
      let(:env) { { 'HTTP_AUTHORIZATION' => 'GL-Geo malformed' } }
      let(:decoder) { instance_double(Gitlab::Geo::JwtRequestDecoder) }

      before do
        allow(Gitlab::Geo::JwtRequestDecoder).to receive(:new).and_return(decoder)
        allow(decoder).to receive(:decode).and_raise(StandardError)
      end

      it { is_expected.to be(false) }
    end
  end

  describe '#virtual_registries_api_endpoints?' do
    subject { request.virtual_registries_api_endpoints? }

    ::VirtualRegistries::PACKAGE_TYPES.each do |package_type|
      context "for #{package_type}" do
        let(:path) { "/api/v4/virtual_registries/packages/#{package_type}/555/" }

        before do
          allow(request).to receive(:logical_path).and_return(path)
        end

        it { is_expected.to be(true) }
      end
    end

    [
      '/v2/virtual_registries/container/123/',
      '/v2/virtual_registries/container/456/image/manifests/tag',
      '/v2/virtual_registries/container/789/image/blobs/sha256'
    ].each do |path|
      context "for path #{path}" do
        before do
          allow(request).to receive(:logical_path).and_return(path)
        end

        it { is_expected.to be(true) }
      end
    end

    [
      '/api/v4/virtual_registries/packages/invalid/555/',
      '/api/v4/virtual_registries/packages/maven/test/',
      '/api/v4/virtual_registries/containers/registries/123/',
      '/v2/virtual_registries/container',
      '/v2/virtual_registries/container/abc/',
      '/virtual_registries/container/123/'
    ].each do |path|
      context "for path #{path}" do
        before do
          allow(request).to receive(:logical_path).and_return(path)
        end

        it { is_expected.to be(false) }
      end
    end
  end
end
