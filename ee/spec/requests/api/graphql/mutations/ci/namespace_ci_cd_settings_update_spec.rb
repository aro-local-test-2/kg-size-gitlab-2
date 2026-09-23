# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'NamespaceCiCdSettingsUpdate', feature_category: :continuous_integration do
  include GraphqlHelpers

  let_it_be_with_reload(:namespace) { create(:group, :public) }

  let(:variables) do
    {
      full_path: namespace.full_path,
      allow_stale_runner_pruning: false
    }
  end

  let(:mutation) { graphql_mutation(:namespace_ci_cd_settings_update, variables) }

  before_all do
    namespace.ci_cd_settings.update!(allow_stale_runner_pruning: true)
  end

  subject(:request) { post_graphql_mutation(mutation, current_user: user) }

  context 'when unauthorized' do
    let(:user) { create(:user) }

    shared_examples 'unauthorized' do
      it 'returns an error' do
        request

        expect(graphql_errors).not_to be_empty
      end
    end

    context 'when not a namespace member' do
      it_behaves_like 'unauthorized'
    end

    context 'when a non-admin namespace member' do
      before do
        namespace.add_developer(user)
      end

      it_behaves_like 'unauthorized'
    end
  end

  context 'when authorized' do
    let_it_be(:owner) { create(:user) }

    let(:user) { owner }

    before do
      namespace.add_owner(owner)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :update_ci_namespace_settings do
      let(:user) { owner }
      let(:boundary_object) { namespace }
      let(:mutation) { graphql_mutation(:namespace_ci_cd_settings_update, variables, 'errors') }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end

    it 'updates allow_stale_runner_pruning?' do
      request

      expect(namespace.reload.ci_cd_settings.allow_stale_runner_pruning?).to be(false)
    end

    it 'does not update allow_stale_runner_pruning? if not specified' do
      variables.except!(:allow_stale_runner_pruning)

      request

      expect(namespace.reload.ci_cd_settings.allow_stale_runner_pruning?).to be(true)
    end

    context 'when bad arguments are provided' do
      let(:variables) { { full_path: '' } }

      it 'returns the errors' do
        request

        expect(graphql_errors).not_to be_empty
      end
    end
  end
end
