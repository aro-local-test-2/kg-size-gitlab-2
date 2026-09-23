# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::OrganizationHelper, feature_category: :organization do
  let_it_be(:organization_detail) { build_stubbed(:organization_detail, description_html: '<em>description</em>') }
  let_it_be(:organization) { organization_detail.organization }
  let_it_be(:activity_organization_path) { '/o/default/-/activity.json' }

  describe '#organization_show_app_data' do
    # rubocop:disable RSpec/FactoryBot/AvoidCreate -- persisted records required for the DB queries
    let_it_be(:organization) { create(:common_organization) }
    let_it_be(:user) { create(:user, organization: create(:organization)) }
    let_it_be(:organization_user) { create(:organization_user, organization: organization, user: user) }
    # rubocop:enable RSpec/FactoryBot/AvoidCreate

    let(:can_read_artifact_registry) { true }
    let(:can_update_organization) { true }
    let(:activated) { false }
    let(:resolved_slug) { nil }

    subject(:app_data) { Gitlab::Json.parse(helper.organization_show_app_data(organization)) }

    before do
      stub_config(artifact_registry: { api_url: 'https://artifact-registry.example.com' })
      allow(helper).to receive(:current_user).and_return(user)
      allow(helper).to receive(:can?)
        .with(user, :read_artifact_registry, organization).and_return(can_read_artifact_registry)
      allow(helper).to receive(:can?)
        .with(user, :update_organization, organization).and_return(can_update_organization)
      allow(helper).to receive(:can?)
        .with(user, :delete_organization_user, organization_user).and_return(true)
      allow(organization).to receive_messages(
        artifact_registry_activated?: activated,
        artifact_registry_resolved_slug: resolved_slug
      )
    end

    context 'when the organization has no mapping row' do
      context 'when the viewer holds the update ability' do
        it 'merges the CE data with a path to the setup page' do
          expect(app_data).to eq(
            'organization' => {
              'name' => organization.name,
              'path' => organization.path
            },
            'can_admin_organization' => true,
            'can_leave_organization' => true,
            'organization_user_gid' => organization_user.to_global_id.to_s,
            'artifact_registry_path' => "/o/#{organization.path}/-/artifact_registry"
          )
        end
      end

      context 'when the viewer holds only the read ability' do
        let(:can_update_organization) { false }

        it 'merges no path, so the overview offers a route the viewer cannot open' do
          expect(app_data).not_to have_key('artifact_registry_path')
        end
      end
    end

    context 'when the handle resolves' do
      let(:activated) { true }
      let(:resolved_slug) { 'my-registry' }

      it 'merges the resolved handle\'s repositories path' do
        expect(app_data).to include(
          'artifact_registry_path' => "/o/#{organization.path}/-/artifact_registry/my-registry/repositories"
        )
      end

      context 'when the viewer holds only the read ability' do
        let(:can_update_organization) { false }

        it 'still merges the repositories path, which every member may open' do
          expect(app_data).to include(
            'artifact_registry_path' => "/o/#{organization.path}/-/artifact_registry/my-registry/repositories"
          )
        end
      end
    end

    context 'when the handle does not resolve' do
      let(:activated) { true }

      it 'merges no path, and offers the owner no setup page for a claimed handle' do
        expect(app_data).not_to have_key('artifact_registry_path')
      end
    end

    describe 'resolution ordering' do
      shared_examples 'a gate that resolves nothing' do
        it 'merges no path without resolving against Artifact Registry', :aggregate_failures do
          expect(organization).not_to receive(:artifact_registry_resolved_slug)

          expect(app_data).not_to have_key('artifact_registry_path')
        end
      end

      context 'when the user cannot read the artifact registry' do
        let(:can_read_artifact_registry) { false }

        it_behaves_like 'a gate that resolves nothing'
      end

      context 'when the artifact_registry_ui feature flag is disabled' do
        before do
          stub_feature_flags(artifact_registry_ui: false)
        end

        it_behaves_like 'a gate that resolves nothing'
      end

      context 'when the instance configures no Artifact Registry' do
        before do
          stub_config(artifact_registry: {})
        end

        it_behaves_like 'a gate that resolves nothing'
      end
    end
  end

  describe '#organization_activity_app_data' do
    let_it_be(:expected_event_types) do
      [
        {
          'title' => 'Comment',
          'value' => EventFilter::COMMENTS
        },
        {
          'title' => 'Design',
          'value' => EventFilter::DESIGNS
        },
        {
          'title' => 'Epic',
          'value' => EventFilter::EPIC
        },
        {
          'title' => 'Issue',
          'value' => EventFilter::ISSUE
        },
        {
          'title' => 'Merge',
          'value' => EventFilter::MERGED
        },
        {
          'title' => 'Repository',
          'value' => EventFilter::PUSH
        },
        {
          'title' => 'Membership',
          'value' => EventFilter::TEAM
        },
        {
          'title' => 'Wiki',
          'value' => EventFilter::WIKI
        }
      ]
    end

    before do
      allow(helper).to receive(:activity_organization_path)
        .with(organization, { format: :json })
        .and_return(activity_organization_path)
    end

    it 'returns expected data object' do
      expect(Gitlab::Json.parse(helper.organization_activity_app_data(organization))).to eq(
        {
          'organization_activity_path' => activity_organization_path,
          'organization_activity_event_types' => expected_event_types,
          'organization_activity_all_event' => EventFilter::ALL
        }
      )
    end
  end

  describe '#organization_settings_general_app_data' do
    subject(:app_data) { Gitlab::Json.parse(helper.organization_settings_general_app_data(organization)) }

    before do
      allow(organization).to receive_messages(
        policy_store_experiment_available?: true,
        policy_store_experiment_enabled?: false
      )
    end

    it 'merges the full CE payload with the Policy Store experiment state' do
      expect(organization).to receive(:avatar_url).with(size: 192).and_return('avatar.jpg')
      expect(organization).to receive(:max_group_visibility_level)
        .and_return(Gitlab::VisibilityLevel::PRIVATE)

      expect(app_data).to eq(
        'organization' => {
          'id' => organization.id,
          'name' => organization.name,
          'path' => organization.path,
          'description' => organization.description,
          'avatar' => 'avatar.jpg',
          'visibility_level' => organization.visibility_level
        },
        'max_group_visibility_level' => Gitlab::VisibilityLevel::PRIVATE,
        'organizations_url' => 'http://test.host/o/',
        'preview_markdown_path' => '/o/-/preview_markdown',
        'policy_store_experiment_available' => true,
        'policy_store_experiment_enabled' => false
      )
    end
  end
end
