# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::ArtifactRegistryController, :use_clean_rails_memory_store_caching,
  feature_category: :artifact_registry do
  let_it_be_with_reload(:organization) { create(:organization) }

  # The test environment configures `api_url` as a bare origin, so the client base URL
  # the view emits is that value unchanged; the derivation itself is covered in
  # ee/spec/helpers/organizations/artifact_registry_helper_spec.rb.
  let(:expected_app_data) do
    {
      'organization_path' => organization.path,
      'client_base_url' => Gitlab.config.artifact_registry['api_url']
    }
  end

  def mount_element
    Nokogiri::HTML.parse(response.body).at_css('#js-artifact-registry-setup')
  end

  shared_examples 'a rendered setup mount' do
    it 'renders the mount with the setup app data', :aggregate_failures do
      gitlab_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(mount_element).to be_present
      expect(Gitlab::Json::SafeParser.parse(mount_element['data-app-data'])).to eq(expected_app_data)
    end
  end

  shared_examples 'a hidden setup mount' do
    it 'returns not found and does not render the mount', :aggregate_failures do
      gitlab_request

      expect(response).to have_gitlab_http_status(:not_found)
      expect(mount_element).to be_nil
    end
  end

  shared_examples 'the unavailable page' do
    it 'renders the unavailable page rather than the instance-wide 503', :aggregate_failures do
      gitlab_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to include(s_('ArtifactRegistry|Artifact registry is unavailable'))
      expect(mount_element).to be_nil
    end
  end

  it 'declares the artifact_registry feature category for #index' do
    expect(described_class.feature_category_for_action('index')).to eq(:artifact_registry)
  end

  describe 'GET #index' do
    subject(:gitlab_request) { get artifact_registry_organization_index_path(organization) }

    context 'when the user is not signed in' do
      it_behaves_like 'organization - redirects to sign in page'

      context 'when the org_pages release flag is disabled' do
        before do
          stub_organization_release(org_pages: false)
        end

        it_behaves_like 'organization - redirects to sign in page'
      end
    end

    context 'when the user is signed in' do
      let_it_be(:user) { create(:user) }

      before do
        sign_in(user)
      end

      context 'with no association to the organization' do
        it_behaves_like 'a hidden setup mount'
        it_behaves_like 'organization - action disabled by org_pages release flag'
      end

      context 'as an admin', :enable_admin_mode do
        let_it_be(:user) { create(:admin) }

        it_behaves_like 'organization - successful response'
        it_behaves_like 'organization - action disabled by org_pages release flag'

        it_behaves_like 'a rendered setup mount'
      end

      context 'as a default organization user' do
        before_all do
          create(:organization_user, organization: organization, user: user)
        end

        # The flag-off case is not repeated here. A member is refused on every path - flag on
        # by the update-ability check, flag off by the gating concern - so a nested flag-off
        # context could not fail. The owner context below is where the flag is observable.
        it_behaves_like 'a hidden setup mount'
        it_behaves_like 'organization - action disabled by org_pages release flag'
      end

      context 'as an owner of an organization' do
        before_all do
          create(:organization_user, :owner, organization: organization, user: user)
        end

        it_behaves_like 'organization - successful response'
        it_behaves_like 'organization - action disabled by org_pages release flag'

        it_behaves_like 'a rendered setup mount'

        context 'when the `artifact_registry_ui` feature flag is disabled' do
          before do
            stub_feature_flags(artifact_registry_ui: false)
          end

          it_behaves_like 'a hidden setup mount'
        end

        it_behaves_like 'a surface gated on a configured Artifact Registry base URL', 'a hidden setup mount'
      end

      context 'when the organization has a mapping row' do
        let_it_be(:mapping) { create(:artifact_registry_namespace_mapping, organization: organization) }

        let(:client) { instance_double(ArtifactRegistry::Client) }
        let(:status) { 'active' }
        let(:namespace) do
          ArtifactRegistry::Namespace.new(
            'id' => mapping.ar_namespace_id, 'slug' => 'acme', 'status' => status,
            'created_at' => '2026-01-01T00:00:00Z'
          )
        end

        before do
          # CachesClient memoizes under :artifact_registry_client, so that is the
          # key to clear to keep a doubled client from leaking across examples.
          organization.clear_memoization(:artifact_registry_client)
          allow(ArtifactRegistry::Client).to receive(:new).and_return(client)
          allow(client).to receive(:namespace).and_return(namespace)
        end

        def redirect_target
          artifact_registry_repositories_organization_path(organization, 'acme')
        end

        # Every resolved status redirects, including non-read-serving ones such as
        # disabled; distinguishing them is a follow-up (see MR description).
        context 'and the slug resolves' do
          context 'for an owner' do
            before_all do
              create(:organization_user, :owner, organization: organization, user: user)
            end

            %w[active suspended disabled blocked something-unrecognized].each do |resolved_status|
              context "when the status is #{resolved_status}" do
                let(:status) { resolved_status }

                it 'redirects to the slug-scoped repositories route', :aggregate_failures do
                  gitlab_request

                  expect(response).to redirect_to(redirect_target)
                  expect(mount_element).to be_nil
                end
              end
            end
          end

          context 'for a member holding only the read ability' do
            before_all do
              create(:organization_user, organization: organization, user: user)
            end

            it 'redirects to the slug-scoped repositories route' do
              gitlab_request

              expect(response).to redirect_to(redirect_target)
            end
          end
        end

        context 'and the slug does not resolve' do
          before_all do
            create(:organization_user, :owner, organization: organization, user: user)
          end

          context 'when Artifact Registry answers an authorization failure' do
            before do
              allow(client).to receive(:namespace)
                .and_raise(ArtifactRegistry::Client::AuthorizationError.new('forbidden', status: 403))
            end

            it_behaves_like 'the unavailable page'
          end

          context 'when Artifact Registry is unreachable' do
            before do
              allow(client).to receive(:namespace)
                .and_raise(ArtifactRegistry::Client::UnavailableError.new('boom'))
            end

            it_behaves_like 'the unavailable page'
          end

          context 'when the namespace is absent (an Artifact Registry 404)' do
            before do
              allow(client).to receive(:namespace).and_return(nil)
            end

            it_behaves_like 'a hidden setup mount'
          end
        end
      end

      context 'with no mapping row, the flag-off and forbidden responses match' do
        before_all do
          create(:organization_user, organization: organization, user: user)
        end

        # The CSP nonce on the error page's inline script changes per request, so it
        # is normalized before the byte comparison.
        def normalized_body
          response.body.gsub(/nonce="[^"]+"/, 'nonce="NONCE"')
        end

        it 'returns a not-found byte-identical to the flag-off response', :aggregate_failures do
          get artifact_registry_organization_index_path(organization)
          member_body = normalized_body
          member_status = response.status

          stub_feature_flags(artifact_registry_ui: false)
          get artifact_registry_organization_index_path(organization)

          expect(response.status).to eq(member_status)
          expect(normalized_body).to eq(member_body)
        end
      end
    end
  end
end
