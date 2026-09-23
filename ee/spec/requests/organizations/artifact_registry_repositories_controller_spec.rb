# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Organizations::ArtifactRegistryRepositoriesController', :use_clean_rails_memory_store_caching, feature_category: :artifact_registry do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:member) { create(:user) }
  let_it_be(:non_member) { create(:user) }
  let_it_be(:mapping) do
    create(:artifact_registry_namespace_mapping, organization: organization)
  end

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:service_token) { 'ar-service-credential-value' }
  let(:resolved_slug) { 'acme' }
  let(:slug) { resolved_slug }
  let(:namespace_uuid) { mapping.ar_namespace_id }
  let(:namespace_url) { "#{base_url}/api/gitlab/v1/namespaces/#{namespace_uuid}" }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:repositories_base_path) { "/o/#{organization.path}/-/artifact_registry/#{slug}/repositories" }

  let(:namespace_body) do
    {
      'id' => namespace_uuid,
      'slug' => resolved_slug,
      'platform' => 'gitlab',
      'status' => 'active',
      'created_at' => '2026-07-01T10:00:00Z'
    }
  end

  # The mount anchors the SPA router to the base path built from the resolved
  # slug, not the request path, so the app data is identical on the top route
  # and any catch-all sub-path.
  let(:expected_app_data) do
    {
      'organization_gid' => organization.to_global_id.to_s,
      'slug' => resolved_slug,
      'base_path' => "/o/#{organization.path}/-/artifact_registry/#{resolved_slug}/repositories",
      'client_base_url' => base_url
    }
  end

  before_all do
    create(:organization_user, organization: organization, user: member)
  end

  before do
    stub_config(artifact_registry: { api_url: base_url })
    allow_next_instance_of(ArtifactRegistry::ServiceCredential) do |credential|
      allow(credential).to receive(:token).and_return(service_token)
    end
  end

  subject(:perform_request) { get path }

  def stub_namespace(status:, body: namespace_body.to_json)
    stub_request(:get, namespace_url).to_return(status: status, headers: json_headers, body: body)
  end

  def mount_element
    Nokogiri::HTML.parse(response.body).at_css('#js-artifact-registry-repositories')
  end

  shared_examples 'a hidden repositories mount' do
    it 'returns not found and does not render the mount', :aggregate_failures do
      perform_request

      expect(response).to have_gitlab_http_status(:not_found)
      expect(mount_element).to be_nil
    end
  end

  shared_examples 'the gated repositories route' do
    context 'when the feature flag is enabled and the user can read the registry' do
      before do
        sign_in(member)
      end

      context 'when the requested slug matches the resolved slug' do
        it 'serves the repositories mount from a single AR call', :aggregate_failures do
          request = stub_namespace(status: 200)

          perform_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(request).to have_been_requested.once
          expect(mount_element).to be_present
          expect(Gitlab::Json::SafeParser.parse(mount_element['data-app-data'])).to eq(expected_app_data)
        end

        # A non-'acme' resolved slug, so the route is proven to serve on the
        # resolved slug rather than passing only because it matches the stub. The
        # GraphQL surface still addresses the stub until #602638.
        context 'and the resolved slug is not the stub slug' do
          let(:resolved_slug) { 'real-namespace' }

          it 'serves the mount for the resolved slug', :aggregate_failures do
            stub_namespace(status: 200)

            perform_request

            expect(response).to have_gitlab_http_status(:ok)
            expect(mount_element).to be_present
            expect(Gitlab::Json::SafeParser.parse(mount_element['data-app-data']))
              .to include('slug' => 'real-namespace')
          end
        end
      end

      context 'when the requested slug does not match the resolved slug' do
        let(:slug) { "not-#{resolved_slug}" }

        before do
          stub_namespace(status: 200)
        end

        it_behaves_like 'a hidden repositories mount'
      end

      context 'when resolution fails with a client error' do
        before do
          stub_namespace(status: 503, body: {}.to_json)
        end

        it 'serves the mount rather than the instance-wide 503', :aggregate_failures do
          perform_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(mount_element).to be_present
          expect(Gitlab::Json::SafeParser.parse(mount_element['data-app-data'])).to eq(expected_app_data)
        end

        context 'and the requested slug is not the one that would resolve' do
          let(:slug) { 'other-namespace' }

          it 'anchors the mount on the requested slug', :aggregate_failures do
            perform_request

            expect(response).to have_gitlab_http_status(:ok)
            expect(Gitlab::Json::SafeParser.parse(mount_element['data-app-data'])).to include(
              'slug' => 'other-namespace',
              'base_path' => "/o/#{organization.path}/-/artifact_registry/other-namespace/repositories"
            )
          end
        end

        context 'and the requested slug is not well formed' do
          let(:slug) { 'Not_A_Slug' }

          it_behaves_like 'a hidden repositories mount'
        end
      end

      context 'when the namespace is absent (AR 404)' do
        it 'answers not-found rather than service-unavailable' do
          stub_namespace(status: 404, body: {}.to_json)

          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when the organization has no mapping row' do
        let_it_be(:organization) { create(:organization) }
        let_it_be(:member) { create(:organization_user, organization: organization).user }

        it 'returns not found and makes no AR call', :aggregate_failures do
          request = stub_request(:get, %r{/api/gitlab/v1/namespaces/})

          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(request).not_to have_been_requested
        end
      end

      context 'when the artifact_registry_ui feature flag is disabled' do
        before do
          stub_feature_flags(artifact_registry_ui: false)
        end

        it 'returns not found and makes no AR call', :aggregate_failures do
          request = stub_request(:get, namespace_url)

          perform_request

          expect(response).to have_gitlab_http_status(:not_found)
          expect(request).not_to have_been_requested
        end
      end

      it_behaves_like 'a surface gated on a configured Artifact Registry base URL', 'a hidden repositories mount'

      context 'when the org_pages release flag is disabled' do
        before do
          stub_organization_release(org_pages: false)
        end

        it_behaves_like 'a hidden repositories mount'
      end
    end

    context 'when the user cannot read the registry' do
      before do
        sign_in(non_member)
      end

      it 'returns not found and makes no AR call', :aggregate_failures do
        request = stub_request(:get, namespace_url)

        perform_request

        expect(response).to have_gitlab_http_status(:not_found)
        expect(request).not_to have_been_requested
      end
    end

    context 'when the user is not signed in' do
      it 'redirects to the sign in page' do
        perform_request

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET #index' do
    it 'declares the artifact_registry feature category' do
      expect(Organizations::ArtifactRegistryRepositoriesController.feature_category_for_action(:index))
        .to eq(:artifact_registry)
    end

    context 'on the repositories base path' do
      let(:path) { repositories_base_path }

      it_behaves_like 'the gated repositories route'
    end

    context 'on a deep catch-all sub-path (hard reload or direct deep link)' do
      let(:path) { "#{repositories_base_path}/some/deep/link" }

      it_behaves_like 'the gated repositories route'
    end
  end

  describe 'slug enumeration' do
    let(:path) { repositories_base_path }
    let(:slug) { "not-#{resolved_slug}" }

    # The per-request CSP nonce is not part of what could enumerate, so it is
    # normalized out; status and body are both returned so each response is
    # confirmed a 404 before the bodies are compared.
    def not_found_response
      get path
      { status: response.status, body: response.body.gsub(/nonce="[^"]+"/, 'nonce="NONCE"') }
    end

    it 'returns byte-identical not-found for an unknown slug and one the viewer may not see', :aggregate_failures do
      request = stub_namespace(status: 200)

      # Non-member first, before any resolution warms the shared cache: the gate
      # stops it with no AR call, so dropping the gate would fail here.
      sign_in(non_member)
      non_member_response = not_found_response
      expect(request).not_to have_been_requested

      # The member passes the gate and resolves, then hits the slug-mismatch 404.
      sign_in(member)
      member_response = not_found_response
      expect(request).to have_been_requested.once

      expect(non_member_response[:status]).to eq(404)
      expect(member_response[:status]).to eq(404)
      expect(member_response[:body]).to eq(non_member_response[:body])
    end
  end
end
