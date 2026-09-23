# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::OrganizationsController, feature_category: :artifact_registry do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:member) { create(:user) }
  let_it_be(:owner) { create(:user) }

  let(:user) { member }

  before_all do
    create(:organization_user, organization: organization, user: member)
    create(:organization_owner, organization: organization, user: owner)
  end

  before do
    sign_in(user)
  end

  describe 'GET #show' do
    subject(:show_request) { get organization_path(organization) }

    it 'pushes the artifact_registry_ui feature flag as enabled to the frontend' do
      show_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to have_pushed_frontend_feature_flags(artifactRegistryUi: true)
    end

    context 'when the artifact_registry_ui feature flag is disabled' do
      before do
        stub_feature_flags(artifact_registry_ui: false)
      end

      it 'pushes the artifact_registry_ui feature flag as disabled to the frontend' do
        show_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).to have_pushed_frontend_feature_flags(artifactRegistryUi: false)
      end
    end

    describe 'the Artifact Registry link' do
      let(:setup_path) { "/o/#{organization.path}/-/artifact_registry" }
      let(:repositories_path) { "#{setup_path}/my-registry/repositories" }

      def artifact_registry_path
        show_request

        app_data = Nokogiri::HTML(response.body).at('#js-organizations-show')['data-app-data']

        Gitlab::Json::SafeParser.parse(app_data)['artifact_registry_path']
      end

      def stub_resolution(resolved)
        allow_next_found_instance_of(ArtifactRegistry::NamespaceMapping) do |mapping|
          allow(mapping).to receive(:registry).and_return(resolved)
        end
      end

      def registry(status:, slug: 'my-registry')
        ArtifactRegistry::NamespaceMapping::Registry.new(slug: slug, status: status, created_at: nil)
      end

      context 'with no mapping row' do
        context 'when the viewer holds the update ability' do
          let(:user) { owner }

          it 'points at the setup page' do
            expect(artifact_registry_path).to eq(setup_path)
          end
        end

        context 'when the viewer holds only the read ability' do
          it 'renders no link, so no member is offered a route that answers not-found' do
            expect(artifact_registry_path).to be_nil
          end
        end
      end

      context 'with a mapping row' do
        before_all do
          create(:artifact_registry_namespace_mapping, organization: organization)
        end

        context 'when the handle resolves' do
          %w[active suspended disabled blocked something-unrecognized].each do |status|
            context "when the status is #{status}" do
              before do
                stub_resolution(registry(status: status))
              end

              it 'points at the resolved handle rather than at the stub' do
                expect(artifact_registry_path).to eq(repositories_path)
              end
            end
          end
        end

        context 'when the status is unknown, which carries no handle' do
          before do
            stub_resolution(registry(status: ArtifactRegistry::NamespaceMapping::UNKNOWN_STATUS, slug: nil))
          end

          it 'renders no link' do
            expect(artifact_registry_path).to be_nil
          end
        end

        context 'when the resolution failed' do
          before do
            stub_resolution(ArtifactRegistry::NamespaceMapping::ResolutionFailure.new(error_class: 'x'))
          end

          it 'renders no link' do
            expect(artifact_registry_path).to be_nil
          end
        end
      end

      describe 'resolution ordering' do
        before_all do
          create(:artifact_registry_namespace_mapping, organization: organization)
        end

        shared_examples 'a gate that resolves nothing' do
          it 'renders no link and builds no client', :aggregate_failures do
            expect(::ArtifactRegistry::Client).not_to receive(:new)

            expect(artifact_registry_path).to be_nil
          end
        end

        context 'when the artifact_registry_ui feature flag is disabled' do
          before do
            stub_feature_flags(artifact_registry_ui: false)
          end

          it_behaves_like 'a gate that resolves nothing'
        end

        context 'when the viewer cannot read the artifact registry' do
          before do
            allow(Ability).to receive(:allowed?).and_call_original
            allow(Ability).to receive(:allowed?)
              .with(user, :read_artifact_registry, organization).and_return(false)
          end

          it_behaves_like 'a gate that resolves nothing'
        end

        it_behaves_like 'a surface gated on a configured Artifact Registry base URL',
          'a gate that resolves nothing'
      end
    end
  end
end
