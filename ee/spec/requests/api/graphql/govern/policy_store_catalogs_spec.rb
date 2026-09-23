# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Policy store catalogs', feature_category: :security_policy_management do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }

  let(:catalog_fields) do
    <<~FIELDS
      policyStore {
        triggers { id name }
        rules { id name }
        actions { id name }
      }
    FIELDS
  end

  before do
    stub_licensed_features(security_orchestration_policies: true)
    stub_application_setting(policy_store_experiment_enabled: true)
  end

  shared_examples 'the full catalogs' do |path|
    it 'returns the catalogs from the policy store gem constants' do
      request

      expect(graphql_data_at(*path, :policy_store, :triggers)).to eq(
        ::Gitlab::PolicyStore::Triggers::ALL.map(&:stringify_keys)
      )
      expect(graphql_data_at(*path, :policy_store, :rules)).to eq(
        ::Gitlab::PolicyStore::Rules::ALL.map(&:stringify_keys)
      )
      expect(graphql_data_at(*path, :policy_store, :actions)).to eq(
        ::Gitlab::PolicyStore::Actions::ALL.map(&:stringify_keys)
      )
    end
  end

  describe 'Group.policyStore' do
    let_it_be_with_reload(:group) { create(:group) }

    let(:query) do
      <<~GQL
        { group(fullPath: "#{group.full_path}") { #{catalog_fields} } }
      GQL
    end

    subject(:request) { post_graphql(query, current_user: current_user) }

    before_all do
      group.add_developer(current_user)
    end

    before do
      group.namespace_settings.update!(policy_store_experiment_enabled: true)
    end

    it_behaves_like 'the full catalogs', [:group]

    it 'returns the catalogs when the flag is enabled for the group actor only' do
      stub_feature_flags(security_policies_v2: group)

      request

      expect(graphql_data_at(:group, :policy_store, :triggers)).to be_present
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(security_policies_v2: false)
      end

      it 'returns null, so the flag works as a kill switch on its own' do
        request

        expect(graphql_data_at(:group, :policy_store)).to be_nil
      end
    end

    context 'when the group has not opted into the experiment' do
      before do
        group.namespace_settings.update!(policy_store_experiment_enabled: false)
      end

      it 'returns null' do
        request

        expect(graphql_data_at(:group, :policy_store)).to be_nil
      end
    end

    context 'when the experiment is disabled for the instance' do
      before do
        stub_application_setting(policy_store_experiment_enabled: false)
      end

      it 'returns null' do
        request

        expect(graphql_data_at(:group, :policy_store)).to be_nil
      end
    end

    context 'when the license does not include security orchestration policies' do
      before do
        stub_licensed_features(security_orchestration_policies: false)
      end

      it 'returns null' do
        request

        expect(graphql_data_at(:group, :policy_store)).to be_nil
      end
    end

    context 'on a subgroup' do
      let_it_be_with_reload(:subgroup) { create(:group, parent: group) }

      let(:query) do
        <<~GQL
          { group(fullPath: "#{subgroup.full_path}") { #{catalog_fields} } }
        GQL
      end

      before do
        subgroup.namespace_settings.update!(policy_store_experiment_enabled: true)
      end

      it 'returns null: the experiment is a top-level-group feature' do
        request

        expect(graphql_data_at(:group, :policy_store)).to be_nil
      end
    end
  end

  describe 'Organization.policyStore' do
    let_it_be(:organization) { create(:organization) }
    let(:query) do
      <<~GQL
        { organization(id: "#{organization.to_global_id}") { #{catalog_fields} } }
      GQL
    end

    let_it_be(:organization_user) { create(:organization_user, organization: organization, user: current_user) }

    before do
      ::Organizations::OrganizationSetting.for(organization.id)
        .update!(policy_store_experiment_enabled: true)
    end

    subject(:request) { post_graphql(query, current_user: current_user) }

    it_behaves_like 'the full catalogs', [:organization]

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(security_policies_v2: false)
      end

      it 'returns null' do
        request

        expect(graphql_data_at(:organization, :policy_store)).to be_nil
      end
    end

    context 'when the experiment is disabled for the instance' do
      before do
        stub_application_setting(policy_store_experiment_enabled: false)
      end

      it 'returns null' do
        request

        expect(graphql_data_at(:organization, :policy_store)).to be_nil
      end
    end

    context 'when the license does not include security orchestration policies' do
      before do
        stub_licensed_features(security_orchestration_policies: false)
      end

      it 'returns null' do
        request

        expect(graphql_data_at(:organization, :policy_store)).to be_nil
      end
    end
  end
end
