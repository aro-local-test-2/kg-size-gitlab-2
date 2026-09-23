# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::RackAttack::Request, feature_category: :rate_limiting do
  using RSpec::Parameterized::TableSyntax

  let(:path) { '/' }
  let(:env) { {} }
  let(:request) do
    ::Rack::Attack::Request.new(
      env.reverse_merge(
        'REQUEST_METHOD' => 'GET',
        'PATH_INFO' => path,
        'rack.input' => StringIO.new
      )
    )
  end

  describe '#should_be_skipped?' do
    where(
      super_value: [true, false],
      verified_geo_request: [true, false],
      virtual_registries_api_endpoints: [true, false],
      geo_proxy_workhorse_request: [true, false]
    )

    with_them do
      it 'returns true if any condition is true' do
        allow(request).to receive_messages(
          api_internal_request?: super_value,
          health_check_request?: super_value,
          container_registry_event?: super_value,
          verified_geo_request?: verified_geo_request,
          virtual_registries_api_endpoints?: virtual_registries_api_endpoints,
          geo_proxy_workhorse_request?: geo_proxy_workhorse_request
        )

        expected = super_value || verified_geo_request || virtual_registries_api_endpoints ||
          geo_proxy_workhorse_request
        expect(request.should_be_skipped?).to be(expected)
      end
    end
  end

  describe '#throttle_unauthenticated_git_http?' do
    let_it_be(:project) { create(:project) }

    let(:path) { "/#{project.full_path}.git/info/refs?service=git-upload-pack" }

    subject { request.throttle_unauthenticated_git_http? }

    before do
      stub_application_setting(throttle_unauthenticated_git_http_enabled: true)
    end

    context 'when verified geo request' do
      before do
        allow(request).to receive(:verified_geo_request?).and_return(true)
      end

      it { is_expected.to be(false) }
    end

    context 'when geo header present but JWT is invalid (security test)' do
      let(:env) { { 'HTTP_AUTHORIZATION' => 'GL-Geo fake-token' } }

      before do
        allow(request).to receive_messages(verified_geo_request?: false, unauthenticated?: true)
      end

      it 'still applies rate limiting' do
        is_expected.to be(true)
      end
    end

    context 'when not a geo request and unauthenticated' do
      before do
        allow(request).to receive_messages(verified_geo_request?: false, unauthenticated?: true)
      end

      it { is_expected.to be(true) }
    end

    context 'when not a geo request and authenticated' do
      before do
        allow(request).to receive_messages(verified_geo_request?: false, unauthenticated?: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when throttling is disabled' do
      before do
        stub_application_setting(throttle_unauthenticated_git_http_enabled: false)
        allow(request).to receive_messages(verified_geo_request?: false, unauthenticated?: true)
      end

      it { is_expected.to be(false) }
    end
  end

  describe '#throttle_authenticated_dependency_proxy?' do
    subject { request.throttle_authenticated_dependency_proxy? }

    before do
      stub_application_setting(throttle_authenticated_dependency_proxy_enabled: true)
    end

    context 'for a regular dependency proxy path' do
      let(:path) { '/v2/mygroup/dependency_proxy/containers/alpine/manifests/latest' }

      it { is_expected.to be(true) }
    end

    context 'for a virtual registry container path that also matches the CE regex' do
      let(:path) { '/v2/virtual_registries/container/1/dependency_proxy/containers/img/manifests/latest' }

      it 'is excluded, so the virtual registries throttle claims the request instead' do
        is_expected.to be(false)
      end
    end
  end
end
